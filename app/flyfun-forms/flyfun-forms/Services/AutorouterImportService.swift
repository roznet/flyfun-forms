import FlyFunCommon
import Foundation
import OSLog
import RZFlight

/// One recent route from the pilot's linked Autorouter account.
///
/// Mirrors `flyfun_common.autorouter.AutorouterRoute`, which flyfun-weather
/// serves from the same shared client — the payload is defined once, in
/// flyfun-common, and both apps decode the same shape.
struct AutorouterRouteSummary: Identifiable, Decodable, Hashable {
    var id: String { routeid }

    let routeid: String
    let departure: String
    let destination: String
    let departureName: String?
    let destinationName: String?
    let departureTime: Date?
    /// The raw ICAO flight plan, parsed on-device rather than by a second
    /// server round trip: forms already has `RZFlight.ICAOFlightPlanParser` in
    /// process for the clipboard import, so both methods share one parser.
    let fplan: String
    let routeDistanceNm: Int?
    let aircraftDescription: String?
    let callsign: String?

    enum CodingKeys: String, CodingKey {
        case routeid
        case departure
        case destination
        case departureName = "departure_name"
        case destinationName = "destination_name"
        case departureTime = "departure_time"
        case fplan
        case routeDistanceNm = "route_distance_nm"
        case aircraftDescription = "aircraft_description"
        case callsign
    }

    /// "EGTF → LFRM" headline for the picker row.
    var routeLabel: String { "\(departure) \u{2192} \(destination)" }
}

private struct AutorouterRoutesResponse: Decodable {
    let routes: [AutorouterRouteSummary]
}

private struct AutorouterLinkStatus: Decodable {
    let linked: Bool
}

/// Reads the pilot's recent Autorouter routes from the forms backend.
///
/// The backend holds the OAuth token, so this is a plain authenticated GET.
/// Linking happens once, on the weather web app: the flyfun apps share one
/// database and one encryption key, so an account linked there is linked here.
struct AutorouterImportService {
    private static let logger = Logger(
        subsystem: "net.ro-z.flyfun-forms", category: "AutorouterImport"
    )
    let baseURL: URL
    let session: RollingBearerSession

    enum AutorouterImportError: LocalizedError {
        case notLinked
        case unreachable
        case serverError(Int, String)
        case unparseablePlan

        var errorDescription: String? {
            switch self {
            case .notLinked:
                return String(localized: "Link your Autorouter account in the FlyFun Weather web app, then come back here.")
            case .unreachable:
                return String(localized: "Autorouter didn't answer. Try again in a moment.")
            case .serverError(let code, let message):
                let detail = message.isEmpty ? "" : ": \(message)"
                return String(localized: "Autorouter import failed (\(code))\(detail)")
            case .unparseablePlan:
                return String(localized: "That route's flight plan couldn't be read.")
            }
        }
    }

    private func endpoint(_ name: String) -> URL {
        baseURL.appendingPathComponent("api")
            .appendingPathComponent("autorouter")
            .appendingPathComponent(name)
    }

    /// Whether the account has a usable Autorouter token.
    ///
    /// Answered from stored credentials, with no call to Autorouter, so the
    /// import list can grey the method with its reason before the pilot taps
    /// it. Returns nil when the check itself fails: unknown is not the same as
    /// unlinked, and a flaky network must not make a working method look
    /// broken.
    func isLinked() async -> Bool? {
        do {
            let (data, http) = try await session.data(
                for: URLRequest(url: endpoint("status"))
            )
            guard http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(AutorouterLinkStatus.self, from: data).linked
        } catch {
            Self.logger.debug("Autorouter link status unavailable: \(error)")
            return nil
        }
    }

    /// The account's recent Autorouter routes, newest first (the server asks
    /// Autorouter for that order).
    func listRoutes(limit: Int = 25) async throws -> [AutorouterRouteSummary] {
        var components = URLComponents(
            url: endpoint("routes"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else {
            throw AutorouterImportError.unreachable
        }

        let (data, http) = try await session.data(for: URLRequest(url: url))
        switch http.statusCode {
        case 200:
            break
        case 409:
            // The server distinguishes "never linked / token revoked" from
            // "no routes", so this must not read as an empty list.
            throw AutorouterImportError.notLinked
        case 502:
            throw AutorouterImportError.unreachable
        default:
            throw AutorouterImportError.serverError(
                http.statusCode, String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutorouterRoutesResponse.self, from: data).routes
    }

    /// Parse a picked route's flight plan into a draft, on-device.
    static func draft(from route: AutorouterRouteSummary) throws -> FlightDraft {
        guard let plan = ICAOFlightPlanParser.parse(route.fplan) else {
            Self.logger.debug("Autorouter route \(route.routeid) had an unparseable fplan")
            throw AutorouterImportError.unparseablePlan
        }
        return FlightDraft(plan, provenance: .autorouter(routeID: route.routeid))
    }
}
