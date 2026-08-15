import Foundation
import Observation

/// Persists the login session (server list, per-server tokens, username) in the
/// Keychain so the app can restore the active session across launches.
@MainActor
@Observable
final class AuthSessionStore {
    private enum Keys {
        static let servers = "servers"
        static let activeServer = "activeServer"
        static let accountToken = "accountToken"
        static let userToken = "userToken"
        static let username = "username"
    }

    /// Offizieller FiveNet-Demo-Server. Wird im Server-Selector als
    /// „Demo-Server“ angeboten, muss aber nicht Teil der persistierten Liste
    /// sein (wird erst bei Verbindung hinzugefügt).
    static let demoServer = URL(string: "https://demo.fivenet.app")!

    var isDemoServerActive: Bool {
        activeServer == Self.demoServer
    }

    /// All servers the user has added, in order.
    private(set) var servers: [URL] = []
    /// The server currently selected.
    private(set) var activeServer: URL?

    private(set) var accountToken: String?
    private(set) var userToken: String?
    private(set) var username: String?

    init() {
        loadServers()
        loadActiveServer()
        migrateLegacySession()
        if let activeServer {
            loadSession(for: activeServer)
        }
    }

    var serverURL: URL? { activeServer }

    var hasStoredSession: Bool {
        activeServer != nil && (userToken != nil || accountToken != nil)
    }

    // MARK: - Server list

    /// Adds the server to the list (if not already present) and activates it.
    /// The existing session of a previously added server is restored.
    func setServerURL(_ url: URL) {
        if !servers.contains(url) {
            servers.append(url)
        }
        activate(url)
    }

    func activate(_ url: URL) {
        activeServer = url
        loadSession(for: url)
        persistServers()
        persistActiveServer()
    }

    func removeServer(_ url: URL) {
        servers.removeAll { $0 == url }
        clearKeys(for: url)
        if activeServer == url {
            activeServer = servers.first
            if let activeServer {
                loadSession(for: activeServer)
            } else {
                accountToken = nil
                userToken = nil
                username = nil
            }
        }
        persistServers()
        persistActiveServer()
    }

    func clearSession() {
        guard let activeServer else { return }
        accountToken = nil
        userToken = nil
        username = nil
        clearKeys(for: activeServer)
    }

    // MARK: - Session values

    func setUsername(_ name: String) {
        guard let activeServer else { return }
        username = name
        KeychainStore.save(name, for: sessionKey(Keys.username, server: activeServer))
    }

    func update(accountToken: String? = nil, userToken: String? = nil) {
        guard let activeServer else { return }
        if let accountToken {
            self.accountToken = accountToken
            KeychainStore.save(accountToken, for: sessionKey(Keys.accountToken, server: activeServer))
        }
        if let userToken {
            self.userToken = userToken
            KeychainStore.save(userToken, for: sessionKey(Keys.userToken, server: activeServer))
        }
    }

    // MARK: - Persistence

    private func loadServers() {
        servers = KeychainStore.load(Keys.servers)?
            .split(separator: "\n")
            .map(String.init)
            .compactMap(URL.init(string:)) ?? []
    }

    private func loadActiveServer() {
        if let stored = KeychainStore.load(Keys.activeServer).flatMap(URL.init(string:)), servers.contains(stored) {
            activeServer = stored
        } else {
            activeServer = servers.first
        }
    }

    private func persistActiveServer() {
        if let activeServer {
            KeychainStore.save(activeServer.absoluteString, for: Keys.activeServer)
        } else {
            KeychainStore.delete(Keys.activeServer)
        }
    }

    private func persistServers() {
        let serialized = servers.map(\.absoluteString).joined(separator: "\n")
        if serialized.isEmpty {
            KeychainStore.delete(Keys.servers)
        } else {
            KeychainStore.save(serialized, for: Keys.servers)
        }
    }

    private func loadSession(for url: URL) {
        accountToken = KeychainStore.load(sessionKey(Keys.accountToken, server: url))
        userToken = KeychainStore.load(sessionKey(Keys.userToken, server: url))
        username = KeychainStore.load(sessionKey(Keys.username, server: url))
    }

    private func clearKeys(for url: URL) {
        for key in [Keys.accountToken, Keys.userToken, Keys.username] {
            KeychainStore.delete(sessionKey(key, server: url))
        }
    }

    private func sessionKey(_ key: String, server url: URL) -> String {
        "\(url.absoluteString)#\(key)"
    }

    /// One-time migration from the single-server layout (plain `serverURL` /
    /// `accountToken` / ... keys) to the per-server layout.
    private func migrateLegacySession() {
        guard let legacy = KeychainStore.load("serverURL").flatMap(URL.init(string:)) else { return }
        let acc = KeychainStore.load("accountToken")
        let user = KeychainStore.load("userToken")
        let name = KeychainStore.load("username")

        if !servers.contains(legacy) {
            servers.insert(legacy, at: 0)
        }
        activeServer = legacy
        persistServers()
        persistActiveServer()
        KeychainStore.delete("serverURL")

        if let acc {
            accountToken = acc
            KeychainStore.save(acc, for: sessionKey(Keys.accountToken, server: legacy))
            KeychainStore.delete("accountToken")
        }
        if let user {
            userToken = user
            KeychainStore.save(user, for: sessionKey(Keys.userToken, server: legacy))
            KeychainStore.delete("userToken")
        }
        if let name {
            username = name
            KeychainStore.save(name, for: sessionKey(Keys.username, server: legacy))
            KeychainStore.delete("username")
        }
    }
}
