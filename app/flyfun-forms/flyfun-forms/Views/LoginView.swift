import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let authService = AuthService()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.text.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Flight Forms")
                .font(.largeTitle.bold())

            Text("GA customs form generator")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await handleAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 280, minHeight: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isSigningIn)

            Button {
                Task { await signIn(provider: "google") }
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 280)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSigningIn)

            Spacer()
                .frame(height: 60)
        }
        .padding()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unexpected credential type."
                return
            }
            let token = try await authService.exchangeAppleCredential(credential, baseURL: APIConfig.baseURL)
            guard let callbackURL = URL(string: "flyfunforms://auth/callback?token=\(token)") else {
                errorMessage = "Failed to create authentication URL."
                return
            }
            appState.handleAuthCallback(url: callbackURL)
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signIn(provider: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let token = try await authService.signIn(baseURL: APIConfig.baseURL, provider: provider)
            guard let callbackURL = URL(string: "flyfunforms://auth/callback?token=\(token)") else {
                errorMessage = "Failed to create authentication URL."
                return
            }
            appState.handleAuthCallback(url: callbackURL)
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = error.localizedDescription
            }
        }
    }
}
