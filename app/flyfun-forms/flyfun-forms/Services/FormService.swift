import Foundation

struct FormService {
    let baseURL: URL

    enum FormError: LocalizedError {
        case notAuthenticated
        case serverError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not signed in. Please sign in to generate forms."
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
        let (data, _) = try await URLSession.shared.data(from: url)
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
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FormError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FormError.serverError(httpResponse.statusCode, message)
        }

        let filename = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
            .flatMap { header in
                header.components(separatedBy: "filename=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } ?? "\(request.airport)_\(request.form).pdf"

        return (data, filename)
    }
}
