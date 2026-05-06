import AuthenticationServices
import FlyFunCommon
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var authService: FlyFunAuthService {
        FlyFunAuthService(config: .init(
            baseURL: APIConfig.baseURL,
            callbackScheme: "flyfunforms"
        ))
    }

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

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await handleAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 175, height: 40)
                .disabled(isSigningIn)

                Button {
                    Task { await signIn(provider: "google") }
                } label: {
                    Image("SignInWithGoogle")
                        .resizable()
                        .frame(width: 175, height: 40)
                        .overlay {
                            if isSigningIn {
                                ProgressView().controlSize(.small)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
            }

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
                errorMessage = String(localized: "Unexpected credential type.")
                return
            }
            let token = try await authService.exchangeAppleCredential(credential)
            appState.signIn(token: token)
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
            let token = try await authService.signIn(provider: provider)
            appState.signIn(token: token)
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Light") {
    LoginView()
        .environment(AppState())
        .frame(width: 500, height: 500)
}

#Preview("Dark") {
    LoginView()
        .environment(AppState())
        .frame(width: 500, height: 500)
        .preferredColorScheme(.dark)
}
