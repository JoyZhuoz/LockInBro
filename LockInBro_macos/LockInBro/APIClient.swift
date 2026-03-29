// APIClient.swift — Backend networking for wahwa.com/api/v1

import Foundation

// MARK: - Errors

enum NetworkError: Error, LocalizedError {
    case noToken
    case httpError(Int, String)
    case decodingError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .noToken: return "Not authenticated. Please log in."
        case .httpError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let e): return "Parse error: \(e.localizedDescription)"
        case .unknown(let e): return e.localizedDescription
        }
    }
}

// MARK: - Token Storage (UserDefaults for hackathon simplicity)

final class TokenStore {
    static let shared = TokenStore()
    private let accessKey = "lockInBro.jwt"
    private let refreshKey = "lockInBro.refreshToken"
    private init() {}

    var token: String? {
        get { UserDefaults.standard.string(forKey: accessKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: accessKey) }
            else { UserDefaults.standard.removeObject(forKey: accessKey) }
        }
    }

    var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: refreshKey) }
            else { UserDefaults.standard.removeObject(forKey: refreshKey) }
        }
    }

    func clear() {
        token = nil
        refreshToken = nil
    }
}

extension Notification.Name {
    static let lockInBroAuthExpired = Notification.Name("lockInBroAuthExpired")
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()
    private let base = "https://wahwa.com/api/v1"
    private let urlSession = URLSession.shared
    private init() {}

    // MARK: Core Request

    // Coalesces concurrent 401-triggered refreshes into one request
    private var activeRefreshTask: Task<Bool, Never>?

