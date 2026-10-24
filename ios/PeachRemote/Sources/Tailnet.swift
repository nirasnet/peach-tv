import Foundation
import TailscaleKit

/// The built-in Tailscale: the app is its own small node on the family tailnet, so the TV answers away from
/// home without the Tailscale app or a VPN switch. It joins once with an invite key, keeps its node state in
/// Application Support, and runs only while the app is open (TV calls go through its local SOCKS proxy).
actor Tailnet {
    static let shared = Tailnet()

    enum State: Equatable {
        case notSetUp
        case off
        case connecting
        case connected
        case failed(String)
    }

    enum Failure: LocalizedError {
        case notJoined
        case timedOut
        var errorDescription: String? {
            switch self {
            case .notJoined: return "Away-from-home access isn't set up on this iPhone yet."
            case .timedOut: return "Couldn't reach Tailscale. Check the internet connection."
            }
        }
    }

    private static let joinedKey = "tailnetJoined"
    private static let nameKey = "tailnetHostName"

    nonisolated static var isJoined: Bool { UserDefaults.standard.bool(forKey: joinedKey) }

    private var node: TailscaleNode?
    private var session: URLSession?
    private var starting: Task<URLSession, Error>?
    private var onChange: (@Sendable (State) -> Void)?
    private(set) var state: State = Tailnet.isJoined ? .off : .notSetUp {
        didSet { if state != oldValue { onChange?(state) } }
    }

    func observe(_ handler: @escaping @Sendable (State) -> Void) {
        onChange = handler
        handler(state)
    }

    /// A URLSession that goes through the tailnet, starting the node when needed.
    func urlSession() async throws -> URLSession {
        if let session { return session }
        guard Self.isJoined else { throw Failure.notJoined }
        return try await start(authKey: nil)
    }

    /// Joins the tailnet with an invite key (a reusable, pre-approved, tagged Tailscale auth key).
    func join(authKey: String) async throws {
        await stop()
        try? FileManager.default.removeItem(at: Self.directory)
        UserDefaults.standard.set(false, forKey: Self.joinedKey)
        do {
            _ = try await start(authKey: authKey)
        } catch {
            await stop()
            state = .failed(Self.describe(error))
            throw error
        }
    }

    /// Stops the node (the app went to the background). It comes back on the next call.
    func stop() async {
        starting?.cancel()
        starting = nil
        session?.invalidateAndCancel()
        session = nil
        if let node { try? await node.close() }
        node = nil
        if state != .notSetUp { state = Self.isJoined ? .off : .notSetUp }
    }

    /// Leaves the tailnet on this iPhone. Remove the node in the Tailscale admin console too.
    func leave() async {
        await stop()
        try? FileManager.default.removeItem(at: Self.directory)
        UserDefaults.standard.set(false, forKey: Self.joinedKey)
        state = .notSetUp
    }

    // MARK: Private

    private func start(authKey: String?) async throws -> URLSession {
        if let starting { return try await starting.value }
        let task = Task { () throws -> URLSession in
            try await self.bringUp(authKey: authKey)
        }
        starting = task
        defer { starting = nil }
        do {
            let s = try await task.value
            session = s
            state = .connected
            return s
        } catch {
            if node != nil { try? await node?.close() }
            node = nil
            state = .failed(Self.describe(error))
            throw error
        }
    }

    private func bringUp(authKey: String?) async throws -> URLSession {
        state = .connecting
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let config = Configuration(hostName: Self.hostName, path: Self.directory.path, authKey: authKey,
                                   controlURL: kDefaultControlURL, ephemeral: false)
        let node = try TailscaleNode(config: config, logger: TailnetLog())
        self.node = node
        // up() waits for the login; a bad key or no internet must not hang the app.
        try await Self.withTimeout(authKey == nil ? 20 : 40) { try await node.up() }
        UserDefaults.standard.set(true, forKey: Self.joinedKey)
        let config2: URLSessionConfiguration = try await URLSessionConfiguration.tailscaleSession(node).0
        config2.requestCachePolicy = .reloadIgnoringLocalCacheData
        config2.timeoutIntervalForResource = 20
        config2.waitsForConnectivity = false
        return URLSession(configuration: config2)
    }

    /// up() is a blocking C call that ignores cancellation, so race it instead of awaiting it in a task group.
    private static func withTimeout(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> Void) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    try await operation()
                    if once.claim() { continuation.resume() }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() { continuation.resume(throwing: Failure.timedOut) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tailscale", isDirectory: true)
    }

    /// "peach-iphone-k3f9", the same on every start, so the admin console shows one node per phone.
    private static var hostName: String {
        if let name = UserDefaults.standard.string(forKey: nameKey) { return name }
        let letters = "abcdefghijkmnpqrstuvwxyz23456789"
        let name = "peach-iphone-" + String((0..<4).map { _ in letters.randomElement()! })
        UserDefaults.standard.set(name, forKey: nameKey)
        return name
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? Failure { return failure.errorDescription ?? "Failed" }
        if case let TailscaleError.internalError(details?) = error { return details }
        if case let TailscaleError.posixError(_, details?) = error { return details }
        return "Couldn't join (\(error))"
    }
}

/// Tailscale's messages go to the Xcode console in debug builds only.
struct TailnetLog: LogSink {
    var logFileHandle: Int32? = nil
    func log(_ message: String) {
        #if DEBUG
        print("[tailnet] \(message)")
        #endif
    }
}

/// peachtv://join?k=<auth key>&t=<agent token>&ts=<TV tailnet IP>&lan=<TV LAN IP>&p=<port>
struct Invite: Equatable {
    var authKey: String
    var token: String
    var tailscaleHost: String
    var lanHost: String
    var port: Int

    init?(url: URL) {
        guard url.scheme == "peachtv", url.host == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let k = value("k"), k.hasPrefix("tskey-"), let t = value("t"), !t.isEmpty,
              let ts = value("ts"), !ts.isEmpty else { return nil }
        authKey = k
        token = t
        tailscaleHost = ts
        lanHost = value("lan") ?? ""
        port = value("p").flatMap(Int.init) ?? 8765
    }

    static func url(authKey: String, settings: TVSettings) -> URL? {
        var c = URLComponents()
        c.scheme = "peachtv"
        c.host = "join"
        c.queryItems = [
            URLQueryItem(name: "k", value: authKey),
            URLQueryItem(name: "t", value: settings.token),
            URLQueryItem(name: "ts", value: settings.tailscaleHost),
            URLQueryItem(name: "lan", value: settings.lanHost),
            URLQueryItem(name: "p", value: String(settings.port)),
        ]
        return c.url
    }
}
