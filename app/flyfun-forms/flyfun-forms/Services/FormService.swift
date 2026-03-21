import Foundation
import OSLog

struct ServerValidationError: Codable, Identifiable {
    var field: String
    var error: String
    var value: String?

    var id: String { "\(field):\(error)" }

    /// Human-readable field label, e.g. "crew[0].id_number" → "Crew 1 — ID Number"
    var displayField: String {
        var s = field

        // Strip common prefixes
        for prefix in ["extra_fields.", "flight.", "aircraft."] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }

        // Convert indexed fields: "crew[0].dob" → "Crew 1 — Date of Birth"
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

private struct ValidationErrorResponse: Codable {
    var detail: [ServerValidationError]
}

struct FormService {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "FormService")
    let baseURL: URL
    let jwt: String?

    enum FormError: LocalizedError {
        case notAuthenticated
        case unauthorized
        case validationErrors([ServerValidationError])
        case serverError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return String(localized: "Not signed in. Please sign in to generate forms.")
            case .unauthorized:
                return String(localized: "Session expired. Please sign in again.")
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

    // Fetches form details for an airport
    func airportDetail(icao: String) async throws -> AirportDetailResponse {
        let url = baseURL.appendingPathComponent("airports").appendingPathComponent(icao)
        var request = URLRequest(url: url)
        applyAuth(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FormError.networkError(URLError(.badServerResponse))
        }
        if httpResponse.statusCode == 401 {
            throw FormError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FormError.serverError(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(AirportDetailResponse.self, from: data)
    }

    // Generates a filled form, returns the file data and suggested filename
    func generate(request: GenerateRequest, flatten: Bool = false) async throws -> (Data, String) {
        var url = baseURL.appendingPathComponent("generate")
        if flatten {
            url = url.appending(queryItems: [URLQueryItem(name: "flatten", value: "true")])
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(request)
        urlRequest.httpBody = body
        applyAuth(&urlRequest)

        Self.logger.debug("POST /generate for airport=\(request.airport) form=\(request.form)")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FormError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            Self.logger.error("401 Unauthorized from \(url)")
            throw FormError.unauthorized
        }

        if httpResponse.statusCode == 422 {
            Self.logger.error("422 Validation error from \(url)")
            if let parsed = try? JSONDecoder().decode(ValidationErrorResponse.self, from: data), !parsed.detail.isEmpty {
                throw FormError.validationErrors(parsed.detail)
            }
            let message = String(data: data, encoding: .utf8) ?? "Validation error"
            throw FormError.serverError(422, message)
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("Server error \(httpResponse.statusCode) from \(url): \(message)")
            throw FormError.serverError(httpResponse.statusCode, message)
        }

        let filename = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
            .flatMap { header in
                header.components(separatedBy: "filename=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } ?? "\(request.airport)_\(request.form).pdf"

        return (data, filename)
    }

    func emailText(request: EmailTextRequest) async throws -> EmailTextResponse {
        let url = baseURL.appendingPathComponent("email-text")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        applyAuth(&urlRequest)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FormError.networkError(URLError(.badServerResponse))
        }
        if httpResponse.statusCode == 401 {
            throw FormError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FormError.serverError(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(EmailTextResponse.self, from: data)
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let jwt {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
    }
}