    private func req(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        auth: Bool = true,
        timeout: TimeInterval = 30,
        isRetry: Bool = false
    ) async throws -> Data {
        guard let url = URL(string: base + path) else {
            throw NetworkError.unknown(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if auth {
            guard let token = TokenStore.shared.token else { throw NetworkError.noToken }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }
        guard http.statusCode < 400 else {
            if http.statusCode == 401 && auth && !isRetry {
                // Try to silently refresh the access token, then retry once
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return try await req(path, method: method, body: body,
                                        contentType: contentType, auth: auth,
                                        timeout: timeout, isRetry: true)
                }
                // Refresh also failed — force logout
                await MainActor.run { AuthManager.shared.handleSessionExpired() }
            }
            let msg = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.detail
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw NetworkError.httpError(http.statusCode, msg)
        }
        return data
    }

    /// Refreshes the access token. Concurrent callers share one in-flight request.
    private func refreshAccessToken() async -> Bool {
        if let existing = activeRefreshTask { return await existing.value }
        let task = Task<Bool, Never> {
            defer { self.activeRefreshTask = nil }
            guard let refresh = TokenStore.shared.refreshToken else { return false }
            do {
                let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
                guard let url = URL(string: base + "/auth/refresh") else { return false }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                req.timeoutInterval = 30
                let (data, res) = try await urlSession.data(for: req)
                guard let http = res as? HTTPURLResponse, http.statusCode == 200 else { return false }
                let auth = try self.decode(AuthResponse.self, from: data)
                TokenStore.shared.token = auth.accessToken
                TokenStore.shared.refreshToken = auth.refreshToken
                return true
            } catch { return false }
        }
        activeRefreshTask = task
        return await task.value
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password
        ])
        let data = try await req("/auth/login", method: "POST", body: body, auth: false)
        return try decode(AuthResponse.self, from: data)
    }

    func appleAuth(identityToken: String, authorizationCode: String, fullName: String?) async throws -> AuthResponse {
        var dict: [String: Any] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode
        ]
        if let name = fullName { dict["full_name"] = name }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let data = try await req("/auth/apple", method: "POST", body: body, auth: false)
        return try decode(AuthResponse.self, from: data)
    }

    func register(email: String, password: String, displayName: String) async throws -> AuthResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "display_name": displayName,
            "timezone": TimeZone.current.identifier
        ])
        let data = try await req("/auth/register", method: "POST", body: body, auth: false)
        return try decode(AuthResponse.self, from: data)
    }

    // MARK: - Tasks

    func getTasks(status: String? = nil) async throws -> [AppTask] {
        var path = "/tasks"
        if let status { path += "?status=\(status)" }
        let data = try await req(path)
        return try decode([AppTask].self, from: data)
    }

    func getUpcomingTasks() async throws -> [AppTask] {
        let data = try await req("/tasks/upcoming")
        return try decode([AppTask].self, from: data)
    }

    func createTask(title: String, description: String?, priority: Int, deadline: String?, estimatedMinutes: Int?, tags: [String]) async throws -> AppTask {
        var dict: [String: Any] = ["title": title, "priority": priority, "tags": tags]
        if let d = description { dict["description"] = d }
        if let dl = deadline { dict["deadline"] = dl }
        if let em = estimatedMinutes { dict["estimated_minutes"] = em }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let data = try await req("/tasks", method: "POST", body: body)
        return try decode(AppTask.self, from: data)
    }

    func updateTask(taskId: String, title: String? = nil, description: String? = nil, priority: Int? = nil, status: String? = nil, deadline: String? = nil, estimatedMinutes: Int? = nil, tags: [String]? = nil) async throws -> AppTask {
        var dict: [String: Any] = [:]
        if let v = title { dict["title"] = v }
        if let v = description { dict["description"] = v }
        if let v = priority { dict["priority"] = v }
        if let v = status { dict["status"] = v }
        if let v = deadline { dict["deadline"] = v }
        if let v = estimatedMinutes { dict["estimated_minutes"] = v }
        if let v = tags { dict["tags"] = v }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let data = try await req("/tasks/\(taskId)", method: "PATCH", body: body)
        return try decode(AppTask.self, from: data)
    }

    func deleteTask(taskId: String) async throws {
        _ = try await req("/tasks/\(taskId)", method: "DELETE")
    }

    func brainDump(rawText: String) async throws -> BrainDumpResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "raw_text": rawText,
            "source": "manual",
            "timezone": TimeZone.current.identifier
        ])
        let data = try await req("/tasks/brain-dump", method: "POST", body: body, timeout: 120)
        return try decode(BrainDumpResponse.self, from: data)
    }

    func planTask(taskId: String) async throws -> StepPlanResponse {
        let body = try JSONSerialization.data(withJSONObject: ["plan_type": "llm_generated"])
        let data = try await req("/tasks/\(taskId)/plan", method: "POST", body: body)
        return try decode(StepPlanResponse.self, from: data)
    }

    // MARK: - Steps

    func getSteps(taskId: String) async throws -> [Step] {
        let data = try await req("/tasks/\(taskId)/steps")
        return try decode([Step].self, from: data)
    }

    func updateStep(stepId: String, status: String? = nil, checkpointNote: String? = nil) async throws -> Step {
        var dict: [String: Any] = [:]
        if let v = status { dict["status"] = v }
        if let v = checkpointNote { dict["checkpoint_note"] = v }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let data = try await req("/steps/\(stepId)", method: "PATCH", body: body)
        return try decode(Step.self, from: data)
    }

    func completeStep(stepId: String) async throws -> Step {
        let data = try await req("/steps/\(stepId)/complete", method: "POST")
        return try decode(Step.self, from: data)
    }

    // MARK: - Sessions

    /// Returns the currently active session, or nil if none (404).
    func getActiveSession() async throws -> FocusSession? {
        do {
            let data = try await req("/sessions/active")
            return try decode(FocusSession.self, from: data)
        } catch NetworkError.httpError(404, _) {
            return nil
        }
    }

    func startSession(taskId: String?) async throws -> FocusSession {
        var dict: [String: Any] = ["platform": "mac"]
        if let tid = taskId { dict["task_id"] = tid }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let data = try await req("/sessions/start", method: "POST", body: body)
        return try decode(FocusSession.self, from: data)
    }

    func endSession(sessionId: String, status: String = "completed") async throws -> FocusSession {
        let body = try JSONSerialization.data(withJSONObject: ["status": status])
        let data = try await req("/sessions/\(sessionId)/end", method: "POST", body: body)
        return try decode(FocusSession.self, from: data)
    }

    func resumeSession(sessionId: String) async throws -> ResumeResponse {
        let data = try await req("/sessions/\(sessionId)/resume")
        return try decode(ResumeResponse.self, from: data)
    }

    func checkpointSession(
        sessionId: String,
        currentStepId: String? = nil,
        lastActionSummary: String? = nil,
        nextUp: String? = nil,
        goal: String? = nil,
        activeApp: String? = nil,
        lastScreenshotAnalysis: String? = nil,
        attentionScore: Int? = nil,
        distractionCount: Int? = nil
    ) async throws {
        var dict: [String: Any] = [:]
        if let v = currentStepId { dict["current_step_id"] = v }
        if let v = lastActionSummary { dict["last_action_summary"] = v }
        if let v = nextUp { dict["next_up"] = v }
        if let v = goal { dict["goal"] = v }
        if let v = activeApp { dict["active_app"] = v }
        if let v = lastScreenshotAnalysis { dict["last_screenshot_analysis"] = v }
        if let v = attentionScore { dict["attention_score"] = v }
        if let v = distractionCount { dict["distraction_count"] = v }
        let body = try JSONSerialization.data(withJSONObject: dict)
        _ = try await req("/sessions/\(sessionId)/checkpoint", method: "POST", body: body)
    }

    // MARK: - App Activity

    func appActivity(
        sessionId: String,
        appBundleId: String,
        appName: String,
        durationSeconds: Int,
        returnedToTask: Bool = false
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionId,
            "app_bundle_id": appBundleId,
            "app_name": appName,
            "duration_seconds": durationSeconds,
            "returned_to_task": returnedToTask
        ] as [String: Any])
        _ = try await req("/distractions/app-activity", method: "POST", body: body)
    }

    // MARK: - Distraction / Screenshot Analysis
    // Note: spec primary endpoint is POST /distractions/analyze-result (device-side VLM, JSON only).
    // Backend currently implements analyze-screenshot (legacy fallback) — using that until analyze-result is deployed.

    func analyzeScreenshot(
        imageData: Data,
        windowTitle: String,
        sessionId: String,
        taskContext: [String: Any]
    ) async throws -> DistractionAnalysisResponse {
        let boundary = "LockInBro-\(UUID().uuidString.prefix(8))"
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Screenshot binary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"screenshot.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("window_title", value: windowTitle)
        appendField("session_id", value: sessionId)

        let contextJSON = String(data: (try? JSONSerialization.data(withJSONObject: taskContext)) ?? Data(), encoding: .utf8) ?? "{}"
        appendField("task_context", value: contextJSON)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await req(
            "/distractions/analyze-screenshot",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: 60
        )
        return try decode(DistractionAnalysisResponse.self, from: data)
    }
}
