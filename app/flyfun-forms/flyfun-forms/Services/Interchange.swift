import Foundation

// The "Move my data" interchange format, `flyfun-forms/data` version 1.
//
// A port of Android's `core-logic/.../Interchange.kt`, which is the reference:
// same field names, same optionality, same defaults, same merge rules. Pure
// value types and functions, with SwiftData only in `DataTransfer.swift`, so
// each case can be checked against the Kotlin tests.
//
// Spec: designs/future/move-my-data.md §4 (format) and §6 (merge). Flat arrays
// with an explicit join table; every record carries `updatedAt` and a nullable
// `deletedAt` tombstone. Absolute moments are ISO-8601 with `Z`
// (`InterchangeTime`); calendar days are plain `YYYY-MM-DD` (`InterchangeDay`).
//
// Decoding mirrors kotlinx.serialization with `ignoreUnknownKeys`: unknown keys
// are ignored, a missing key with a Kotlin default takes that default, and a
// missing key without one (`id`, `updatedAt`, ...) fails the decode. Encoding
// omits nil values, as Android's `explicitNulls = false` does.

struct InterchangeDocument: Codable, Equatable {
    static let format = "flyfun-forms/data"
    static let version = 1

    var format: String = InterchangeDocument.format
    var version: Int = InterchangeDocument.version
    var exportedAt: String
    var exportedBy: ExportedBy = ExportedBy()
    var people: [PersonRecord] = []
    var travelDocuments: [TravelDocumentRecord] = []
    var aircraft: [AircraftRecord] = []
    var trips: [TripRecord] = []
    var flights: [FlightRecord] = []
    var flightPeople: [FlightPersonRecord] = []

    init(
        exportedAt: String,
        exportedBy: ExportedBy = ExportedBy(),
        people: [PersonRecord] = [],
        travelDocuments: [TravelDocumentRecord] = [],
        aircraft: [AircraftRecord] = [],
        trips: [TripRecord] = [],
        flights: [FlightRecord] = [],
        flightPeople: [FlightPersonRecord] = []
    ) {
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
        self.people = people
        self.travelDocuments = travelDocuments
        self.aircraft = aircraft
        self.trips = trips
        self.flights = flights
        self.flightPeople = flightPeople
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? Self.format
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        exportedAt = try c.decode(String.self, forKey: .exportedAt)
        exportedBy = try c.decodeIfPresent(ExportedBy.self, forKey: .exportedBy) ?? ExportedBy()
        people = try c.decodeIfPresent([PersonRecord].self, forKey: .people) ?? []
        travelDocuments = try c.decodeIfPresent([TravelDocumentRecord].self, forKey: .travelDocuments) ?? []
        aircraft = try c.decodeIfPresent([AircraftRecord].self, forKey: .aircraft) ?? []
        trips = try c.decodeIfPresent([TripRecord].self, forKey: .trips) ?? []
        flights = try c.decodeIfPresent([FlightRecord].self, forKey: .flights) ?? []
        flightPeople = try c.decodeIfPresent([FlightPersonRecord].self, forKey: .flightPeople) ?? []
    }
}

struct ExportedBy: Codable, Equatable {
    /// "ios", "macos" or "android".
    var platform: String = "ios"
    var appVersion: String = ""

    init(platform: String = "ios", appVersion: String = "") {
        self.platform = platform
        self.appVersion = appVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Android's default is "android": a file without it came from there.
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "android"
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
    }
}

/// The shape every mergeable record shares.
protocol InterchangeRecord: Equatable {
    var id: String { get }
    var updatedAt: String { get }
    var deletedAt: String? { get }
}

struct PersonRecord: InterchangeRecord, Codable {
    var id: String
    var firstName: String = ""
    var lastName: String = ""
    var dateOfBirth: String?
    var sex: String?
    var placeOfBirth: String?
    var address: String?
    var phone: String?
    var email: String?
    var isUsualCrew: Bool = false
    var updatedAt: String
    var deletedAt: String?

