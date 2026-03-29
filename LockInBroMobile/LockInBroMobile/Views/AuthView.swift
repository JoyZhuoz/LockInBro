// AuthView.swift — LockInBro
// Login / Register / Apple Sign In

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AppState.self) private var appState
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var localError: String?
    @State private var isSubmitting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // MARK: Logo / Header
                VStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)

                    Text("LockInBro")
                        .font(.largeTitle.bold())

                    Text("ADHD-Aware Focus Assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                // MARK: Form
                VStack(spacing: 14) {
                    Picker("Mode", selection: $isLogin) {
                        Text("Log In").tag(true)
                        Text("Sign Up").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !isLogin {
                        TextField("Your name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                    }

                    TextField("Email address", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isLogin ? .password : .newPassword)

                    if let err = localError ?? appState.globalError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }

                    Button(action: submit) {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isLogin ? "Log In" : "Create Account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!isFormValid || isSubmitting)
                }
                .padding(.horizontal)

                // MARK: Apple Sign In
                VStack(spacing: 14) {
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                        Text("or").font(.caption).foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
        }
        .onChange(of: isLogin) { _, _ in
            localError = nil
            appState.globalError = nil
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && (isLogin || !displayName.isEmpty)
    }

    private func submit() {
        localError = nil
        appState.globalError = nil
        isSubmitting = true
        Task {
            do {
                if isLogin {
                    try await appState.login(email: email, password: password)
                } else {
                    try await appState.register(email: email, password: password, displayName: displayName)
                }
            } catch {
                localError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        localError = nil
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8) else {
                localError = "Apple Sign In failed — missing credentials"
                return
            }

            let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
            let fullName = parts.compactMap { $0 }.joined(separator: " ")

            Task {
                do {
                    let response = try await APIClient.shared.signInWithApple(
                        identityToken: token,
                        authorizationCode: code,
                        fullName: fullName.isEmpty ? nil : fullName
                    )
                    await appState.applyAuthResponse(response)
                } catch {
                    await MainActor.run { localError = error.localizedDescription }
                }
            }

        case .failure(let error):
            // User cancelled sign-in — don't show error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                localError = error.localizedDescription
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AppState())
}
