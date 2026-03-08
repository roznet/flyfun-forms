import Foundation
import OSLog
import RZUtilsSwift

enum SecureKey: String {
    case jwt
}

/// Central auth state: JWT storage, login/logout.
@Observable
@MainActor
final class AppState {
    @ObservationIgnored
    private var secureStorage = CodableSecureStorage<SecureKey, String>(
        key: .jwt, service: "net.ro-z.flyfun-forms"
    )

    private(set) var jwt: String?
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "AppState")

    var isAuthenticated: Bool { jwt != nil }

    init() {
        jwt = secureStorage.wrappedValue
    }

    func handleAuthCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "flyfunforms",
              components.host == "auth",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty
        else {
            Self.logger.warning("Invalid auth callback URL: \(url)")
            return
        }
        Self.logger.info("Auth callback received, storing JWT")
        secureStorage.wrappedValue = token
        jwt = token
    }

    func logout() {
        Self.logger.info("Logging out")
        secureStorage.wrappedValue = nil
        jwt = nil
    }
}
