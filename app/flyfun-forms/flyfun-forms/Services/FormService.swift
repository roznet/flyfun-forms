import FlyFunCommon
import Foundation
import OSLog

extension ServerValidationError {
    /// Human-readable field label, e.g. "crew[0].id_number" → "Crew 1 — ID Number"
    var displayField: String {
        var s = field

        for prefix in ["extra_fields.", "flight.", "aircraft."] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }

        if let openBracket = s.firstIndex(of: "["),
           let closeBracket = s.firstIndex(of: "]"),
           openBracket < closeBracket {
            let section = String(s[s.startIndex..<openBracket]).capitalized
            let indexStr = String(s[s.index(after: openBracket)..<closeBracket])
            let index = (Int(indexStr) ?? 0) + 1
            let rest = s[s.index(after: closeBracket)...]
            let fieldKey = rest.hasPrefix(".") ? String(rest.dropFirst()) : String(rest)
            return "\(section) \(index) — \(Self.humanizeKey(fieldKey))"
        }

        return Self.humanizeKey(s)
    }

    private static func humanizeKey(_ key: String) -> String {
        let labels: [String: String] = [
            "dob": "Date of Birth",
            "id_number": "ID Number",
            "id_type": "ID Type",
            "id_expiry": "ID Expiry",
            "id_issuing_country": "ID Issuing Country",
            "first_name": "First Name",
            "last_name": "Last Name",
            "departure_date": "Departure Date",
            "departure_time_utc": "Departure Time (UTC)",
            "arrival_date": "Arrival Date",
            "arrival_time_utc": "Arrival Time (UTC)",
            "owner_address": "Owner Address",
            "usual_base": "Usual Base",
            "reason_for_visit": "Reason for Visit",
            "responsible_person": "Responsible Person",
            "place_of_birth": "Place of Birth",
        ]
        if let label = labels[key] { return label }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Form-generation API wrapper. All authenticated calls flow through the
/// shared `RollingBearerSession`, so 401s clear the keychain and trigger
/// the `onUnauthorized` callback configured on `AppState`.
struct FormService {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "FormService")
    let baseURL: URL
    let session: RollingBearerSession

    enum FormError: LocalizedError {
        case validationErrors([ServerValidationError])
        case serverError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .validationErrors(let errors):
                let lines = errors.map { e in
                    var line = "• \(e.displayField): \(e.error)"
                    if let v = e.value, !v.isEmpty { line += " (sent: \"\(v)\")"}
                    return line
                }
                return lines.joined(separator: "\n")
            case .serverError(let code, let message):
                return String(localized: "Server error (\(code)): \(message)")
            case .networkError(let error):
                return error.localizedDescription
            }
        }
    }

    func airportDetail(icao: String) async throws -> AirportDetailResponse {
        // include_web: this build knows how to open web forms (book-out, PPR…)
        let url = baseURL.appendingPathComponent("airports").appendingPathComponent(icao)
            .appending(queryItems: [URLQueryItem(name: "include_web", value: "true")])
        let (data, http) = try await session.data(for: URLRequest(url: url))
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FormError.serverError(http.statusCode, message)
        }
        return try JSONDecoder().decode(AirportDetailResponse.self, from: data)
    }

    func generate(request: GenerateRequest, flatten: Bool = false) async throws -> (Data, String) {
        var url = baseURL.appendingPathComponent("generate")
        if flatten {
            url = url.appending(queryItems: [URLQueryItem(name: "flatten", value: "true")])
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        Self.logger.debug("POST /generate for airport=\(request.airport) form=\(request.form)")
        let (data, http) = try await session.data(for: urlRequest)
        try Self.checkFormResponse(data: data, http: http, url: url)

        let filename = http.value(forHTTPHeaderField: "Content-Disposition")
            .flatMap { header in
                header.components(separatedBy: "filename=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } ?? "\(request.airport)_\(request.form).pdf"
        return (data, filename)
    }

    /// Fill plan for an official web form (book-out, PPR…): same body as
    /// `generate`, answered with the page URL and a value per input.
    func prefill(request: GenerateRequest) async throws -> FillPlan {
        let url = baseURL.appendingPathComponent("prefill")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        Self.logger.debug("POST /prefill for airport=\(request.airport) form=\(request.form)")
        let (data, http) = try await session.data(for: urlRequest)
        try Self.checkFormResponse(data: data, http: http, url: url)
        return try JSONDecoder().decode(FillPlan.self, from: data)
    }

    /// Throws unless the response is a 200, parsing a 422 into structured
    /// validation errors.
    private static func checkFormResponse(data: Data, http: HTTPURLResponse, url: URL) throws {
        if http.statusCode == 422 {
            logger.error("422 Validation error from \(url)")
            if let parsed = try? JSONDecoder().decode(ServerValidationErrorResponse.self, from: data),
               !parsed.detail.isEmpty {
                throw FormError.validationErrors(parsed.detail)
            }
            let message = String(data: data, encoding: .utf8) ?? "Validation error"
            throw FormError.serverError(422, message)
        }

        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Server error \(http.statusCode) from \(url): \(message)")
            throw FormError.serverError(http.statusCode, message)
        }
    }

    func emailText(request: EmailTextRequest) async throws -> EmailTextResponse {
        let url = baseURL.appendingPathComponent("email-text")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, http) = try await session.data(for: urlRequest)
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FormError.serverError(http.statusCode, message)
        }
        return try JSONDecoder().decode(EmailTextResponse.self, from: data)
    }
}
