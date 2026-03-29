// APIClient.swift — LockInBro
// All API calls to https://wahwa.com/api/v1

import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case badRequest(String)
    case conflict(String)
    case serverError(String)
    case decodingError(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please log in again."
        case .badRequest(let msg): return msg
        case .conflict(let msg): return msg
        case .serverError(let msg): return msg
        case .decodingError(let msg): return "Data error: \(msg)"
        case .invalidURL: return "Invalid URL"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let baseURL = "https://wahwa.com/api/v1"
    var token: String?

    /// Called when a refresh attempt fails — AppState hooks into this to force logout.
    var onAuthFailure: (() -> Void)?

    /// Prevents multiple concurrent refresh attempts.
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<Bool, Never>] = []

    // MARK: - Core Request

    private func rawRequest(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError("No HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 409:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Conflict"
            throw APIError.conflict(msg)
        case 400...499:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8) ?? "Bad request"
            throw APIError.badRequest(msg)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)"
            throw APIError.serverError(msg)
        }
    }

    /// Attempt to refresh the access token using the stored refresh token.
    /// Returns true if refresh succeeded. Coalesces concurrent callers so only one
    /// refresh request is in-flight at a time.
    private func attemptTokenRefresh() async -> Bool {
        if isRefreshing {
            // Another call is already refreshing — wait for it
            return await withCheckedContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            // Notify all waiters with the result
            let waiters = refreshContinuations
            refreshContinuations = []
            for waiter in waiters { waiter.resume(returning: token != nil) }
        }

        guard let refreshToken = KeychainService.shared.getRefreshToken() else {
            return false
        }

        do {
            let data = try await rawRequest("/auth/refresh", method: "POST", body: ["refresh_token": refreshToken])
            let decoder = JSONDecoder()
            let response = try decoder.decode(AuthResponse.self, from: data)
            token = response.accessToken
            KeychainService.shared.saveToken(response.accessToken)
            KeychainService.shared.saveRefreshToken(response.refreshToken)
            return true
        } catch {
            print("[APIClient] Token refresh failed: \(error)")
            return false
        }
    }

    /// Main entry point for all authenticated requests.
    /// On 401, attempts a token refresh and retries once. If refresh fails, triggers onAuthFailure.
    private func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> Data {
        do {
            return try await rawRequest(path, method: method, body: body)
        } catch APIError.unauthorized {
            // Don't try to refresh the refresh endpoint itself
            guard path != "/auth/refresh" else { throw APIError.unauthorized }

            let refreshed = await attemptTokenRefresh()
            if refreshed {
                return try await rawRequest(path, method: method, body: body)
            }

            // Refresh failed — force logout
            await MainActor.run { onAuthFailure?() }
            throw APIError.unauthorized
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            let detail: String
            switch error {
            case .keyNotFound(let key, let ctx):
                let path = (ctx.codingPath + [key]).map(\.stringValue).joined(separator: ".")
                detail = "missing key '\(key.stringValue)' (path: \(path))"
            case .valueNotFound(_, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "unexpected null at '\(path)'"
            case .typeMismatch(_, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "wrong type at '\(path)': \(ctx.debugDescription)"
            case .dataCorrupted(let ctx):
                detail = "corrupted data: \(ctx.debugDescription)"
            @unknown default:
                detail = error.localizedDescription
            }
            // Also print raw response for debugging during development
            if let raw = String(data: data, encoding: .utf8) {
                print("[APIClient] Decode failed for \(T.self): \(detail)\nRaw response: \(raw.prefix(500))")
            }
            throw APIError.decodingError(detail)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Auth

    func register(email: String, password: String, displayName: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "display_name": displayName,
            "timezone": TimeZone.current.identifier
        ]
        let data = try await request("/auth/register", method: "POST", body: body)
        return try decode(AuthResponse.self, from: data)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await request("/auth/login", method: "POST", body: body)
        return try decode(AuthResponse.self, from: data)
    }

    func signInWithApple(identityToken: String, authorizationCode: String, fullName: String?) async throws -> AuthResponse {
        var body: [String: Any] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode
        ]
        if let name = fullName { body["full_name"] = name }
        let data = try await request("/auth/apple", method: "POST", body: body)
        return try decode(AuthResponse.self, from: data)
    }

    func registerDeviceToken(platform: String, token deviceToken: String) async throws {
        let body: [String: Any] = ["platform": platform, "token": deviceToken]
        _ = try await request("/auth/device-token", method: "POST", body: body)
    }

    // MARK: - Tasks

    func getTasks(status: String? = nil) async throws -> [TaskOut] {
        var path = "/tasks"
        if let status { path += "?status=\(status)" }
        let data = try await request(path)
        return try decode([TaskOut].self, from: data)
    }

    func getUpcomingTasks() async throws -> [TaskOut] {
        let data = try await request("/tasks/upcoming")
        return try decode([TaskOut].self, from: data)
    }

    func createTask(
        title: String,
        description: String?,
        priority: Int,
        deadline: String?,
        estimatedMinutes: Int?,
        tags: [String] = [],
        source: String = "manual"
    ) async throws -> TaskOut {
        var body: [String: Any] = ["title": title, "priority": priority, "source": source, "tags": tags]
        if let d = description, !d.isEmpty { body["description"] = d }
        if let dl = deadline { body["deadline"] = dl }
        if let em = estimatedMinutes { body["estimated_minutes"] = em }
        let data = try await request("/tasks", method: "POST", body: body)
        return try decode(TaskOut.self, from: data)
    }

    func brainDump(text: String, source: String = "voice") async throws -> BrainDumpResponse {
        let body: [String: Any] = [
            "raw_text": text,
            "source": source,
            "timezone": TimeZone.current.identifier
        ]
        let data = try await request("/tasks/brain-dump", method: "POST", body: body)
        return try decode(BrainDumpResponse.self, from: data)
    }

    func planTask(taskId: String) async throws -> PlanResponse {
        let body: [String: Any] = ["plan_type": "llm_generated"]
        let data = try await request("/tasks/\(taskId)/plan", method: "POST", body: body)
        return try decode(PlanResponse.self, from: data)
    }

    func updateTask(taskId: String, fields: [String: Any]) async throws -> TaskOut {
        let data = try await request("/tasks/\(taskId)", method: "PATCH", body: fields)
        return try decode(TaskOut.self, from: data)
    }

    func deleteTask(taskId: String) async throws {
        _ = try await request("/tasks/\(taskId)", method: "DELETE")
    }

    // MARK: - Steps

    func getSteps(taskId: String) async throws -> [StepOut] {
        let data = try await request("/tasks/\(taskId)/steps")
        return try decode([StepOut].self, from: data)
    }

    func addStep(taskId: String, title: String, description: String? = nil, estimatedMinutes: Int? = nil) async throws -> StepOut {
        var body: [String: Any] = ["title": title]
        if let d = description { body["description"] = d }
        if let m = estimatedMinutes { body["estimated_minutes"] = m }
        let data = try await request("/tasks/\(taskId)/steps", method: "POST", body: body)
        return try decode(StepOut.self, from: data)
    }

    func updateStep(stepId: String, fields: [String: Any]) async throws -> StepOut {
        let data = try await request("/steps/\(stepId)", method: "PATCH", body: fields)
        return try decode(StepOut.self, from: data)
    }

    func completeStep(stepId: String) async throws -> StepOut {
        let data = try await request("/steps/\(stepId)/complete", method: "POST", body: [:])
        return try decode(StepOut.self, from: data)
    }

    // MARK: - Sessions

    func getActiveSession() async throws -> SessionOut {
        let data = try await request("/sessions/active")
        return try decode(SessionOut.self, from: data)
    }

    func startSession(
        taskId: String?,
        platform: String,
        workAppBundleIds: [String] = []
    ) async throws -> SessionOut {
        var body: [String: Any] = ["platform": platform]
        if let tid = taskId { body["task_id"] = tid }
        if !workAppBundleIds.isEmpty { body["work_app_bundle_ids"] = workAppBundleIds }
        let data = try await request("/sessions/start", method: "POST", body: body)
        return try decode(SessionOut.self, from: data)
    }

    func checkpointSession(sessionId: String, fields: [String: Any]) async throws -> SessionOut {
        let data = try await request("/sessions/\(sessionId)/checkpoint", method: "POST", body: fields)
        return try decode(SessionOut.self, from: data)
    }

    func endSession(sessionId: String, status: String = "completed") async throws -> SessionOut {
        let body: [String: Any] = ["status": status]
        let data = try await request("/sessions/\(sessionId)/end", method: "POST", body: body)
        return try decode(SessionOut.self, from: data)
    }

    func resumeSession(sessionId: String) async throws -> ResumeResponse {
        let data = try await request("/sessions/\(sessionId)/resume")
        return try decode(ResumeResponse.self, from: data)
    }

    func joinSession(sessionId: String, platform: String, workAppBundleIds: [String] = []) async throws -> JoinSessionResponse {
        var body: [String: Any] = ["platform": platform]
        if !workAppBundleIds.isEmpty { body["work_app_bundle_ids"] = workAppBundleIds }
        let data = try await request("/sessions/\(sessionId)/join", method: "POST", body: body)
        return try decode(JoinSessionResponse.self, from: data)
    }

    // MARK: - Distractions

    func appCheck(bundleId: String) async throws -> AppCheckResponse {
        let body: [String: Any] = ["app_bundle_id": bundleId]
        let data = try await request("/distractions/app-check", method: "POST", body: body)
        return try decode(AppCheckResponse.self, from: data)
    }

    func reportAppActivity(
        sessionId: String,
        appBundleId: String,
        appName: String,
        durationSeconds: Int,
        returnedToTask: Bool
    ) async throws {
        let body: [String: Any] = [
            "session_id": sessionId,
            "app_bundle_id": appBundleId,
            "app_name": appName,
            "duration_seconds": durationSeconds,
            "returned_to_task": returnedToTask
        ]
        _ = try await request("/distractions/app-activity", method: "POST", body: body)
    }

    // MARK: - Analytics

    func getAnalyticsSummary() async throws -> Data {
        return try await request("/analytics/summary")
    }

    func getDistractionAnalytics() async throws -> Data {
        return try await request("/analytics/distractions")
    }

    func getFocusTrends() async throws -> Data {
        return try await request("/analytics/focus-trends")
    }

    func getWeeklyReport() async throws -> Data {
        return try await request("/analytics/weekly-report")
    }
}
