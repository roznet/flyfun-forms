import FlyFunCommon
import Foundation
import OSLog

/// Central auth state: JWT storage (via FlyFunCommon's keychain-backed store)
/// and the rolling Bearer session that all authenticated calls go through.
@Observable
@MainActor
final class AppState {
    @ObservationIgnored let tokenStore: KeychainBearerTokenStore
    @ObservationIgnored private(set) var rollingSession: RollingBearerSession!
    @ObservationIgnored private let callbackParser = AuthCallbackParser(customScheme: "flyfunforms")

    /// Mirror of the keychain JWT — observable so SwiftUI re-renders on
    /// login/logout. Don't pass this around for API auth; use `rollingSession`,
    /// which always reads the live store and rotates the token in-place.
    private(set) var jwt: String?

    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "AppState")

    var isAuthenticated: Bool { APIConfig.isDevMode || jwt != nil }

    init() {
        let store = KeychainBearerTokenStore(service: "net.ro-z.flyfun-forms")
        self.tokenStore = store
        self.jwt = store.token

        self.rollingSession = RollingBearerSession(
            store: store,
            onUnauthorized: { [weak self] in
                await self?.handleUnauthorized()
            }
        )
    }

    /// Apply a JWT obtained from the Apple credential exchange or Google OAuth.
    func signIn(token: String) {
        Self.logger.info("Storing JWT after sign-in")
        applyToken(token)
    }

    /// Handle a deep-link auth callback: `flyfunforms://auth?token=…`.
    func handleAuthCallback(url: URL) {
        guard let token = callbackParser.token(from: url) else {
            Self.logger.warning("Invalid auth callback URL: \(url)")
            return
        }
        Self.logger.info("Auth callback received, storing JWT")
        applyToken(token)
    }

    func logout() {
        Self.logger.info("Logging out")
        applyToken(nil)
    }

    /// Sync the observable mirror after the rolling session cleared the
    /// store on 401. Triggers SwiftUI to swap ContentView for LoginView.
    func handleUnauthorized() {
        if jwt != nil {
            Self.logger.info("401 from server — clearing local auth state")
            jwt = nil
        }
    }

    private func applyToken(_ token: String?) {
        tokenStore.token = token
        jwt = token
    }
}
