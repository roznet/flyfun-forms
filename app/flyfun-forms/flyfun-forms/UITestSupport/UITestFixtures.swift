#if DEBUG
import Foundation
import SwiftData

/// The store the XCUI suite runs against: in memory, never CloudKit, and
/// seeded with the same records on every launch.
///
/// Dates are relative to the launch day, so the upcoming flights stay upcoming
/// and the past one stays past however long after this was written the suite
/// runs. The journeys in `flyfun-formsUITests` name these records, so a change
/// here is a change to them.
@MainActor
enum UITestFixtures {

    /// Airport timezones, standing in for the reverse-geocode that normally
    /// resolves them. That lookup is a network call to Apple, so without this
    /// the zone pickers would sometimes offer a local zone and sometimes only
    /// UTC, and the schedule journey could not know which.
    static let timeZones: [String: String] = [
        "EGTF": "Europe/London",
        "LFRM": "Europe/Paris",
        "LFAC": "Europe/Paris",
        "LSGS": "Europe/Zurich",
    ]

    static func makeContainer(schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seed(container.mainContext)
            return container
        } catch {
            fatalError("Could not create the UI test ModelContainer: \(error)")
        }
    }

    /// - Test Pilot, usual crew, holding a French and a British passport, so
    ///   the document picked for a form depends on the airport's region.
    /// - Sample Passenger, a passenger with a French identity card.
    /// - Expired Traveller, whose only passport has expired.
    /// - ZZ-TEST, the one aircraft. ZZ is no nationality prefix, so no real
    ///   aircraft carries it; the names are as plainly made up.
    /// - EGTF → LFRM in 30 days and LFRM → EGTF two days later, as one trip.
    /// - EGTF → LFAC 20 days ago, in the past section.
    static func seed(_ context: ModelContext) {
        let pilot = person("Test", "Pilot", born: (1980, 4, 12), sex: "Female", usualCrew: true, in: context)
        pilot.phone = "+00 000 000 001"
        pilot.email = "pilot@example.com"
        pilot.address = "1 Test Street, Testville"
        document(for: pilot, "Passport", "FXA000001", "FRA", expiresInDays: 5 * 365, in: context)
        document(for: pilot, "Passport", "GBA000001", "GBR", expiresInDays: 3 * 365, in: context)

        let passenger = person("Sample", "Passenger", born: (1975, 9, 3), sex: "Male", usualCrew: false, in: context)
        document(for: passenger, "Identity card", "IDF000002", "FRA", expiresInDays: 4 * 365, in: context)

        let traveller = person("Expired", "Traveller", born: (1990, 1, 20), sex: "Female", usualCrew: false, in: context)
        document(for: traveller, "Passport", "DEA000003", "DEU", expiresInDays: -30, in: context)

        let aircraft = Aircraft(registration: "ZZ-TEST", type: "DR40")
        aircraft.owner = "Test Aero Club"
        aircraft.usualBase = "EGTF"
        context.insert(aircraft)

        let trip = Trip(name: "Test trip")
        context.insert(trip)

        let outbound = flight("EGTF", "LFRM", day: 30, departureHour: 9, arrivalHour: 10, in: context)
        outbound.aircraft = aircraft
        outbound.crew = [pilot]
        outbound.passengers = [passenger]
        outbound.responsiblePerson = pilot
        outbound.trip = trip
        outbound.legOrder = 0

        let inbound = flight("LFRM", "EGTF", day: 32, departureHour: 12, arrivalHour: 13, in: context)
        inbound.aircraft = aircraft
        inbound.crew = [pilot]
        inbound.passengers = [passenger]
        inbound.responsiblePerson = pilot
        inbound.trip = trip
        inbound.legOrder = 1

        let past = flight("EGTF", "LFAC", day: -20, departureHour: 8, arrivalHour: 9, in: context)
        past.aircraft = aircraft
        past.crew = [pilot]
        past.passengers = [traveller]

        try? context.save()
    }

    // MARK: - Builders

    private static func person(
        _ first: String, _ last: String, born: (Int, Int, Int), sex: String, usualCrew: Bool,
        in context: ModelContext
    ) -> Person {
        let person = Person(firstName: first, lastName: last)
        // Date-only fields are midnight in the device's zone, as the editor writes them.
        person.dateOfBirth = Calendar.current.date(
            from: DateComponents(year: born.0, month: born.1, day: born.2)
        )
        person.sex = sex
        person.isUsualCrew = usualCrew
        context.insert(person)
        return person
    }

    private static func document(
        for person: Person, _ type: String, _ number: String, _ country: String,
        expiresInDays days: Int, in context: ModelContext
    ) {
        let today = Calendar.current.startOfDay(for: Date())
        let doc = TravelDocument(
            docType: type,
            docNumber: number,
            issuingCountry: country,
            expiryDate: Calendar.current.date(byAdding: .day, value: days, to: today)
        )
        doc.person = person
        context.insert(doc)
    }

    /// A leg `day` days from today, departing and arriving on the hour, UTC.
    private static func flight(
        _ origin: String, _ destination: String, day: Int, departureHour: Int, arrivalHour: Int,
        in context: ModelContext
    ) -> Flight {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let midnight = utc.date(byAdding: .day, value: day, to: utc.startOfDay(for: Date()))!

        let flight = Flight()
        flight.originICAO = origin
        flight.destinationICAO = destination
        // Through the setters, which write the legacy day + time pair and the instant together.
        flight.departureDateTime = utc.date(byAdding: .hour, value: departureHour, to: midnight)!
        flight.arrivalDateTime = utc.date(byAdding: .hour, value: arrivalHour, to: midnight)!
        context.insert(flight)
        return flight
    }
}
#endif
