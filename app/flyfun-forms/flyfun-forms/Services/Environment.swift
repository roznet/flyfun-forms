import SwiftUI

// MARK: - API Configuration

enum APIConfig {
    static let productionURL = URL(string: "https://forms.flyfun.aero")!
    static let devURL = URL(string: "https://localhost.ro-z.me:8443")!

    /// flyfun-weather backend — source of "Import from Weather" flights. The
    /// dev host matches the weather HTTPS dev server (`/devserver --https`).
    static let weatherProductionURL = URL(string: "https://weather.flyfun.aero")!
    static let weatherDevURL = URL(string: "https://localhost.ro-z.me:8443")!

    /// Whether the server toggle is available (DEBUG builds or simulator)
    static var canToggleServer: Bool {
        #if DEBUG
        return true
        #elseif targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Current base URL, respecting the user toggle in debug/simulator builds.
    static var baseURL: URL {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "useDevServer") ? devURL : productionURL
        #elseif targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "useDevServer") ? devURL : productionURL
        #else
        return productionURL
        #endif
    }

    /// Base URL of the flyfun-weather backend, respecting the dev-server toggle.
    static var weatherBaseURL: URL {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "useDevServer") ? weatherDevURL : weatherProductionURL
        #elseif targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "useDevServer") ? weatherDevURL : weatherProductionURL
        #else
        return weatherProductionURL
        #endif
    }

    /// Whether auth can be skipped (only when actively using dev server)
    static var isDevMode: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "useDevServer")
        #elseif targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "useDevServer")
        #else
        return false
        #endif
    }
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
