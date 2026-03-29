// AuthManager.swift — Authentication state

import SwiftUI

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()

    var isLoggedIn: Bool = false
    var currentUser: User?
    var isLoading: Bool = false
    var errorMessage: String?

    private init() {
        isLoggedIn = TokenStore.shared.token != nil
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIClient.shared.login(email: email, password: password)
            TokenStore.shared.token = response.accessToken
            TokenStore.shared.refreshToken = response.refreshToken
            currentUser = response.user
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIClient.shared.register(
                email: email,
                password: password,
                displayName: displayName
            )
            TokenStore.shared.token = response.accessToken
            TokenStore.shared.refreshToken = response.refreshToken
            currentUser = response.user
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loginWithApple(identityToken: String, authorizationCode: String, fullName: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIClient.shared.appleAuth(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName
            )
            TokenStore.shared.token = response.accessToken
            TokenStore.shared.refreshToken = response.refreshToken
            currentUser = response.user
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() {
        SessionManager.shared.stopMonitoring()
        TokenStore.shared.clear()
        currentUser = nil
        isLoggedIn = false
        errorMessage = nil
    }

    /// Called by APIClient when the server returns 401 and the refresh token is also dead.
    func handleSessionExpired() {
        guard isLoggedIn else { return }
        SessionManager.shared.stopMonitoring()
        TokenStore.shared.clear()
        currentUser = nil
        isLoggedIn = false
        errorMessage = "Your session expired — please log in again."
    }
}