    init(
        id: String, firstName: String = "", lastName: String = "", dateOfBirth: String? = nil,
        sex: String? = nil, placeOfBirth: String? = nil, address: String? = nil,
        phone: String? = nil, email: String? = nil, isUsualCrew: Bool = false,
        updatedAt: String, deletedAt: String? = nil
    ) {
        self.id = id; self.firstName = firstName; self.lastName = lastName
        self.dateOfBirth = dateOfBirth; self.sex = sex; self.placeOfBirth = placeOfBirth
        self.address = address; self.phone = phone; self.email = email
        self.isUsualCrew = isUsualCrew; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth)
        sex = try c.decodeIfPresent(String.self, forKey: .sex)
        placeOfBirth = try c.decodeIfPresent(String.self, forKey: .placeOfBirth)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isUsualCrew = try c.decodeIfPresent(Bool.self, forKey: .isUsualCrew) ?? false
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct TravelDocumentRecord: InterchangeRecord, Codable {
    var id: String
    var personId: String
    var docType: String = "Passport"
    var docNumber: String = ""
    var issuingCountry: String?
    var expiryDate: String?
    var isActive: Bool = true
    var updatedAt: String
    var deletedAt: String?

    init(
        id: String, personId: String, docType: String = "Passport", docNumber: String = "",
        issuingCountry: String? = nil, expiryDate: String? = nil, isActive: Bool = true,
        updatedAt: String, deletedAt: String? = nil
    ) {
        self.id = id; self.personId = personId; self.docType = docType; self.docNumber = docNumber
        self.issuingCountry = issuingCountry; self.expiryDate = expiryDate; self.isActive = isActive
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        personId = try c.decode(String.self, forKey: .personId)
        docType = try c.decodeIfPresent(String.self, forKey: .docType) ?? "Passport"
        docNumber = try c.decodeIfPresent(String.self, forKey: .docNumber) ?? ""
        issuingCountry = try c.decodeIfPresent(String.self, forKey: .issuingCountry)
        expiryDate = try c.decodeIfPresent(String.self, forKey: .expiryDate)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct AircraftRecord: InterchangeRecord, Codable {
    var id: String
    var registration: String = ""
    var type: String = ""
    var owner: String?
    var ownerAddress: String?
    var isAirplane: Bool = true
    var usualBase: String?
    var ownerPersonId: String?
    var useCompanyOperator: Bool = false
    var operatorName: String?
    var updatedAt: String
    var deletedAt: String?

    init(
        id: String, registration: String = "", type: String = "", owner: String? = nil,
        ownerAddress: String? = nil, isAirplane: Bool = true, usualBase: String? = nil,
        ownerPersonId: String? = nil, useCompanyOperator: Bool = false, operatorName: String? = nil,
        updatedAt: String, deletedAt: String? = nil
    ) {
        self.id = id; self.registration = registration; self.type = type; self.owner = owner
        self.ownerAddress = ownerAddress; self.isAirplane = isAirplane; self.usualBase = usualBase
        self.ownerPersonId = ownerPersonId; self.useCompanyOperator = useCompanyOperator
        self.operatorName = operatorName; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        registration = try c.decodeIfPresent(String.self, forKey: .registration) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        ownerAddress = try c.decodeIfPresent(String.self, forKey: .ownerAddress)
        isAirplane = try c.decodeIfPresent(Bool.self, forKey: .isAirplane) ?? true
        usualBase = try c.decodeIfPresent(String.self, forKey: .usualBase)
        ownerPersonId = try c.decodeIfPresent(String.self, forKey: .ownerPersonId)
        useCompanyOperator = try c.decodeIfPresent(Bool.self, forKey: .useCompanyOperator) ?? false
        operatorName = try c.decodeIfPresent(String.self, forKey: .operatorName)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct TripRecord: InterchangeRecord, Codable {
    var id: String
    var name: String = ""
    var createdAt: String
    var extraFields: [String: String] = [:]
    var updatedAt: String
    var deletedAt: String?

    init(
        id: String, name: String = "", createdAt: String, extraFields: [String: String] = [:],
        updatedAt: String, deletedAt: String? = nil
    ) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.extraFields = extraFields
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        createdAt = try c.decode(String.self, forKey: .createdAt)
        extraFields = try c.decodeIfPresent([String: String].self, forKey: .extraFields) ?? [:]
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct FlightRecord: InterchangeRecord, Codable {
    var id: String
    var originICAO: String = ""
    var destinationICAO: String = ""
    var departureInstant: String
    var arrivalInstant: String
    var nature: String = "private"
    var observations: String?
    var contact: String?
    var reasonForVisit: String?
    var aircraftId: String?
    var responsiblePersonId: String?
    var tripId: String?
    var legOrder: Int = 0
    /// Documents picked by hand for this flight, by number. Absent in files
    /// from before it existed.
    var chosenDocNumbers: [String]?
    var updatedAt: String
    var deletedAt: String?

    init(
        id: String, originICAO: String = "", destinationICAO: String = "",
        departureInstant: String, arrivalInstant: String, nature: String = "private",
        observations: String? = nil, contact: String? = nil, reasonForVisit: String? = nil,
        aircraftId: String? = nil, responsiblePersonId: String? = nil, tripId: String? = nil,
        legOrder: Int = 0, chosenDocNumbers: [String]? = nil,
        updatedAt: String, deletedAt: String? = nil
    ) {
        self.id = id; self.originICAO = originICAO; self.destinationICAO = destinationICAO
        self.departureInstant = departureInstant; self.arrivalInstant = arrivalInstant
        self.nature = nature; self.observations = observations; self.contact = contact
        self.reasonForVisit = reasonForVisit; self.aircraftId = aircraftId
        self.responsiblePersonId = responsiblePersonId; self.tripId = tripId
        self.legOrder = legOrder; self.chosenDocNumbers = chosenDocNumbers
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        originICAO = try c.decodeIfPresent(String.self, forKey: .originICAO) ?? ""
        destinationICAO = try c.decodeIfPresent(String.self, forKey: .destinationICAO) ?? ""
        departureInstant = try c.decode(String.self, forKey: .departureInstant)
        arrivalInstant = try c.decode(String.self, forKey: .arrivalInstant)
        nature = try c.decodeIfPresent(String.self, forKey: .nature) ?? "private"
        observations = try c.decodeIfPresent(String.self, forKey: .observations)
        contact = try c.decodeIfPresent(String.self, forKey: .contact)
        reasonForVisit = try c.decodeIfPresent(String.self, forKey: .reasonForVisit)
        aircraftId = try c.decodeIfPresent(String.self, forKey: .aircraftId)
        responsiblePersonId = try c.decodeIfPresent(String.self, forKey: .responsiblePersonId)
        tripId = try c.decodeIfPresent(String.self, forKey: .tripId)
        legOrder = try c.decodeIfPresent(Int.self, forKey: .legOrder) ?? 0
        chosenDocNumbers = try c.decodeIfPresent([String].self, forKey: .chosenDocNumbers)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

/// One person on one flight. Not versioned per row: membership travels with
/// its flight.
struct FlightPersonRecord: Codable, Equatable {
    static let crew = "crew"
    static let passenger = "passenger"

    var flightId: String
    var personId: String
    /// ``crew`` or ``passenger``, as Android's `FlightRole`.
    var role: String
    var seatOrder: Int = 0

    init(flightId: String, personId: String, role: String, seatOrder: Int = 0) {
        self.flightId = flightId; self.personId = personId; self.role = role; self.seatOrder = seatOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flightId = try c.decode(String.self, forKey: .flightId)
        personId = try c.decode(String.self, forKey: .personId)
        role = try c.decode(String.self, forKey: .role)
        seatOrder = try c.decodeIfPresent(Int.self, forKey: .seatOrder) ?? 0
    }
}

// MARK: - Merge

/// What an import would do to one kind of record, shown before anything is
/// written.
struct MergeOutcome<T: InterchangeRecord>: Equatable {
    var insert: [T] = []
    var update: [T] = []
    var remove: [T] = []
    var unchanged: Int = 0
}

struct MergeSummary: Equatable {
    var people = MergeOutcome<PersonRecord>()
    var travelDocuments = MergeOutcome<TravelDocumentRecord>()
    var aircraft = MergeOutcome<AircraftRecord>()
    var trips = MergeOutcome<TripRecord>()
    var flights = MergeOutcome<FlightRecord>()
    var flightPeople: [FlightPersonRecord] = []

    var inserted: Int {
        people.insert.count + travelDocuments.insert.count + aircraft.insert.count
            + trips.insert.count + flights.insert.count
    }
    var updated: Int {
        people.update.count + travelDocuments.update.count + aircraft.update.count
            + trips.update.count + flights.update.count
    }
    var removed: Int {
        people.remove.count + travelDocuments.remove.count + aircraft.remove.count
            + trips.remove.count + flights.remove.count
    }
    var untouched: Int {
        people.unchanged + travelDocuments.unchanged + aircraft.unchanged
            + trips.unchanged + flights.unchanged
    }

    /// One line for the confirm sheet: "N new · N updated · N removed · N unchanged".
    var localizedDescription: String {
        String(localized: "\(inserted) new · \(updated) updated · \(removed) removed · \(untouched) unchanged",
               comment: "Import preview: counts of records the import adds, changes, removes and leaves alone")
    }
}

enum InterchangeMerge {

    /// Everything currently held, in interchange shape, tombstones included.
    struct LocalSnapshot: Equatable {
        var people: [PersonRecord] = []
        var travelDocuments: [TravelDocumentRecord] = []
        var aircraft: [AircraftRecord] = []
        var trips: [TripRecord] = []
        var flights: [FlightRecord] = []
    }

    enum Failure: LocalizedError, Equatable {
        case notOurFile
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .notOurFile:
                return String(localized: "This is not a FlyFun Forms data file.")
            case .newerVersion:
                return String(localized: "This file was written by a newer version of the app.")
            }
        }
    }

    /// Whether `incoming` is a later instant than `existing`.
    ///
    /// Compared as instants, not strings: Android writes 0, 3, 6 or 9
    /// fractional digits depending on precision, so "…:12Z" sorts after
    /// "…:12.500Z" as a string though it is half a second earlier. Falls back
    /// to string order only if a value is unparseable, as Android does.
    static func isNewer(_ incoming: String, than existing: String) -> Bool {
        guard let a = InterchangeTime.parse(incoming), let b = InterchangeTime.parse(existing) else {
            return incoming > existing
        }
        return a > b
    }

    /// Decides what an import changes, per record. Rules from
    /// move-my-data.md §6, identical to Android's `InterchangeMerge.merge`:
    ///
    /// - in the file, not local: insert, unless it is a tombstone
    /// - in both, file not newer: unchanged
    /// - in both, file newer and a tombstone: remove
    /// - in both, file newer: update, whole record
    /// - local only: kept; an import never deletes what the file does not mention
    ///
    /// `local` includes local tombstones, so a live record whose id was
    /// deleted here more recently is unchanged (not brought back), and one
    /// deleted here earlier than the file's edit comes back as an update.
    static func merge<T: InterchangeRecord>(local: [T], incoming: [T]) -> MergeOutcome<T> {
        var byId: [String: T] = [:]
        for record in local { byId[record.id] = record }
        var outcome = MergeOutcome<T>()
        for record in incoming {
            if let existing = byId[record.id] {
                if !isNewer(record.updatedAt, than: existing.updatedAt) {
                    outcome.unchanged += 1
                } else if record.deletedAt != nil {
                    outcome.remove.append(record)
                } else {
                    outcome.update.append(record)
                }
            } else if record.deletedAt == nil {
                outcome.insert.append(record)
            } else {
                outcome.unchanged += 1
            }
        }
        return outcome
    }

    static func summarise(local: LocalSnapshot, document: InterchangeDocument) -> MergeSummary {
        let flights = merge(local: local.flights, incoming: document.flights)
        // Membership is not versioned on its own: it rides with its flight,
        // and only for the flights this merge is going to write.
        let written = Set((flights.insert + flights.update).map(\.id))
        return MergeSummary(
            people: merge(local: local.people, incoming: document.people),
            travelDocuments: merge(local: local.travelDocuments, incoming: document.travelDocuments),
            aircraft: merge(local: local.aircraft, incoming: document.aircraft),
            trips: merge(local: local.trips, incoming: document.trips),
            flights: flights,
            flightPeople: document.flightPeople.filter { written.contains($0.flightId) }
        )
    }

    static func encode(_ document: InterchangeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// - Throws: ``Failure/notOurFile`` when the data is not one of our files,
    ///   ``Failure/newerVersion`` for a version this build cannot read. Better
    ///   to say so than to half-import.
    static func decode(_ data: Data) throws -> InterchangeDocument {
        let document: InterchangeDocument
        do {
            document = try JSONDecoder().decode(InterchangeDocument.self, from: data)
        } catch {
            throw Failure.notOurFile
        }
        guard document.format == InterchangeDocument.format else { throw Failure.notOurFile }
        guard document.version <= InterchangeDocument.version else { throw Failure.newerVersion }
        return document
    }
}

// MARK: - Dates

/// Absolute moments in the file: ISO-8601 with an explicit `Z`.
enum InterchangeTime {

    /// What a record with no `updatedAt` (one from before stable ids) is
    /// written with: older than anything, so any real edit on the other side
    /// wins. Never "now", which would let stale data win.
    static let oldest = "1970-01-01T00:00:00Z"

    /// `2026-09-18T14:22:03Z`, or `…03.250Z` when there are milliseconds.
    ///
    /// Truncated, never rounded, to the millisecond: the file must not claim a
    /// record is newer than it is, or re-importing a file into the device that
    /// wrote it would update records with themselves.
    static func format(_ date: Date) -> String {
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let seconds = Date(timeIntervalSince1970: TimeInterval(millis.floorDiv(1000)))
        let base = wholeSeconds.string(from: seconds)
        let fraction = millis.floorMod(1000)
        guard fraction != 0 else { return base }
        return String(base.dropLast()) + String(format: ".%03dZ", Int32(fraction))
    }

    /// The instant `value` names, or nil. Accepts any number of fractional
    /// digits and a `Z` or `±hh:mm` offset; Android's `Instant.toString()`
    /// writes 0, 3, 6 or 9 digits.
    static func parse(_ value: String) -> Date? {
        guard let match = value.wholeMatch(of: pattern) else { return nil }
        let (_, base, fraction, zone) = match.output
        guard let whole = wholeSeconds.date(from: String(base) + String(zone)) else { return nil }
        guard let fraction, let digits = Double("0" + fraction) else { return whole }
        return whole.addingTimeInterval(digits)
    }

    private static let pattern =
        /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})/

    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Calendar days in the file (a birth date, a passport expiry): `YYYY-MM-DD`.
///
/// Stored days are midnight in the device's time zone, so they are formatted
/// and parsed in that zone, exactly as the API mapping does
/// (`FlightEditView.dateFmt`). Reading one in any other zone shifts it by a day.
enum InterchangeDay {

    static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone).string(from: date)
    }

    /// Midnight on that day in `timeZone`, or nil for anything that is not a
    /// real `YYYY-MM-DD` day.
    static func parse(_ value: String, timeZone: TimeZone = .current) -> Date? {
        formatter(timeZone).date(from: value)
    }

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        return formatter
    }
}

private extension Int64 {
    func floorDiv(_ divisor: Int64) -> Int64 {
        let q = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? q - 1 : q
    }

    func floorMod(_ divisor: Int64) -> Int64 {
        self - floorDiv(divisor) * divisor
    }
}
