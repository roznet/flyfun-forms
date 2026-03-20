import SwiftUI

// MARK: - API Configuration

enum APIConfig {
    #if targetEnvironment(simulator)
    static let baseURL = URL(string: "https://localhost.ro-z.me:8443")!
    static let isDevMode = true
    #else
    static let baseURL = URL(string: "https://forms.flyfun.aero")!
    static let isDevMode = false
    #endif
}

// MARK: - Environment Keys

struct AirportCatalogKey: EnvironmentKey {
    nonisolated static let defaultValue = AirportCatalog(baseURL: APIConfig.baseURL)
}

extension EnvironmentValues {
    var airportCatalog: AirportCatalog {
        get { self[AirportCatalogKey.self] }
        set { self[AirportCatalogKey.self] = newValue }
    }
}
