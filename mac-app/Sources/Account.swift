import Foundation

enum Role: String, Codable {
    case admin
    case user

    var label: String { self == .admin ? "Admin" : "User" }
}

struct UserProfile: Codable, Equatable {
    let id: String
    var name: String
    var role: Role
}

/// Who is using the app and what they may see. Local for now (a dev switcher stands
/// in for login); this maps onto Creative Loop accounts when the network arrives.
///
/// - `current` is the logged-in user; recording always writes to their folder.
/// - `viewing` is whose data the Activity page shows. A normal user can only view
///   themselves; an admin may switch to anyone.
final class AccountStore {
    static let shared = AccountStore()
    static let didChange = Notification.Name("AccountStoreDidChange")

    let baseDir: URL
    private(set) var users: [UserProfile] = []
    private(set) var current: UserProfile
    private(set) var viewing: UserProfile

    private var usersDir: URL { baseDir.appendingPathComponent("users", isDirectory: true) }
    private var configURL: URL { baseDir.appendingPathComponent("config.json") }

    private struct Config: Codable { var currentUserId: String }

    private init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeTracker", isDirectory: true)
        baseDir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let usersFolder = base.appendingPathComponent("users", isDirectory: true)
        AccountStore.migrateLooseDataIfNeeded(baseDir: base, usersDir: usersFolder)

        // Ensure a default user exists (admin, so the first person can see everything).
        let defaultId = AccountStore.defaultUserId()
        AccountStore.ensureUser(
            id: defaultId, name: NSFullUserName(), role: .admin, usersDir: usersFolder)

        let loaded = AccountStore.loadUsers(usersDir: usersFolder)
        users = loaded
        let savedId = (try? JSONDecoder().decode(
            Config.self, from: Data(contentsOf: base.appendingPathComponent("config.json"))))?
            .currentUserId
        let start = loaded.first { $0.id == savedId }
            ?? loaded.first { $0.id == defaultId } ?? loaded[0]
        current = start
        viewing = start
    }

    // MARK: - Reads

    var isAdmin: Bool { current.role == .admin }

    func allUsers() -> [UserProfile] { users.sorted { $0.name < $1.name } }

    func userDir(_ id: String) -> URL {
        usersDir.appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Mutations (dev switcher until real login)

    func switchCurrent(to id: String) {
        guard let profile = users.first(where: { $0.id == id }), profile.id != current.id
        else { return }
        current = profile
        viewing = profile
        saveConfig()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func setCurrentRole(_ role: Role) {
        guard current.role != role else { return }
        current.role = role
        upsert(current)
        if role == .user { viewing = current }   // users can only see themselves
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func setViewing(_ id: String) {
        guard isAdmin, let profile = users.first(where: { $0.id == id }) else { return }
        viewing = profile
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Make the server-authenticated user the current account, creating or updating
    /// its local profile. Data folders key off this id, so it must match the server.
    func adoptRemoteUser(id: String, name: String, role: Role) {
        let profile = UserProfile(id: id, name: name, role: role)
        if let index = users.firstIndex(where: { $0.id == id }) {
            users[index] = profile
        } else {
            users.append(profile)
        }
        AccountStore.write(profile, usersDir: usersDir)
        current = profile
        viewing = profile
        saveConfig()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    @discardableResult
    func createUser(name: String, role: Role) -> UserProfile {
        let id = AccountStore.slug(name) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
        let profile = UserProfile(id: id, name: name, role: role)
        AccountStore.write(profile, usersDir: usersDir)
        users.append(profile)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return profile
    }

    private func upsert(_ profile: UserProfile) {
        if let i = users.firstIndex(where: { $0.id == profile.id }) { users[i] = profile }
        AccountStore.write(profile, usersDir: usersDir)
    }

    private func saveConfig() {
        let data = try? JSONEncoder().encode(Config(currentUserId: current.id))
        try? data?.write(to: configURL)
    }

    // MARK: - Persistence helpers

    private static func loadUsers(usersDir: URL) -> [UserProfile] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: usersDir.path)) ?? []
        return entries.compactMap { id in
            let file = usersDir.appendingPathComponent(id).appendingPathComponent("profile.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(UserProfile.self, from: data)
        }
    }

    private static func ensureUser(id: String, name: String, role: Role, usersDir: URL) {
        let profileFile = usersDir.appendingPathComponent(id).appendingPathComponent("profile.json")
        guard !FileManager.default.fileExists(atPath: profileFile.path) else { return }
        write(UserProfile(id: id, name: name, role: role), usersDir: usersDir)
    }

    private static func write(_ profile: UserProfile, usersDir: URL) {
        let dir = usersDir.appendingPathComponent(profile.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(profile).write(to: dir.appendingPathComponent("profile.json"))
    }

    /// Moves the pre-accounts single-user data into the default user's folder once.
    private static func migrateLooseDataIfNeeded(baseDir: URL, usersDir: URL) {
        let fm = FileManager.default
        let looseScreens = baseDir.appendingPathComponent("screenshots")
        let looseShifts = baseDir.appendingPathComponent("shifts.json")
        let hasLoose = fm.fileExists(atPath: looseScreens.path)
            || fm.fileExists(atPath: looseShifts.path)
        guard hasLoose, !fm.fileExists(atPath: usersDir.path) else { return }

        let target = usersDir.appendingPathComponent(defaultUserId(), isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["screenshots", "activity", "shifts.json", "tracker.log"] {
            let src = baseDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.moveItem(at: src, to: target.appendingPathComponent(name))
        }
    }

    private static func defaultUserId() -> String { slug(NSUserName()) }

    private static func slug(_ text: String) -> String {
        let allowed = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(allowed)
        return joined.isEmpty ? "user" : joined
    }
}
