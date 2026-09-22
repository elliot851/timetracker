import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The server is not configured yet."
        case .server(let message): return message
        }
    }
}

/// Talks to the TimeTracker Worker. Auth endpoints are open; everything else sends
/// the saved bearer token.
enum APIClient {
    private struct AuthResponse: Codable { let token: String; let user: LoggedInUser }

    static func login(email: String, password: String) async throws -> LoggedInUser {
        try await authenticate(path: "/api/login", email: email, password: password)
    }

    struct RegisterResult { let pending: Bool; let user: LoggedInUser? }
    private struct RegisterResponse: Codable { let pending: Bool?; let token: String?; let user: LoggedInUser? }

    /// Registration now returns `pending` (a code was emailed) rather than a session.
    static func register(email: String, password: String) async throws -> RegisterResult {
        let r: RegisterResponse = try await post(
            "/api/register", body: ["email": email, "password": password], authed: false)
        if let token = r.token, let user = r.user {
            Session.save(token: token, user: user)
            return RegisterResult(pending: false, user: user)
        }
        return RegisterResult(pending: true, user: nil)
    }

    static func verifyCode(email: String, code: String) async throws -> LoggedInUser {
        let r: AuthResponse = try await post(
            "/api/verify", body: ["email": email, "code": code], authed: false)
        Session.save(token: r.token, user: r.user)
        return r.user
    }

    static func resendCode(email: String) async throws {
        _ = try await postRaw("/api/resend-code",
            body: try JSONSerialization.data(withJSONObject: ["email": email]), authed: false)
    }

    static func requestReset(email: String) async throws {
        _ = try await postRaw("/api/request-reset",
            body: try JSONSerialization.data(withJSONObject: ["email": email]), authed: false)
    }

    static func resetPassword(email: String, code: String, password: String) async throws -> LoggedInUser {
        let r: AuthResponse = try await post(
            "/api/reset", body: ["email": email, "code": code, "password": password], authed: false)
        Session.save(token: r.token, user: r.user)
        return r.user
    }

    private static func authenticate(
        path: String, email: String, password: String
    ) async throws -> LoggedInUser {
        let response: AuthResponse = try await post(
            path, body: ["email": email, "password": password], authed: false)
        Session.save(token: response.token, user: response.user)
        return response.user
    }

    static func logout() async {
        _ = try? await postRaw("/api/logout", body: Data(), authed: true)
        Session.clear()
    }

    // MARK: - Data sync (fire-and-forget; failures are logged, not fatal)

    static func sendJSON(_ path: String, _ body: Any) async {
        guard Session.isLoggedIn else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            _ = try await postRaw(path, body: data, authed: true)
        } catch {
            Log.write("Sync failed \(path):\(error.localizedDescription)")
        }
    }

    /// Uploads raw JPEG bytes to R2 via the Worker. Returns true on success so the
    /// caller can retry later (e.g. once R2 is enabled).
    @discardableResult
    static func uploadShot(key: String, data: Data) async -> Bool {
        guard Session.isLoggedIn, let token = Session.token else { return false }
        guard let base = URL(string: Session.apiBaseURL + "/api/upload?key=" + key
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) else { return false }
        var request = URLRequest(url: base)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)
        } catch {
            return false
        }
    }

    // MARK: - Request plumbing

    private static func url(_ path: String) throws -> URL {
        let base = Session.apiBaseURL
        guard !base.isEmpty, let url = URL(string: base + path) else { throw APIError.notConfigured }
        return url
    }

    private static func post<T: Decodable>(
        _ path: String, body: [String: Any], authed: Bool
    ) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        let result = try await postRaw(path, body: data, authed: authed)
        return try JSONDecoder().decode(T.self, from: result)
    }

    @discardableResult
    private static func postRaw(_ path: String, body: Data, authed: Bool) async throws -> Data {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed, let token = Session.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try check(response, responseData)
        return responseData
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(
                [String: String].self, from: data))?["error"] ?? "Server error (\(http.statusCode))"
            throw APIError.server(message)
        }
    }
}
