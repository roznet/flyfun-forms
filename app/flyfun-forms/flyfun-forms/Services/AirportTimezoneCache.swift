import CoreLocation
import Foundation
import RZFlight

/// Resolves and caches airport ICAO codes to their local TimeZone
/// using CLGeocoder reverse-geocoding of the airport's coordinates.
@Observable
final class AirportTimezoneCache {
    static let shared = AirportTimezoneCache()

    struct Entry {
        var timezone: TimeZone
        var city: String
    }

    private var cache: [String: Entry] = [:]
    private var pending: Set<String> = []

    private init() {}

    /// Returns the cached timezone for an airport, or nil if not yet resolved.
    /// Automatically triggers resolution if not cached.
    func timezone(for icao: String) -> TimeZone? {
        if let entry = cache[icao] { return entry.timezone }
        resolve(icao: icao)
        return nil
    }

    /// Returns the cached entry (timezone + city) for an airport.
    func entry(for icao: String) -> Entry? {
        cache[icao]
    }

    /// Resolve the timezone for an airport ICAO code.
    func resolve(icao: String) {
        guard !icao.isEmpty, cache[icao] == nil, !pending.contains(icao) else { return }
        guard let airport = AirportDatabase.shared.airport(icao: icao) else { return }

        pending.insert(icao)
        let location = CLLocation(latitude: airport.coord.latitude, longitude: airport.coord.longitude)
        let airportCity = airport.city

        Task {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let tz = placemarks.first?.timeZone {
                    let city = placemarks.first?.locality ?? airportCity
                    await MainActor.run {
                        cache[icao] = Entry(timezone: tz, city: city)
                        pending.remove(icao)
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
