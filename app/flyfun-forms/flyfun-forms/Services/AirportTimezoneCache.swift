import CoreLocation
import Foundation
import RZFlight

/// Resolves and caches airport ICAO codes to their local TimeZone
/// using CLGeocoder reverse-geocoding of the airport's coordinates.
/// Results are persisted to disk so geocoding only happens once per airport.
final class AirportTimezoneCache {
    static let shared = AirportTimezoneCache()

    private var cache: [String: TimeZone] = [:]
    private var pending: Set<String> = []

    private static let cacheFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlightForms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timezone_cache.json")
    }()

    private init() {
        loadFromDisk()
    }

    /// Returns the cached timezone for an airport, or nil if not yet resolved.
    func timezone(for icao: String) -> TimeZone? {
        cache[icao]
    }

    /// Resolve the timezone for an airport ICAO code.
    /// Calls the completion handler on the main actor when done.
    func resolve(icao: String, onResolved: (() -> Void)? = nil) {
        guard !icao.isEmpty, cache[icao] == nil, !pending.contains(icao) else {
            if cache[icao] != nil { onResolved?() }
            return
        }
        guard let airport = AirportDatabase.shared.airport(icao: icao) else { return }

        pending.insert(icao)
        let location = CLLocation(latitude: airport.coord.latitude, longitude: airport.coord.longitude)

        Task {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let tz = placemarks.first?.timeZone {
                    await MainActor.run {
                        self.cache[icao] = tz
                        self.pending.remove(icao)
                        self.saveToDisk()
                        onResolved?()
                    }
                    return
                }
            } catch {}
            await MainActor.run {
                self.pending.remove(icao)
            }
        }
    }

    /// Pre-warm the cache for a set of ICAO codes.
    /// Waits for AirportDatabase to be ready, then resolves concurrently.
    @MainActor
    func preload(icaos: Set<String>) async {
        await AirportDatabase.shared.ready()

        let toResolve = icaos.filter { !$0.isEmpty && cache[$0] == nil && !pending.contains($0) }
        guard !toResolve.isEmpty else { return }

        // Resolve sequentially with a small delay to respect CLGeocoder rate limits
        for icao in toResolve {
            guard let airport = AirportDatabase.shared.airport(icao: icao) else { continue }
            pending.insert(icao)
            let location = CLLocation(latitude: airport.coord.latitude, longitude: airport.coord.longitude)

            let geocoder = CLGeocoder()
            if let tz = try? await geocoder.reverseGeocodeLocation(location).first?.timeZone {
                cache[icao] = tz
            }
            pending.remove(icao)

            // Small delay between requests to stay within Apple's rate limit
            try? await Task.sleep(for: .milliseconds(100))
        }

        saveToDisk()
    }

    // MARK: - Disk Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (icao, identifier) in dict {
            if let tz = TimeZone(identifier: identifier) {
                cache[icao] = tz
            }
        }
    }

    private func saveToDisk() {
        let dict = cache.mapValues(\.identifier)
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
    }
}
