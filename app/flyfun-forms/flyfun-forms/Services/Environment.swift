import SwiftUI

// MARK: - API Configuration

enum APIConfig {
    static let baseURL = URL(string: "https://forms.flyfun.aero")!
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
