import SwiftUI
import UIKit

@MainActor
final class RemoteModel: ObservableObject {
    enum Connection: Equatable {
        case checking
        case online(host: String, latencyMs: Int)
        case offline
    }

    @Published var settings: TVSettings
    @Published private(set) var connection: Connection = .checking
    @Published private(set) var status: TVStatus?
    @Published private(set) var lastSeen: Date?
    @Published private(set) var snapshot: UIImage?
    @Published private(set) var snapshotTime: Date?
    @Published private(set) var busy: String?
    @Published var toast: String?
    @Published private(set) var today: ActivityDay?
    @Published private(set) var rules: RulesState?
    @Published private(set) var look: LockLook?
    @Published private(set) var lookUnsupported = false
    @Published private(set) var kids: KidsState?
    /// The built-in Tailscale (Tailnet.swift).
    @Published private(set) var tailnet: Tailnet.State = Tailnet.isJoined ? .off : .notSetUp
    /// An invite link that was opened, waiting for "Join".
    @Published var pendingInvite: Invite?

    private var todayFetched = Date.distantPast

    private var preferredHost: String?
    private var pollTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        settings = TVSettings.load()
        today = ActivityCache.load(DayKey.string(Date()))?.0
        if let seen = UserDefaults.standard.object(forKey: "lastSeen") as? Date { lastSeen = seen }
        Task { [weak self] in
            await Tailnet.shared.observe { state in
                Task { @MainActor in self?.tailnet = state }
            }
        }
    }

    var isOnline: Bool { if case .online = connection { return true } else { return false } }

    // MARK: Auto check

    /// Polls while the app is on screen: every 5 s while the TV answers, every 8 s while it doesn't.
    func setActive(_ active: Bool) {
        pollTask?.cancel()
        pollTask = nil
        guard active else {
            // The tailnet node's local proxy goes stale while iOS suspends the app: stop it, restart on demand.
            Task { await Tailnet.shared.stop() }
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.isOnline ? 5 : 8))
            }
        }
    }

    func refresh() async {
        if status == nil, !isOnline { connection = .checking }
        do {
            let (data, host, latencyMs) = try await call("GET", "/status")
            let decoded = try JSONDecoder().decode(TVStatus.self, from: data)
            status = decoded
            connection = .online(host: host, latencyMs: latencyMs)
            lastSeen = Date()
            UserDefaults.standard.set(lastSeen, forKey: "lastSeen")
            await loadRules()
            // Kids mode: the full state (with the TV's app list) once, then again when the mode changed on the TV.
            if decoded.kidsMode != nil, kids == nil || kids?.enabled != decoded.kidsMode { await loadKids() }
            if Date().timeIntervalSince(todayFetched) > 30 {
                todayFetched = Date()
                if case .live(let day) = await activity(for: Date()) { today = day }
            }
        } catch is CancellationError {
        } catch TVError.unreachable {
            connection = .offline
        } catch {
            connection = .offline
            show(error)
        }
    }

    // MARK: Actions

    func turnOff() async {
        await perform("Turning off…", "POST", "/sleep", done: "TV turned off 🌙")
    }

    func wake() async {
        await perform("Waking…", "POST", "/wake", done: "Waking the TV ☀️")
    }

    func lock(message: String) async {
        await perform("Locking…", "POST", "/lock", body: ["message": message], done: "TV locked 🍑🔒")
    }

    func unlock() async {
        await perform("Unlocking…", "POST", "/unlock", done: "TV unlocked")
    }

    func send(message: String) async {
        await perform("Sending…", "POST", "/message", body: ["text": message], done: "Message on the TV 💬")
    }

    func takeSnapshot() async {
        busy = "Snapping…"
        defer { busy = nil }
        do {
            let (data, _, _) = try await call("GET", "/screenshot", timeout: 12)
            guard let image = UIImage(data: data) else { throw TVError.badResponse }
            snapshot = image
            snapshotTime = Date()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            show(error)
        }
    }

    // MARK: Family rules

    func loadRules() async {
        guard let (data, _, _) = try? await call("GET", "/rules"),
              let state = try? JSONDecoder().decode(RulesState.self, from: data) else { return }
        rules = state
    }

    @discardableResult
    func saveRules(_ new: FamilyRules, done: String = "Rules saved on the TV ✅") async -> Bool {
        await rulesCall("Saving…", "/rules", new.json, done: done)
    }

    func setRulesEnabled(_ on: Bool) async {
        guard var current = rules?.rules else { return }
        current.enabled = on
        await saveRules(current, done: on ? "Family rules on 🍑" : "Family rules off")
    }

    func addBonus(minutes: Int) async {
        await rulesCall("Adding time…", "/bonus", ["minutes": minutes], done: "+\(minutes) min for today 🎁")
    }

    func pauseToday(_ paused: Bool) async {
        await rulesCall(paused ? "Pausing…" : "Resuming…", "/pause", ["today": paused],
                        done: paused ? "Rules paused until midnight" : "Rules back on for today")
    }

    @discardableResult
    private func rulesCall(_ label: String, _ path: String, _ body: [String: Any], done: String) async -> Bool {
        busy = label
        defer { busy = nil }
        do {
            let (data, _, _) = try await call("POST", path, body: body)
            rules = try JSONDecoder().decode(RulesState.self, from: data)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash(done)
            await refresh()
            return true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show(error)
            return false
        }
    }

    enum ActivityResult {
        case live(ActivityDay)
        case saved(ActivityDay, Date)
        case unavailable(String)
    }

    // MARK: Kids mode

    func loadKids() async {
        guard let (data, _, _) = try? await call("GET", "/kids"),
              let state = try? JSONDecoder().decode(KidsState.self, from: data) else { return }
        kids = state
    }

    func setKidsMode(_ on: Bool) async {
        await saveKids(["enabled": on], done: on ? "Kids mode on 🧸" : "Parent mode 👨‍👩‍👧 all apps")
    }

    @discardableResult
    func saveKids(_ body: [String: Any], done: String) async -> Bool {
        busy = "Saving…"
        defer { busy = nil }
        do {
            let (data, _, _) = try await call("POST", "/kids", body: body)
            kids = try JSONDecoder().decode(KidsState.self, from: data)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash(done)
            await refresh()
            return true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show(error)
            return false
        }
    }

    // MARK: Lock screen look

    func loadLook() async {
        do {
            let (data, _, _) = try await call("GET", "/look")
            look = try JSONDecoder().decode(LookState.self, from: data).look
            lookUnsupported = false
        } catch TVError.refused {
            lookUnsupported = true
        } catch {}
    }

    func saveLook(_ new: LockLook) async -> Bool {
        busy = "Saving…"
        defer { busy = nil }
        do {
            let (data, _, _) = try await call("POST", "/look", body: new.json)
            look = try JSONDecoder().decode(LookState.self, from: data).look
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("Lock screen saved on the TV 🎨")
            return true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show(error)
            return false
        }
    }

    func previewLook(_ draft: LockLook, kind: String) async {
        var body = draft.json
        body["kind"] = kind
        await perform("Showing…", "POST", "/look/preview", body: body, done: "On the TV for 10 s 👀")
    }

    /// History snapshots for a day: live from the TV, or the phone's copy when the TV is off.
    func snaps(for date: Date) async -> SnapDay? {
        let key = DayKey.string(date)
        if let (data, _, _) = try? await call("GET", "/snaps?date=\(key)", timeout: 6),
           let day = try? JSONDecoder().decode(SnapDay.self, from: data) {
            SnapCache.saveList(data, for: key)
            SnapCache.prune(keepDays: day.keepDays)
            return day
        }
        return SnapCache.list(key)
    }

    func snapImage(day: String, _ name: String) async -> UIImage? {
        if let cached = SnapCache.image(day, name) { return cached }
        let path = "/snap?date=\(day)&name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
        guard let (data, _, _) = try? await call("GET", path, timeout: 10) else { return nil }
        return SnapCache.store(data, day, name)
    }

    /// A day of history from the TV, or the copy saved last time when the TV is off.
    func activity(for date: Date) async -> ActivityResult {
        let key = DayKey.string(date)
        do {
            let (data, _, _) = try await call("GET", "/activity?date=\(key)", timeout: 6)
            let day = try JSONDecoder().decode(ActivityDay.self, from: data)
            ActivityCache.save(data, for: key)
            if key == DayKey.string(Date()) { today = day }
            return .live(day)
        } catch {
            if let (day, saved) = ActivityCache.load(key) { return .saved(day, saved) }
            return .unavailable((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func unlockCode() async -> String? {
        guard let (data, _, _) = try? await call("GET", "/config"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["unlockCode"] as? String
    }

    // MARK: Away from home (built-in Tailscale)

    var viaBuiltInTailscale: Bool {
        guard case .online(let host, _) = connection else { return false }
        return Tailnet.isJoined && host == settings.tailscaleHost.trimmingCharacters(in: .whitespaces)
    }

    func open(_ url: URL) {
        if let invite = Invite(url: url) { pendingInvite = invite } else { flash("That link isn't a Peach TV invite.") }
    }

    /// Joins with an invite (from a link or a QR code): the TV's address and token, and the tailnet key.
    func accept(_ invite: Invite) async {
        var next = settings
        next.token = invite.token
        next.tailscaleHost = invite.tailscaleHost
        if !invite.lanHost.isEmpty { next.lanHost = invite.lanHost }
        next.port = invite.port
        settings = next
        next.save()
        preferredHost = nil
        status = nil
        await join(authKey: invite.authKey)
        if case .failed = tailnet { await refresh() }
    }

    /// Joins this iPhone to the tailnet (the parent's own phone, with the key from Settings).
    func join(authKey: String) async {
        busy = "Joining…"
        defer { busy = nil }
        do {
            try await Tailnet.shared.join(authKey: authKey)
            preferredHost = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("Set up 🎉 The TV works away from home now")
            await refresh()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show(error)
        }
    }

    func leaveTailnet() async {
        await Tailnet.shared.leave()
        preferredHost = nil
        flash("Away-from-home access removed from this iPhone")
        await refresh()
    }

    func apply(_ newSettings: TVSettings) {
        settings = newSettings
        newSettings.save()
        preferredHost = nil
        status = nil
        connection = .checking
        Task { await refresh() }
    }

    // MARK: Plumbing

    private func perform(_ label: String, _ method: String, _ path: String,
                         body: [String: Any]? = nil, done: String) async {
        busy = label
        defer { busy = nil }
        do {
            _ = try await call(method, path, body: body ?? (method == "POST" ? [:] : nil))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash(done)
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            show(error)
        }
    }

    /// Tries the host that answered last, then the others (Tailscale first, then the home Wi-Fi).
    private func call(_ method: String, _ path: String, body: [String: Any]? = nil,
                      timeout: TimeInterval = 4) async throws -> (Data, String, Int) {
        var hosts = settings.hosts
        let tailnetHost = settings.tailscaleHost.trimmingCharacters(in: .whitespaces)
        let builtIn = Tailnet.isJoined && !tailnetHost.isEmpty
        // The built-in Tailscale takes a few seconds to start: try the home Wi-Fi first unless the tailnet answered last.
        if builtIn, preferredHost == nil, let index = hosts.firstIndex(of: tailnetHost), hosts.count > 1 {
            hosts.append(hosts.remove(at: index))
        }
        if let preferredHost, let index = hosts.firstIndex(of: preferredHost) {
            hosts.insert(hosts.remove(at: index), at: 0)
        }
        guard !hosts.isEmpty else { throw TVError.notPaired }
        for host in hosts {
            var client = TVClient(host: host, port: settings.port, token: settings.token)
            var timeout = timeout
            if builtIn && host == tailnetHost {
                guard let session = try? await Tailnet.shared.urlSession() else { continue }
                client.session = session
                timeout = max(timeout, 10)
            }
            do {
                let start = Date()
                let data = try await client.send(method, path, body: body, timeout: timeout)
                preferredHost = host
                return (data, host, Int(Date().timeIntervalSince(start) * 1000))
            } catch TVError.unreachable {
                continue
            }
        }
        throw TVError.unreachable
    }

    private func show(_ error: Error) {
        flash((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
