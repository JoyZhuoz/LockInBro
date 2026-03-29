// LoginView.swift — Email/password + Sign in with Apple

import SwiftUI
import AuthenticationServices

// MARK: - Apple Sign In Coordinator (macOS window anchor)

@MainActor
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var onResult: ((Result<ASAuthorization, Error>) -> Void)?

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow }
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        onResult?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        onResult?(.failure(error))
    }

    func start(scopes: [ASAuthorization.Scope]) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = scopes

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

// MARK: - LoginView

struct LoginView: View {
    @Environment(AuthManager.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isRegistering = false
    @State private var coordinator = AppleSignInCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("LockInBro")
                    .font(.largeTitle.bold())
                Text("ADHD-aware focus assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 28)

            VStack(spacing: 14) {

                // ── Sign in with Apple ──────────────────────────────────
                Button {
                    triggerAppleSignIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 16, weight: .medium))
                        Text(isRegistering ? "Sign up with Apple" : "Sign in with Apple")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.primary)
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(auth.isLoading)

                // ── Divider ─────────────────────────────────────────────
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }

                // ── Email / password form ───────────────────────────────
                if isRegistering {
                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isRegistering ? .newPassword : .password)

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        if isRegistering {
                            await auth.register(email: email, password: password, displayName: displayName)
                        } else {
                            await auth.login(email: email, password: password)
                        }
                    }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView()
                        } else {
                            Text(isRegistering ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

                Button {
                    isRegistering.toggle()
                    auth.errorMessage = nil
                } label: {
                    Text(isRegistering ? "Already have an account? Sign in" : "New here? Create account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(width: 360, height: 520)
    }

    // MARK: - Apple Sign In trigger

    private func triggerAppleSignIn() {
        coordinator.onResult = { result in
            Task { @MainActor in
                handleAppleResult(result)
            }
        }
        coordinator.start(scopes: [.fullName, .email])
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                auth.errorMessage = "Apple Sign In failed — could not read identity token"
                return
            }

            let authorizationCode = credential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""

            let fullName: String? = {
                let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()

            Task {
                await auth.loginWithApple(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: fullName
                )
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                auth.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager.shared)
}
