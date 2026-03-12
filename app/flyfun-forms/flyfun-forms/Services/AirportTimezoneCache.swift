import CoreLocation
import Foundation
import RZFlight

/// Resolves and caches airport ICAO codes to their local TimeZone
/// using CLGeocoder reverse-geocoding of the airport's coordinates.
final class AirportTimezoneCache {
    static let shared = AirportTimezoneCache()

    private var cache: [String: TimeZone] = [:]
    private var pending: Set<String> = []

    private init() {}

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
                        cache[icao] = tz
                        pending.remove(icao)
                        onResolved?()
                    }
                    return
                }
            } catch {}
            await MainActor.run {
                pending.remove(icao)
            }
        }
    }
}
