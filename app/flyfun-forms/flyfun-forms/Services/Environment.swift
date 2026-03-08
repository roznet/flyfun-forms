import SwiftUI

// MARK: - API Configuration

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:8030")!
    #else
    static let baseURL = URL(string: "https://forms.flyfun.aero")!
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
