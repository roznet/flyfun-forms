import Foundation
import OSLog

struct FormService {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "FormService")
    let baseURL: URL
    let jwt: String?

    enum FormError: LocalizedError {
        case notAuthenticated
        case unauthorized
        case serverError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not signed in. Please sign in to generate forms."
            case .unauthorized:
                return "Session expired. Please sign in again."
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .networkError(let error):
                return error.localizedDescription
            }
        }
    }

    // Fetches form details for an airport
    func airportDetail(icao: String) async throws -> AirportDetailResponse {
        let url = baseURL.appendingPathComponent("airports/\(icao)")
        var request = URLRequest(url: url)
        applyAuth(&request)
        let (data, _) = try await URLSession.shared.data(for: request)
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

        if let bodyStr = String(data: body, encoding: .utf8) {
            Self.logger.debug("POST /generate body: \(bodyStr)")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FormError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            Self.logger.error("401 Unauthorized from \(url)")
            throw FormError.unauthorized
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

    private func applyAuth(_ request: inout URLRequest) {
        if let jwt {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
    }
}
