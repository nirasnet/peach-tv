import Foundation
import Security

/// Where to find the TV. The token lives in the Keychain; the hosts in UserDefaults.
struct TVSettings: Equatable {
    var tailscaleHost: String
    var lanHost: String
    var port: Int
    var token: String

    var hosts: [String] {
        [tailscaleHost, lanHost]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func load() -> TVSettings {
        let defaults = UserDefaults.standard
        let token = Keychain.read() ?? {
            if !DefaultPairing.token.isEmpty { Keychain.write(DefaultPairing.token) }
            return DefaultPairing.token
        }()
        return TVSettings(
            tailscaleHost: defaults.string(forKey: "tailscaleHost") ?? DefaultPairing.tailscaleHost,
            lanHost: defaults.string(forKey: "lanHost") ?? DefaultPairing.lanHost,
            port: defaults.object(forKey: "port") as? Int ?? DefaultPairing.port,
            token: token)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(tailscaleHost, forKey: "tailscaleHost")
        defaults.set(lanHost, forKey: "lanHost")
        defaults.set(port, forKey: "port")
        Keychain.write(token)
    }

    static func describe(host: String) -> String {
        host.hasPrefix("100.") || host.hasPrefix("fd7a:") || host.hasSuffix(".ts.net") ? "Tailscale" : "home Wi-Fi"
    }
}

enum Keychain {
    /// The Tailscale invite key (auth key) kept on the parent's iPhone to make family invites.
    static let inviteKey = "tailscale-invite-key"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.example.PeachRemote",
            kSecAttrAccount as String: account,
        ]
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    static func read(account: String = "tv-token") -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String = "tv-token") {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
