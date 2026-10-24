import Foundation

/// What the TV agent's `GET /status` returns.
struct TVStatus: Decodable, Equatable {
    var screenOn: Bool
    var locked: Bool
    var lockReason: String?
    var lockMessage: String?
    var rulesOn: Bool?
    var kidsMode: Bool?
    var usedSec: Int?
    var remainingSec: Int?
    var app: String?
    var appLabel: String?
    var volume: Int?
    var muted: Bool?
    var uptimeSec: Int?
    var model: String?
    var android: String?
    var agent: String?
}

enum TVError: LocalizedError {
    case unreachable
    case notPaired
    case wrongToken
    case refused(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unreachable: return "The TV is off or out of reach."
        case .notPaired: return "Add the TV's token in Settings."
        case .wrongToken: return "The TV rejected the token. Check Settings."
        case .refused(let message): return message
        case .badResponse: return "The TV sent something unexpected."
        }
    }
}

/// Speaks to the Peach TV agent (port 8765) on one host. Every call carries the bearer token.
struct TVClient {
    var host: String
    var port: Int
    var token: String
    /// The built-in Tailscale's session for a tailnet address; nil for the normal network.
    var session: URLSession? = nil

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    func send(_ method: String, _ path: String, body: [String: Any]? = nil,
              timeout: TimeInterval = 4) async throws -> Data {
        guard !token.isEmpty else { throw TVError.notPaired }
        let urlHost = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "http://\(urlHost):\(port)\(path)") else { throw TVError.badResponse }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (session ?? Self.session).data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TVError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw TVError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw TVError.wrongToken
        default: throw TVError.refused(Self.message(in: data) ?? "The TV said no (\(http.statusCode)).")
        }
    }

    private static func message(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["error"] as? String
    }
}
