import AuthenticationServices
import Foundation
import OSLog

/// Handles OAuth login via ASWebAuthenticationSession (Google, Apple, etc.).
@MainActor
final class AuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "Auth")

    private var authSession: ASWebAuthenticationSession?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            return scene?.keyWindow ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }

    /// Opens the OAuth flow for the given provider and returns the JWT token.
    func signIn(baseURL: URL, provider: String = "google") async throws -> String {
        let loginURL = baseURL.appendingPathComponent("auth/login/\(provider)")
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "scheme", value: "flyfunforms"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        Self.logger.info("Starting OAuth flow (\(provider)) to \(url)")

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme("flyfunforms")
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty
        else {
            Self.logger.error("No token in callback URL: \(callbackURL)")
            throw URLError(.userAuthenticationRequired)
        }
        return token
    }
}
