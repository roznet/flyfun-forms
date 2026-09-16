import Testing
import Foundation
import SwiftData
import RZFlight
@testable import flyfun_forms

// MARK: - Helpers

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = .gmt
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: components)!
}

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
        configurations: config
    )
}

// MARK: - Rescheduling a repeated flight

@Suite("Flight.nextOccurrence")
struct NextOccurrenceTests {

    @Test("keeps the time of day and lands today when it is still ahead")
    func landsToday() {
        let result = Flight.nextOccurrence(
            departure: utc(2026, 3, 1, 14, 30),
            arrival: utc(2026, 3, 1, 16, 0),
            now: utc(2026, 9, 16, 9, 0)
        )
        #expect(result.departure == utc(2026, 9, 16, 14, 30))
    }

    @Test("rolls to tomorrow once the time of day has passed")
    func rollsToTomorrow() {
        let result = Flight.nextOccurrence(
            departure: utc(2026, 3, 1, 8, 0),
            arrival: utc(2026, 3, 1, 9, 30),
            now: utc(2026, 9, 16, 9, 0)
        )
        #expect(result.departure == utc(2026, 9, 17, 8, 0))
    }

    @Test("carries the leg's duration rather than realigning onto the day")
    func keepsDuration() {
        // An overnight leg: 22:00 to 01:30 the next day. Aligning the arrival
        // onto the departure day would put it 20.5 hours *before* departure.
        let result = Flight.nextOccurrence(
            departure: utc(2026, 3, 1, 22, 0),
            arrival: utc(2026, 3, 2, 1, 30),
            now: utc(2026, 9, 16, 9, 0)
        )
        #expect(result.departure == utc(2026, 9, 16, 22, 0))
        #expect(result.arrival == utc(2026, 9, 17, 1, 30))
        #expect(result.arrival.timeIntervalSince(result.departure) == 3.5 * 3600)
    }

    @Test("reads the time of day in the origin's zone, not UTC")
    func usesOriginZone() {
        // 09:00 local in Zurich (UTC+2 in September) is 07:00Z. Repeating it
        // must keep 09:00 local, so 07:00Z — not 09:00Z, which would be 11:00
        // local and an hour the pilot never flies.
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        let result = Flight.nextOccurrence(
            departure: utc(2026, 6, 1, 7, 0),
            arrival: utc(2026, 6, 1, 8, 30),
            now: utc(2026, 9, 16, 4, 0),
            zone: zurich
        )
        #expect(result.departure == utc(2026, 9, 16, 7, 0))
    }

    @Test("a flight with no arrival time does not produce one before departure")
    func clampsNegativeDuration() {
        // A flight where no arrival was ever entered reads back as midnight of
        // its day, which is before the departure.
        let result = Flight.nextOccurrence(
            departure: utc(2026, 3, 1, 14, 0),
            arrival: utc(2026, 3, 1, 0, 0),
            now: utc(2026, 9, 16, 9, 0)
        )
        #expect(result.arrival == result.departure)
    }
}

// MARK: - Drafts

@Suite("FlightDraft")
@MainActor
struct FlightDraftTests {

    @Test("repeating a flight carries its people and aircraft")
    func repeatingCarriesPeople() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let pilot = Person(firstName: "Zara", lastName: "Kowalski")
        let passenger = Person(firstName: "Ola", lastName: "Nowak")
        let aircraft = Aircraft(registration: "HB-ABC", type: "P28A")
        context.insert(pilot)
        context.insert(passenger)
        context.insert(aircraft)

        let flight = Flight()
        flight.originICAO = "EGTF"
        flight.destinationICAO = "LFRM"
        flight.departureDateTime = utc(2026, 3, 1, 10, 0)
        flight.arrivalDateTime = utc(2026, 3, 1, 11, 30)
        flight.aircraft = aircraft
        flight.crew = [pilot]
        flight.passengers = [passenger]
        flight.observations = "Weekend trip"
        context.insert(flight)

        let draft = FlightDraft(repeating: flight, now: utc(2026, 9, 16, 9, 0))

        #expect(draft.route.departure == "EGTF")
        #expect(draft.route.destination == "LFRM")
        #expect(draft.registration == "HB-ABC")
        #expect(draft.crew.count == 1)
        #expect(draft.passengers.count == 1)
        #expect(draft.observations == "Weekend trip")
        #expect(draft.hasPeople)
        // 10:00 is past 09:00 today? No — still ahead, so today.
        #expect(draft.route.departureTime == utc(2026, 9, 16, 10, 0))
    }

    @Test("a parsed flight plan brings no people, so the suggestion still shows")
    func planCarriesNoPeople() throws {
        // Shaped like RZFlight's own IFR fixture, so this tests the draft
        // conversion rather than the parser (which has its own tests).
        let fpl = """
        (FPL-GZIPM-IS
        -C172/L-S/C
        -EGTF1030
        -N0110F065 HAZEL UL9 ORTAC L28 DINARD
        -LFAT0130
        -DOF/260326 PBN/D2)
        """
        let plan = try #require(ICAOFlightPlanParser.parse(fpl))
        let draft = FlightDraft(plan)

        #expect(draft.route.departure == "EGTF")
        #expect(draft.route.destination == "LFAT")
        #expect(!draft.hasPeople)
        #expect(draft.provenance == .clipboard)
    }
}

// MARK: - Method ranking

@Suite("FlightImportMethod ranking")
struct ImportRankingTests {

    @Test("a flight plan on the clipboard outranks everything")
    func clipboardWins() {
        let context = FlightImportContext(
            hasPastFlights: true, clipboardHasText: true, isSignedIn: true
        )
        #expect(FlightImportMethod.ranked(for: context) == .clipboardFPL)
    }

