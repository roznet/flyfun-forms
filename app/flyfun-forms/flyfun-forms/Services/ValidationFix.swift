import FlyFunCommon
import Foundation

/// What a pilot edits to clear one server validation error.
///
/// The server names the field in the request it rejected (`crew[0].id_number`,
/// `extra_fields.email`), which is often not where the value lives on device:
/// `email` is the responsible person's, `nationality` is the issuing country
/// of whichever document `DocumentResolver` picked. `ValidationFixContext`
/// maps one to the other so the errors sheet can offer the right editor.
/// `.none` keeps the row read-only, as every row used to be.
enum ValidationFix {
    case reasonForVisit(options: [String])
    case responsiblePerson
    case personText(Person, PersonTextField)
    case personDateOfBirth(Person)
    case personSex(Person)
    /// A field of the document the form would use. The document itself is
    /// looked up when the row is drawn, so adding one turns the row into its
    /// fields.
    case document(Person, DocumentField)
    case aircraftText(Aircraft, AircraftTextField)
    /// Owner and base come from a person, a company and an airport picker,
    /// so they open the aircraft's own editor.
    case openAircraft(Aircraft)
    case chooseAircraft
    case extraText(key: String)
    case extraChoice(key: String, options: [String])
    case none

    enum PersonTextField {
        case firstName, lastName, placeOfBirth, address, phone, email
    }

    enum DocumentField {
        case number, type, issuingCountry, expiry
    }

    enum AircraftTextField {
        case registration, type
    }

    /// The person the fix edits, to say whose value is missing.
    var person: Person? {
        switch self {
        case .personText(let p, _), .personDateOfBirth(let p), .personSex(let p), .document(let p, _):
            p
        default:
            nil
        }
    }
}

/// Everything needed to resolve the errors of one form request.
///
/// `crew` and `passengers` are the lists the request was built from, so
/// `crew[1]` names the same person even if the flight's relationship comes
/// back in another order later.
struct ValidationFixContext {
    let flight: Flight
    let airport: String
    let formInfo: FormInfo?
    let crew: [Person]
    let passengers: [Person]

    /// The key `FlightEditView` stores this form's extra field values under.
    var formKey: String { "\(airport)_\(formInfo?.id ?? "")" }

    func fix(for error: ServerValidationError) -> ValidationFix {
        let path = ValidationFieldPath(error.field)
        switch path.section {
        case "extra_fields":
            return extraFieldFix(key: path.key)
        case "flight":
            return path.key == "contact" ? .responsiblePerson : .none
        case "aircraft":
            return aircraftFix(key: path.key)
        case "crew", "passengers":
            let people = path.section == "crew" ? crew : passengers
            guard let index = path.index, people.indices.contains(index) else { return .none }
            return personFix(people[index], key: path.key)
        default:
            return .none
        }
    }

    private func extraFieldFix(key: String) -> ValidationFix {
        let info = formInfo?.extraFields.first { $0.key == key }
        switch key {
        case "reason_for_visit":
            return .reasonForVisit(options: info?.options ?? Flight.reasonForVisitOptions)
        case "responsible_person":
            return .responsiblePerson
        case "email", "telephone":
            // Sent from the responsible person, so the fix belongs on them and
            // is there for the next flight too.
            guard let person = flight.responsiblePerson else { return .responsiblePerson }
            return .personText(person, key == "email" ? .email : .phone)
        default:
            switch info?.type {
            case "choice":
                guard let options = info?.options, !options.isEmpty else { return .none }
                return .extraChoice(key: key, options: options)
            case "person":
                return .none
            default:
                return .extraText(key: key)
            }
        }
    }

    private func aircraftFix(key: String) -> ValidationFix {
        guard ["registration", "type", "owner", "owner_address", "usual_base"].contains(key) else { return .none }
        guard let aircraft = flight.aircraft else { return .chooseAircraft }
        switch key {
        case "registration": return .aircraftText(aircraft, .registration)
        case "type": return .aircraftText(aircraft, .type)
        default: return .openAircraft(aircraft)
        }
    }

    private func personFix(_ person: Person, key: String) -> ValidationFix {
        switch key {
        case "first_name": .personText(person, .firstName)
        case "last_name": .personText(person, .lastName)
        case "place_of_birth": .personText(person, .placeOfBirth)
        case "address": .personText(person, .address)
        case "dob": .personDateOfBirth(person)
        case "sex": .personSex(person)
        // Nationality is not stored on the person: it is sent from the
        // document's issuing country.
        case "nationality", "id_issuing_country": .document(person, .issuingCountry)
        case "id_number": .document(person, .number)
        case "id_type": .document(person, .type)
        case "id_expiry": .document(person, .expiry)
        default: .none
        }
    }

    /// The document the form request sends for this person.
    func document(for person: Person) -> TravelDocument? {
        DocumentResolver.resolve(person: person, airport: airport, chosenDocNumbers: flight.chosenDocNumberList)
    }
}

/// An API field path split into its parts: `crew[0].id_number` is section
/// `crew`, index 0, key `id_number`; `extra_fields.email` has no index; a bare
/// `crew` (a count error) has an empty key.
struct ValidationFieldPath: Equatable {
    let section: String
    let index: Int?
    let key: String

    init(section: String, index: Int?, key: String) {
        self.section = section
        self.index = index
        self.key = key
    }

    init(_ field: String) {
        let head: Substring
        if let dot = field.firstIndex(of: ".") {
            head = field[..<dot]
            key = String(field[field.index(after: dot)...])
        } else {
            head = Substring(field)
            key = ""
        }
        if let open = head.firstIndex(of: "["), let close = head.firstIndex(of: "]"), open < close {
            section = String(head[..<open])
            index = Int(head[head.index(after: open)..<close])
        } else {
            section = String(head)
            index = nil
        }
    }
}
