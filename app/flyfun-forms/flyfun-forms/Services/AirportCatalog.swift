import Foundation
import Observation

@Observable
final class AirportCatalog {
    private(set) var airports: [AirportInfo] = []
    private(set) var prefixes: [PrefixInfo] = []
    private(set) var lastSynced: Date?
    private(set) var isLoading = false

    private let baseURL: URL
    private let cacheFileURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlightForms", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.cacheFileURL = appDir.appendingPathComponent("airports_cache.json")
        loadFromCacheOrBundle()
    }

    // Returns all forms available for a given ICAO code (exact match + prefix fallback)
    func formsForAirport(icao: String) -> [String] {
        if let airport = airports.first(where: { $0.icao == icao }) {
            return airport.forms
        }
        for prefix in prefixes {
            if icao.hasPrefix(prefix.prefix) {
                return prefix.forms
            }
        }
        return []
    }

    func hasFormsAvailable(icao: String) -> Bool {
        !formsForAirport(icao: icao).isEmpty
    }

    func airportName(icao: String) -> String? {
        airports.first(where: { $0.icao == icao })?.name
    }

    func sync() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let url = baseURL.appendingPathComponent("airports")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AirportCatalogResponse.self, from: data)
            airports = response.airports
            prefixes = response.prefixes
            lastSynced = Date()
            saveToCache(data)
        } catch {
            // Keep existing data on failure
        }
    }

    private func loadFromCacheOrBundle() {
        // Try cache first
        if let data = try? Data(contentsOf: cacheFileURL),
           let response = try? JSONDecoder().decode(AirportCatalogResponse.self, from: data) {
            airports = response.airports
            prefixes = response.prefixes
            return
        }
        // Fall back to bundled snapshot
        if let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let response = try? JSONDecoder().decode(AirportCatalogResponse.self, from: data) {
            airports = response.airports
            prefixes = response.prefixes
        }
    }

    private func saveToCache(_ data: Data) {
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
