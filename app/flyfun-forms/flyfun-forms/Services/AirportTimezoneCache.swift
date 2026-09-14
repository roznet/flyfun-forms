import CoreLocation
import Foundation
import Observation
import RZFlight

/// Resolves and caches airport ICAO codes to their local `TimeZone` by
/// reverse-geocoding the airport's coordinates, persisting results to disk so
/// each airport is geocoded once.
///
/// Observable rather than callback-based: a view reads ``timezone(for:)`` and
/// re-renders when a resolution lands. The callback API this replaces dropped
/// its completion on three paths (airport not in the database yet, geocoder
/// failure, and a resolution already in flight for the same ICAO), each of
/// which left a picker showing nothing with no way to recover.
@Observable
@MainActor
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

    /// The cached timezone for an airport, or nil if it is not resolved yet.
    func timezone(for icao: String) -> TimeZone? {
        cache[icao]
    }

    /// The cached IANA identifier for an airport, or nil if not resolved yet.
    func timeZoneId(for icao: String) -> String? {
        cache[icao]?.identifier
    }

    /// Start resolving an airport's timezone if it is not known already.
    ///
    /// Safe to call repeatedly and from several views at once: a resolution
    /// already in flight is not started twice, and every observer sees the
    /// result because the cache is observable rather than notifying one caller.
    func resolve(icao: String) {
        guard !icao.isEmpty, cache[icao] == nil, !pending.contains(icao) else { return }
        pending.insert(icao)

        Task {
            defer { pending.remove(icao) }
            // The airport database loads in the background at launch, so an
            // early lookup can miss. Waiting for it is what makes resolution
            // work on a cold start rather than silently giving up.
            await AirportDatabase.shared.ready()
            guard let airport = AirportDatabase.shared.airport(icao: icao) else { return }
            let coord = airport.coord
            guard let zone = await Self.reverseGeocodeTimeZone(
                latitude: coord.latitude, longitude: coord.longitude
            ) else { return }
            cache[icao] = zone
            saveToDisk()
        }
    }

    /// Pre-warm the cache for a set of ICAO codes.
    func preload(icaos: Set<String>) async {
        await AirportDatabase.shared.ready()

        let toResolve = icaos.filter { !$0.isEmpty && cache[$0] == nil && !pending.contains($0) }
        guard !toResolve.isEmpty else { return }

        var resolvedAny = false
        for icao in toResolve {
            guard let airport = AirportDatabase.shared.airport(icao: icao) else { continue }
            pending.insert(icao)
            let coord = airport.coord
            if let zone = await Self.reverseGeocodeTimeZone(
                latitude: coord.latitude, longitude: coord.longitude
            ) {
                cache[icao] = zone
                resolvedAny = true
            }
            pending.remove(icao)

            // Sequential with a small delay, to stay inside CLGeocoder's rate limit.
            try? await Task.sleep(for: .milliseconds(100))
        }

        if resolvedAny {
            saveToDisk()
        }
    }

    private static func reverseGeocodeTimeZone(latitude: Double, longitude: Double) async -> TimeZone? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.timeZone
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
