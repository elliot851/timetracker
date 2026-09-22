import Foundation

/// The logged-in identity, persisted so the app stays logged in until the user
/// signs out. The token authenticates every API call.
struct LoggedInUser: Codable {
    let id: String
    let email: String
    let name: String
    let role: String   // "admin" | "user"

    var isAdmin: Bool { role == "admin" }
}

enum Session {
    static let didChange = Notification.Name("SessionDidChange")

    private static let tokenKey = "sessionToken"
    private static let userKey = "sessionUser"
    private static let apiKey = "apiBaseURL"

    /// The deployed Worker. Overridable via UserDefaults for testing another backend.
    static let defaultAPIBaseURL = "https://timetracker-api.elliot-897.workers.dev"
    static var apiBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: apiKey) ?? ""
            return stored.isEmpty ? defaultAPIBaseURL : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: apiKey) }
    }

    static var token: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static var user: LoggedInUser? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        return try? JSONDecoder().decode(LoggedInUser.self, from: data)
    }

    static var isLoggedIn: Bool { token != nil && user != nil }

    static func save(token: String, user: LoggedInUser) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: userKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
