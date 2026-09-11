import Foundation

// MARK: - Airport Catalog (from GET /airports)

struct AirportCatalogResponse: Codable {
    var airports: [AirportInfo]
    var prefixes: [PrefixInfo]
}

struct AirportInfo: Codable, Identifiable {
    var icao: String
    var name: String
    var forms: [String]

    var id: String { icao }
}

struct PrefixInfo: Codable, Identifiable {
    var prefix: String
    var country: String
    var forms: [String]

    var id: String { prefix }
}

// MARK: - Airport Detail (from GET /airports/{icao})

struct AirportDetailResponse: Codable {
    var icao: String
    var name: String
    var forms: [FormInfo]
}

struct EmailConfig: Codable {
    var to: [String]
    var cc: [String]
}

struct FormInfo: Codable, Identifiable {
    var id: String
    var label: String
    var version: String
    var requiredFields: RequiredFields
    var extraFields: [ExtraFieldInfo]
    var maxCrew: Int
    var maxPassengers: Int
    var hasConnectingFlight: Bool
    /// Send the flight coming back to the airport (book-outs). Optional so
    /// older servers keep parsing.
    var hasReturnFlight: Bool?
    var timeReference: String
    var sendTo: String?
    var email: EmailConfig?
    /// "document" (a generated file) or "web" (an official web page the app
    /// opens and prefills). Optional so older servers keep parsing.
    var kind: String?
    /// "departure" / "arrival" when the form only applies to one side
    var direction: String?

    var isWebForm: Bool { kind == "web" }

    enum CodingKeys: String, CodingKey {
        case id, label, version
        case requiredFields = "required_fields"
        case extraFields = "extra_fields"
        case maxCrew = "max_crew"
        case maxPassengers = "max_passengers"
        case hasConnectingFlight = "has_connecting_flight"
        case hasReturnFlight = "has_return_flight"
        case timeReference = "time_reference"
        case sendTo = "send_to"
        case email, kind, direction
    }
}

// MARK: - Web Form Fill Plan (POST /prefill)

/// How to prefill an official web form: its page, and a value per input
/// keyed by the input's `name`.
struct FillPlan: Codable, Identifiable {
    var form: String
    var label: String
    var url: URL
    /// CSS selector of the `<form>` to fill, for pages holding several
    var scope: String?
    /// Shown to the pilot above the page
    var note: String?
    var fields: [FillField]

    var id: String { form }
}

struct FillField: Codable {
    var name: String
    var value: String
    /// "text" or "checkbox" (value "true" / "false")
    var type: String
}

struct RequiredFields: Codable {
    var flight: [String]
    var aircraft: [String]
    var crew: [String]
    var passengers: [String]
}

struct ExtraFieldInfo: Codable, Identifiable {
    var key: String
    var label: String
    var type: String
    var options: [String]?
    var mapsTo: [String: String]?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, type, options
        case mapsTo = "maps_to"
    }
}

// MARK: - Extra Field Value (supports string and person dict)

enum ExtraFieldValue: Codable {
    case text(String)
    case person([String: String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str):
            try container.encode(str)
        case .person(let dict):
            try container.encode(dict)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else if let dict = try? container.decode([String: String].self) {
            self = .person(dict)
        } else {
            self = .text("")
        }
    }
}

// MARK: - Email Text (POST /email-text)

struct EmailTextRequest: Codable {
    var airport: String
    var form: String
    var origin: String
    var destination: String
    var departureDate: String
    var registration: String
    var aircraftType: String?

    enum CodingKeys: String, CodingKey {
        case airport, form, origin, destination, registration
        case departureDate = "departure_date"
        case aircraftType = "aircraft_type"
    }
}

struct EmailTextResponse: Codable {
    var subjectEn: String
    var bodyEn: String
    var subjectLocal: String
    var bodyLocal: String
    /// ISO 639-1 code for the airport's local language (e.g. "fr", "de"),
    /// or nil/empty when unknown / English-speaking. Optional so older
    /// servers without this field keep parsing.
    var localLanguage: String?

    enum CodingKeys: String, CodingKey {
        case subjectEn = "subject_en"
        case bodyEn = "body_en"
        case subjectLocal = "subject_local"
        case bodyLocal = "body_local"
        case localLanguage = "local_language"
    }
}

// MARK: - Generate Request (POST /generate)

struct GenerateRequest: Codable {
    var airport: String
    var form: String
    var flight: FlightPayload
    var aircraft: AircraftPayload
    var crew: [PersonPayload]
    var passengers: [PersonPayload]
    var connectingFlight: FlightPayload?
    var returnFlight: ReturnFlightPayload?
    var extraFields: [String: ExtraFieldValue]?
    var observations: String?

    enum CodingKeys: String, CodingKey {
        case airport, form, flight, aircraft, crew, passengers
        case connectingFlight = "connecting_flight"
        case returnFlight = "return_flight"
        case extraFields = "extra_fields"
        case observations
    }
}

/// The flight coming back to the airport after a departure (book-outs ask
/// when, and from where, you'll be back).
struct ReturnFlightPayload: Codable {
    var origin: String
    var destination: String
    var departureDate: String
    var departureTimeUtc: String
    var arrivalDate: String
    var arrivalTimeUtc: String
    var peopleOnBoard: Int

    enum CodingKeys: String, CodingKey {
        case origin, destination
        case departureDate = "departure_date"
        case departureTimeUtc = "departure_time_utc"
        case arrivalDate = "arrival_date"
        case arrivalTimeUtc = "arrival_time_utc"
        case peopleOnBoard = "people_on_board"
    }
}

struct FlightPayload: Codable {
    var origin: String
    var destination: String
    var departureDate: String
    var departureTimeUtc: String
    var arrivalDate: String
    var arrivalTimeUtc: String
    var nature: String?
    var contact: String?

    enum CodingKeys: String, CodingKey {
        case origin, destination
        case departureDate = "departure_date"
        case departureTimeUtc = "departure_time_utc"
        case arrivalDate = "arrival_date"
        case arrivalTimeUtc = "arrival_time_utc"
        case nature, contact
    }
}

struct AircraftPayload: Codable {
    var registration: String
    var type: String
    var owner: String?
    var ownerAddress: String?
    var isAirplane: Bool?
    var usualBase: String?

    enum CodingKeys: String, CodingKey {
        case registration, type, owner
        case ownerAddress = "owner_address"
        case isAirplane = "is_airplane"
        case usualBase = "usual_base"
    }
}

struct PersonPayload: Codable {
    var function: String?
    var firstName: String
    var lastName: String
    var dob: String?
    var nationality: String?
    var idNumber: String?
    var idType: String?
    var idIssuingCountry: String?
    var idExpiry: String?
    var sex: String?
    var placeOfBirth: String?
    var address: String?

    enum CodingKeys: String, CodingKey {
        case function
        case firstName = "first_name"
        case lastName = "last_name"
        case dob, nationality
        case idNumber = "id_number"
        case idType = "id_type"
        case idIssuingCountry = "id_issuing_country"
        case idExpiry = "id_expiry"
        case sex
        case placeOfBirth = "place_of_birth"
        case address
    }
}