    @Test("with an empty clipboard, a previous flight is the offer")
    func previousFlightNext() {
        let context = FlightImportContext(
            hasPastFlights: true, clipboardHasText: false, isSignedIn: true
        )
        #expect(FlightImportMethod.ranked(for: context) == .previousFlight)
    }

    @Test("a first-run signed-in pilot is offered weather")
    func firstRunSignedIn() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false, isSignedIn: true
        )
        #expect(FlightImportMethod.ranked(for: context) == .weather)
    }

    @Test("a fresh install with nothing available still has a primary")
    func freshInstallHasAPrimary() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false, isSignedIn: false
        )
        // Never nil: the button always says something, and the method reports
        // why it can't run rather than the row vanishing.
        #expect(FlightImportMethod.ranked(for: context) == .clipboardFPL)
    }

    @Test("unavailable methods explain themselves rather than being hidden")
    func unavailableMethodsExplain() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false,
            isSignedIn: false, autorouterLinked: false
        )
        for method in FlightImportMethod.allCases {
            guard case .unavailable(let reason) = method.availability(in: context) else {
                Issue.record("\(method) should be unavailable in an empty context")
                continue
            }
            #expect(!reason.isEmpty)
        }
    }

    @Test("Autorouter is greyed with its reason when the account is not linked")
    func autorouterNeedsLinking() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false,
            isSignedIn: true, autorouterLinked: false
        )
        guard case .unavailable(let reason) =
            FlightImportMethod.autorouter.availability(in: context) else {
            Issue.record("Autorouter should be unavailable when not linked")
            return
        }
        // Signing in is not the missing piece, so the reason must not say so.
        #expect(reason.contains("Autorouter"))
    }

    @Test("an unfinished link check does not hide a method that works")
    func unknownLinkStateStaysAvailable() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false,
            isSignedIn: true, autorouterLinked: nil
        )
        #expect(FlightImportMethod.autorouter.availability(in: context).isAvailable)
    }

    @Test("a linked account has Autorouter available")
    func linkedAccountIsAvailable() {
        let context = FlightImportContext(
            hasPastFlights: false, clipboardHasText: false,
            isSignedIn: true, autorouterLinked: true
        )
        #expect(FlightImportMethod.autorouter.availability(in: context).isAvailable)
    }

    @Test("the primary button names the flight it would repeat")
    func primaryLabelNamesTheRoute() {
        let context = FlightImportContext(
            hasPastFlights: true,
            clipboardHasText: false,
            isSignedIn: true,
            mostRecentRoute: "EGTF > LFRM"
        )
        let label = FlightImportMethod.primaryLabel(for: .previousFlight, context: context)
        #expect(label.contains("EGTF > LFRM"))
    }
}

// MARK: - People suggestion

@Suite("PeopleSuggestion")
@MainActor
struct PeopleSuggestionTests {

    private func makeFlight(
        context: ModelContext,
        departure: Date,
        aircraft: Aircraft?,
        crew: [Person],
        passengers: [Person] = []
    ) -> Flight {
        let flight = Flight()
        flight.originICAO = "EGTF"
        flight.destinationICAO = "LFRM"
        flight.departureDateTime = departure
        flight.aircraft = aircraft
        flight.crew = crew
        flight.passengers = passengers
        context.insert(flight)
        return flight
    }

    @Test("prefers the most recent flight in the same aircraft")
    func prefersSameAircraft() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let zara = Person(firstName: "Zara", lastName: "Kowalski")
        let ola = Person(firstName: "Ola", lastName: "Nowak")
        let cessna = Aircraft(registration: "G-ONE", type: "C172")
        let piper = Aircraft(registration: "G-TWO", type: "P28A")
        [zara, ola].forEach { context.insert($0) }
        [cessna, piper].forEach { context.insert($0) }

        let older = makeFlight(
            context: context, departure: utc(2026, 1, 1, 10, 0),
            aircraft: piper, crew: [ola]
        )
        let newer = makeFlight(
            context: context, departure: utc(2026, 2, 1, 10, 0),
            aircraft: cessna, crew: [zara]
        )

        let suggestion = try #require(
            PeopleSuggestion.suggest(from: [newer, older], aircraft: piper, usualCrew: [])
        )
        #expect(suggestion.crew.map(\.displayName) == [ola.displayName])
    }

    @Test("falls back to the most recent flight when the aircraft is unknown")
    func fallsBackToMostRecent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let zara = Person(firstName: "Zara", lastName: "Kowalski")
        context.insert(zara)
        let flight = makeFlight(
            context: context, departure: utc(2026, 2, 1, 10, 0),
            aircraft: nil, crew: [zara]
        )

        let suggestion = try #require(
            PeopleSuggestion.suggest(from: [flight], aircraft: nil, usualCrew: [])
        )
        #expect(suggestion.crew.count == 1)
    }

    @Test("falls back to usual crew when no flight has people")
    func fallsBackToUsualCrew() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let zara = Person(firstName: "Zara", lastName: "Kowalski")
        zara.isUsualCrew = true
        context.insert(zara)

        let empty = makeFlight(
            context: context, departure: utc(2026, 2, 1, 10, 0),
            aircraft: nil, crew: []
        )

        let suggestion = try #require(
            PeopleSuggestion.suggest(from: [empty], aircraft: nil, usualCrew: [zara])
        )
        #expect(suggestion.crew.count == 1)
    }

    @Test("suggests nothing at all on a first run")
    func nothingToSuggest() {
        #expect(PeopleSuggestion.suggest(from: [], aircraft: nil, usualCrew: []) == nil)
    }
}
