// AppState.swift — LockInBro
// Central observable state shared across all views via @Environment

import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Auth State
    var isAuthenticated = false
    var currentUser: UserOut?

    // MARK: - Task State
    var tasks: [TaskOut] = []
    var isLoadingTasks = false

    // MARK: - Session State
    var activeSession: SessionOut?

    // MARK: - UI State
    var globalError: String?
    var isLoading = false

    // Set by deep link / notification tap to trigger navigation
    var pendingOpenTaskId: String?
    var pendingResumeSessionId: String?

    // MARK: - Init
    init() {
        if let token = KeychainService.shared.getToken() {
            APIClient.shared.token = token
            isAuthenticated = true
        }
        APIClient.shared.onAuthFailure = { [weak self] in
            self?.logout()
        }
    }

    // MARK: - Auth

    @MainActor
    func login(email: String, password: String) async throws {
        isLoading = true
        globalError = nil
        defer { isLoading = false }
        let response = try await APIClient.shared.login(email: email, password: password)
        await applyAuthResponse(response)
    }

    @MainActor
    func register(email: String, password: String, displayName: String) async throws {
        isLoading = true
        globalError = nil
        defer { isLoading = false }
        let response = try await APIClient.shared.register(
            email: email, password: password, displayName: displayName
        )
        await applyAuthResponse(response)
    }

    @MainActor
    func applyAuthResponse(_ response: AuthResponse) async {
        APIClient.shared.token = response.accessToken
        KeychainService.shared.saveToken(response.accessToken)
        KeychainService.shared.saveRefreshToken(response.refreshToken)
        currentUser = response.user
        isAuthenticated = true
        await loadTasks()
    }

    @MainActor
    func logout() {
        APIClient.shared.token = nil
        KeychainService.shared.deleteAll()
        isAuthenticated = false
        currentUser = nil
        tasks = []
        activeSession = nil
    }

    // MARK: - Tasks

    @MainActor
    func loadTasks() async {
        isLoadingTasks = true
        defer { isLoadingTasks = false }
        do {
            tasks = try await APIClient.shared.getTasks()
        } catch {
            globalError = error.localizedDescription
        }
        await loadActiveSession()
    }

    @MainActor
    func loadActiveSession() async {
        do {
            activeSession = try await APIClient.shared.getActiveSession()
        } catch {
            activeSession = nil
        }
    }

    @MainActor
    func deleteTask(_ task: TaskOut) async {
        do {
            try await APIClient.shared.deleteTask(taskId: task.id)
            tasks.removeAll { $0.id == task.id }
        } catch {
            globalError = error.localizedDescription
        }
    }

    @MainActor
    func markTaskDone(_ task: TaskOut) async {
        do {
            let updated = try await APIClient.shared.updateTask(taskId: task.id, fields: ["status": "done"])
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = updated
            }
        } catch {
            globalError = error.localizedDescription
        }
    }

    // MARK: - Computed

    var pendingTaskCount: Int { tasks.filter { $0.status != "done" }.count }
    var urgentTasks: [TaskOut] { tasks.filter { $0.priority == 4 && $0.status != "done" } }
    var overdueTasks: [TaskOut] { tasks.filter { $0.isOverdue } }
}
