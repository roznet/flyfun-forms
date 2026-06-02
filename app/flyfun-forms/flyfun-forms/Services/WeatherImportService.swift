import FlyFunCommon
import Foundation
import OSLog
import RZFlight

/// A lightweight summary of a weather flight, for the import picker. Decodes a
/// subset of weather's `FlightResponse` — `JSONDecoder` ignores the many other
/// keys the full response carries.
struct WeatherFlightSummary: Identifiable, Decodable {
    let id: String
    let routeName: String
    let waypoints: [String]
    let departureTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case routeName = "route_name"
        case waypoints
        case departureTime = "departure_time"
    }

    /// "EGTK → LSGS" when endpoints are known, else the flight's name.
    var routeLabel: String {
        if let first = waypoints.first, let last = waypoints.last, waypoints.count >= 2 {
            return "\(first) → \(last)"
        }
        return routeName
    }
}

/// Reads flights from the flyfun-weather backend so they can be imported into
/// forms. Every call goes through the shared `RollingBearerSession`, so the
/// same flyfun account logged into forms authenticates against
/// `weather.flyfun.aero` — the pilot imports their own flights, private ones
/// included.
struct WeatherImportService {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "WeatherImport")
    let baseURL: URL
    let session: RollingBearerSession

    enum WeatherImportError: LocalizedError {
        case serverError(Int, String)
        case noRoute

        var errorDescription: String? {
            switch self {
            case .serverError(let code, let message):
                if code == 401 {
                    return String(localized: "Sign in to the same FlyFun account to import your weather flights.")
                }
                let detail = message.isEmpty ? "" : ": \(message)"
                return String(localized: "Weather server error (\(code))\(detail)")
            case .noRoute:
                return String(localized: "This flight has no route to import.")
            }
        }
    }

    /// The current account's flights on weather, newest departure first.
    func listFlights() async throws -> [WeatherFlightSummary] {
        let url = baseURL.appendingPathComponent("api")
            .appendingPathComponent("flights")
        let (data, http) = try await session.data(for: URLRequest(url: url))
        guard http.statusCode == 200 else {
            throw WeatherImportError.serverError(http.statusCode, Self.body(data))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let flights = try decoder.decode([WeatherFlightSummary].self, from: data)
        return flights.sorted { $0.departureTime > $1.departureTime }
    }

    /// Fetch one flight as a cross-app `FlightExchange` payload.
    func exportFlight(id: String) async throws -> FlightExchange {
        let url = baseURL.appendingPathComponent("api")
            .appendingPathComponent("flights")
            .appendingPathComponent(id)
            .appendingPathComponent("export")
        let (data, http) = try await session.data(for: URLRequest(url: url))
        if http.statusCode == 422 { throw WeatherImportError.noRoute }
        guard http.statusCode == 200 else {
            throw WeatherImportError.serverError(http.statusCode, Self.body(data))
        }
        return try FlightExchange.decode(from: data)
    }

    private static func body(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}
