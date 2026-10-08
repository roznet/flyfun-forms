import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

// Every assumption in `designs/stay-report.md` has at least one named test
// here, so changing an assumption means changing a test on purpose.

// MARK: - Helpers

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> StayDay {
    StayDay(year: year, month: month, day: day)
}

/// Airport timezones for the tests: France, Switzerland and Germany on
/// Paris time, the UK on London time, Greece on Athens time, anything else
/// unknown (UTC fallback).
private func testZone(_ icao: String) -> TimeZone? {
    switch icao.prefix(2) {
    case "LF", "LS", "ED": TimeZone(identifier: "Europe/Paris")
    case "EG": TimeZone(identifier: "Europe/London")
    case "LG": TimeZone(identifier: "Europe/Athens")
    default: nil
    }
}

/// A timed leg; the arrival defaults to an hour after departure.
private func leg(_ origin: String, _ destination: String, _ departure: Date, arrival: Date? = nil, id: UUID = UUID()) -> StayLeg {
    StayLeg(
        flightID: id, origin: origin, destination: destination,
        departure: .instant(departure), arrival: .instant(arrival ?? departure.addingTimeInterval(3600))
    )
}

private func report(
    _ legs: [StayLeg], asOf: Date,
    zone: (String) -> TimeZone? = testZone,
    deviceZone: TimeZone = .gmt
) -> StayReport {
    StayReport.compute(legs: legs, asOf: asOf, zone: zone, deviceZone: deviceZone)
}

// MARK: - Counting

@Suite("StayReport counting")
struct StayReportCountingTests {

    @Test("same-day out and back counts one Schengen day and one UK day")
    func sameDayOutAndBack() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 10, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 10, 15)),
        ], asOf: at(2026, 6, 10, 20))
        #expect(r.days(in: .schengen) == 1)
        #expect(r.days(in: .uk) == 1)
        #expect(r.gaps.isEmpty)
    }

    @Test("entry and exit days count as full days: out day 1, back day 3 is 3 days")
    func entryAndExitDaysCount() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 3, 15)),
        ], asOf: at(2026, 6, 3, 20))
        #expect(r.days(in: .schengen) == 3)
        #expect(r.days(in: .uk) == 2)
    }

    @Test("a hop inside Schengen with days between is continuous, no gap")
    func schengenInternalHop() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "LFPN", at(2026, 6, 5, 9)),
            leg("LFPN", "EGTF", at(2026, 6, 10, 9)),
        ], asOf: at(2026, 6, 10, 20))
        #expect(r.days(in: .schengen) == 10)
        #expect(r.gaps.isEmpty)
        #expect(r.unknownDays == 0)
    }

    @Test("staying put is assumed between flights in the same region, however far apart")
    func stayingPutAssumed() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 3, 1, 9)),
            leg("LFAC", "LSGS", at(2026, 5, 30, 9)),
            leg("LSGS", "EGTF", at(2026, 5, 31, 9)),
        ], asOf: at(2026, 5, 31, 20))
        // 1 March to 31 May inclusive.
        #expect(r.days(in: .schengen) == 92)
        #expect(r.gaps.isEmpty)
    }

    @Test("two trips add up and a shared day is not counted twice")
    func twoTripsSharedDay() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 3, 15)),
            leg("EGTF", "LSGS", at(2026, 6, 3, 17)),
            leg("LSGS", "EGTF", at(2026, 6, 5, 15)),
        ], asOf: at(2026, 6, 5, 20))
        #expect(r.days(in: .schengen) == 5)
        #expect(r.days(in: .uk) == 3)
    }

    @Test("a day can count for several regions")
    func dayInSeveralRegions() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 10, 8)),
            leg("LFAC", "EIDW", at(2026, 6, 10, 12)),
        ], asOf: at(2026, 6, 10, 20))
        #expect(r.days(in: .uk) == 1)
        #expect(r.days(in: .schengen) == 1)
        #expect(r.days(in: .euNonSchengen) == 1)
    }

    @Test("the same flight given twice is counted once")
    func duplicateLegCountedOnce() {
        let id = UUID()
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9), id: id),
            leg("EGTF", "LFAC", at(2026, 6, 1, 9), id: id),
        ], asOf: at(2026, 6, 1, 20))
        #expect(r.flightsUsed == [id])
        #expect(r.overlaps.isEmpty)
    }

    @Test("legs in any order give the same result")
    func orderIndependent() {
        let legs = [
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 3, 15)),
            leg("EGTF", "LSGS", at(2026, 6, 20, 9)),
        ]
        let forward = report(legs, asOf: at(2026, 6, 25))
        let backward = report(legs.reversed(), asOf: at(2026, 6, 25))
        #expect(forward.seenDays == backward.seenDays)
        #expect(forward.flightsUsed == backward.flightsUsed)
    }
}

// MARK: - Window

@Suite("StayReport window")
struct StayReportWindowTests {

    // 30 June 2026: the window runs 2 January to 30 June 2026.
    private let asOf = at(2026, 6, 30, 18)

    @Test("the window is 180 calendar days ending today, inclusive")
    func windowBounds() {
        let r = report([], asOf: asOf)
        #expect(r.today == day(2026, 6, 30))
        #expect(r.windowStart == day(2026, 1, 2))
        #expect(r.windowStart.distance(to: r.today) == StayReport.windowLength - 1)
    }

    @Test("a stay ending on today minus 180 is outside the window")
    func stayEndingJustBeforeWindow() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 12, 20, 9)),
            leg("LFAC", "EGTF", at(2026, 1, 1, 9)),
        ], asOf: asOf)
        #expect(r.days(in: .schengen) == 0)
    }

    @Test("a stay ending on today minus 179 counts one day")
    func stayEndingOnWindowStart() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 12, 20, 9)),
            leg("LFAC", "EGTF", at(2026, 1, 2, 9)),
        ], asOf: asOf)
        #expect(r.days(in: .schengen) == 1)
    }

    @Test("a stay straddling the window start counts only the days inside")
    func straddlingWindowStart() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 12, 25, 9)),
            leg("LFAC", "EGTF", at(2026, 1, 10, 9)),
        ], asOf: asOf)
        // 2 to 10 January.
        #expect(r.days(in: .schengen) == 9)
    }

    @Test("a stay that began before the window takes its state from the earlier flight")
    func stateFromBeforeWindow() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 12, 1, 9)),
        ], asOf: asOf)
        #expect(r.days(in: .schengen) == 180)
        #expect(r.days(in: .uk) == 0)
        #expect(r.openEnded == StayReport.OpenEnded(airport: "LFAC", region: .schengen, since: day(2025, 12, 1)))
    }

    @Test("a leap day inside the window still makes 180 calendar days")
    func leapDay() {
        let r = report([
            leg("EGTF", "LFAC", at(2027, 12, 1, 9)),
        ], asOf: at(2028, 6, 30, 18))
        // 2028 is a leap year: 29 February pulls the start a day later than in 2026.
        #expect(r.windowStart == day(2028, 1, 3))
        #expect(r.days(in: .schengen) == 180)
    }

    @Test("a DST change inside a stay counts calendar days, not 24-hour steps")
    func dstChange() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        // European clocks go forward on 29 March 2026.
        let r = report([
            leg("EGTF", "LFAC", at(2026, 3, 27, 10)),
            leg("LFAC", "EGTF", at(2026, 3, 31, 10)),
        ], asOf: at(2026, 3, 31, 20), deviceZone: paris)
        #expect(r.days(in: .schengen) == 5)
    }

    @Test("today is read in the device timezone")
    func todayInDeviceZone() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        // 22:30Z on 30 June is already 1 July in Paris.
        let r = report([], asOf: at(2026, 6, 30, 22, 30), deviceZone: paris)
        #expect(r.today == day(2026, 7, 1))
    }

    @Test("flights in the window: those arriving in it plus the one before that sets the start")
    func flightsInWindowCount() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2025, 9, 1, 9)),
            leg("EGTF", "LFAC", at(2026, 3, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 3, 5, 9)),
        ], asOf: asOf)
        #expect(r.flightsUsed.count == 4)
        #expect(r.flightsInWindow == 3)
    }

    @Test("only old flights: the last one still shapes the window")
    func flightsInWindowOnlyOld() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2025, 9, 1, 9)),
        ], asOf: asOf)
        #expect(r.flightsInWindow == 1)
        #expect(report([], asOf: asOf).flightsInWindow == 0)
    }
}

// MARK: - Time

@Suite("StayReport time")
struct StayReportTimeTests {

    @Test("days are local at each airport: departure 23:30 local, arrival 00:45 local next day")
    func localDayAtEachAirport() {
        // 22:30Z is 23:30 in London (BST); 22:45Z is 00:45 in Paris (CEST).
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 9, 22, 30), arrival: at(2026, 6, 9, 22, 45)),
        ], asOf: at(2026, 6, 10, 12))
        #expect(r.days(in: .uk) == 1)
        #expect(r.days(in: .schengen) == 1)
        #expect(r.openEnded == nil)
    }

    @Test("an arrival at 23:30Z in Greece in summer is the next local day")
    func greekArrivalNextDay() {
        let r = report([
            leg("EGTF", "LGAV", at(2026, 6, 9, 20), arrival: at(2026, 6, 9, 23, 30)),
        ], asOf: at(2026, 6, 10, 12))
        // Read in UTC this would be 9 June plus an open-ended 10 June.
        #expect(r.days(in: .schengen) == 1)
        #expect(r.openEnded == nil)
    }

    @Test("an unknown timezone falls back to UTC")
    func unknownZoneIsUTC() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 9, 22, 30), arrival: at(2026, 6, 9, 23, 30)),
        ], asOf: at(2026, 6, 10, 12), zone: { _ in nil })
        // In Paris time the arrival would be 10 June.
        #expect(r.openEnded?.since == day(2026, 6, 9))
        #expect(r.days(in: .schengen) == 2)
    }

    @Test("a flight with no time uses its stored day")
    func flightWithNoTime() {
        let r = report([
            StayLeg(flightID: UUID(), origin: "EGTF", destination: "LFAC",
                    departure: .day(day(2026, 6, 1)), arrival: .day(day(2026, 6, 1))),
            StayLeg(flightID: UUID(), origin: "LFAC", destination: "EGTF",
                    departure: .day(day(2026, 6, 3)), arrival: .day(day(2026, 6, 3))),
        ], asOf: at(2026, 6, 3, 20))
        #expect(r.days(in: .schengen) == 3)
        #expect(r.days(in: .uk) == 2)
    }
}

// MARK: - Gaps and edges

@Suite("StayReport gaps")
struct StayReportGapTests {

    @Test("a region change between flights is a gap, with unknown days and a Schengen range")
    func gapWithUnknownDays() {
        let out = UUID(), next = UUID()
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9), id: out),
            // Next seen leaving the UK: the way back was not recorded.
            leg("EGTF", "LFAC", at(2026, 6, 10, 9), id: next),
        ], asOf: at(2026, 6, 12, 20))
        #expect(r.gaps.count == 1)
        let gap = r.gaps[0]
        #expect(gap.previousFlightID == out)
        #expect(gap.nextFlightID == next)
        #expect(gap.arrivedAt == "LFAC")
        #expect(gap.departsFrom == "EGTF")
        #expect(gap.fromRegion == .schengen)
        #expect(gap.toRegion == .uk)
        #expect(gap.unknownDays == day(2026, 6, 2)...day(2026, 6, 9))
        #expect(gap.unknownDayCount == 8)
        #expect(r.unknownDays == 8)
        // Seen in Schengen 1 June and 10 to 12 June; up to all 12 with the gap.
        #expect(r.days(in: .schengen) == 4)
        #expect(r.schengenUpperBound == 12)
        #expect(r.days(in: .uk) == 2)
    }

    @Test("a region change on adjacent days is still a gap, with no unknown days")
    func gapOnAdjacentDays() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 17)),
            leg("EGTF", "LFAC", at(2026, 6, 2, 8)),
        ], asOf: at(2026, 6, 2, 20))
        #expect(r.gaps.count == 1)
        #expect(r.gaps[0].unknownDays == nil)
        #expect(r.unknownDays == 0)
        #expect(r.schengenUpperBound == r.days(in: .schengen))
    }

    @Test("a gap before the window is not listed")
    func gapBeforeWindowNotListed() {
        let r = report([
            leg("EGTF", "LFAC", at(2025, 6, 1, 9)),
            leg("EGTF", "LFAC", at(2025, 7, 1, 9)),
            leg("LFAC", "EGTF", at(2025, 7, 2, 9)),
        ], asOf: at(2026, 6, 30))
        #expect(r.gaps.isEmpty)
        #expect(r.unknownDays == 0)
    }

    @Test("nothing is counted before the first flight")
    func nothingBeforeFirstFlight() {
        let r = report([
            leg("LFAC", "EGTF", at(2026, 6, 10, 9)),
        ], asOf: at(2026, 6, 30, 20))
        // Only the departure day is known in Schengen.
        #expect(r.days(in: .schengen) == 1)
        #expect(r.gaps.isEmpty)
    }

    @Test("after the last flight the person is assumed to stay, flagged open-ended")
    func openEndedAfterLastFlight() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 10, 9)),
        ], asOf: at(2026, 6, 30, 20))
        #expect(r.days(in: .schengen) == 21)
        #expect(r.openEnded == StayReport.OpenEnded(airport: "LFAC", region: .schengen, since: day(2026, 6, 10)))
    }

    @Test("a last flight arriving today is not open-ended")
    func notOpenEndedWhenArrivedToday() {
        let r = report([
            leg("LFAC", "EGTF", at(2026, 6, 30, 9)),
        ], asOf: at(2026, 6, 30, 20))
        #expect(r.openEnded == nil)
    }

    @Test("overlapping flights are walked in departure order and flagged")
    func overlappingFlights() {
        let first = UUID(), second = UUID()
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 10), arrival: at(2026, 6, 1, 12), id: first),
            leg("LFAC", "LFPN", at(2026, 6, 1, 11), id: second),
        ], asOf: at(2026, 6, 1, 20))
        #expect(r.overlaps == [StayReport.Overlap(firstFlightID: first, secondFlightID: second)])
        #expect(r.flightsUsed == [first, second])
    }

    @Test("a flight missing an origin or destination is ignored and listed")
    func missingAirportIgnored() {
        let noOrigin = UUID(), noDestination = UUID()
        let r = report([
            leg("", "LFAC", at(2026, 6, 1, 9), id: noOrigin),
            leg("LFAC", " ", at(2026, 6, 2, 9), id: noDestination),
        ], asOf: at(2026, 6, 3))
        #expect(r.flightsIgnored == [noOrigin, noDestination])
        #expect(r.flightsUsed.isEmpty)
        #expect(r.seenDays.isEmpty)
    }

    @Test("a flight that has not departed yet is excluded")
    func futureFlightExcluded() {
        let later = UUID()
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 30, 21), id: later),
        ], asOf: at(2026, 6, 30, 20))
        #expect(r.flightsFuture == [later])
        #expect(r.days(in: .schengen) == 30)
        #expect(r.openEnded?.region == .schengen)
    }

    @Test("a flight that has departed but not landed counts")
    func flightInProgressCounts() {
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 30, 19), arrival: at(2026, 6, 30, 21)),
        ], asOf: at(2026, 6, 30, 20))
        #expect(r.flightsUsed.count == 1)
        #expect(r.days(in: .uk) == 1)
        #expect(r.days(in: .schengen) == 1)
    }

    @Test("every flight in the app is assumed to have happened")
    func everyFlightCounts() {
        // Nothing marks a flight as cancelled: one left in the app counts.
        let r = report([
            leg("EGTF", "LFAC", at(2026, 6, 1, 9)),
            leg("LFAC", "EGTF", at(2026, 6, 1, 15)),
            leg("EGTF", "LFAC", at(2026, 6, 1, 16)),
        ], asOf: at(2026, 6, 2, 20))
        #expect(r.flightsUsed.count == 3)
        #expect(r.days(in: .schengen) == 2)
    }
}

// MARK: - Rule status

@Suite("StayReport rule status")
struct StayReportRuleStatusTests {

    @Test("a GBR document only is subject")
    func gbrOnly() {
        #expect(StayReport.ruleStatus(issuingCountries: ["GBR"]) == .subject)
    }

    @Test("a Liechtenstein (LIE) document is not subject")
    func liechtenstein() {
        #expect(StayReport.ruleStatus(issuingCountries: ["LIE"]) == .notSubject)
    }

    @Test("GBR and FRA documents are not subject")
    func gbrAndFra() {
        #expect(StayReport.ruleStatus(issuingCountries: ["GBR", "FRA"]) == .notSubject)
    }

    @Test("an expired or inactive FRA document still means not subject")
    @MainActor
    func expiredFraOnly() throws {
        let container = try ModelContainer(
            for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let person = Person(firstName: "Test", lastName: "Expired")
        container.mainContext.insert(person)
        let doc = TravelDocument(docNumber: "TEST-FRA-0001", issuingCountry: "FRA", expiryDate: at(2020, 1, 1))
        doc.isActive = false
        doc.person = person
        container.mainContext.insert(doc)
        #expect(StayReport.ruleStatus(issuingCountries: person.documentList.map(\.issuingCountry)) == .notSubject)
    }

    @Test("no documents, or none naming a country, is unknown")
    func noDocuments() {
        #expect(StayReport.ruleStatus(issuingCountries: []) == .unknown)
        #expect(StayReport.ruleStatus(issuingCountries: [nil, ""]) == .unknown)
    }
}

// MARK: - From a person's flights

@Suite("StayLeg from a person")
@MainActor
struct StayLegFromPersonTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func flight(_ origin: String, _ destination: String, _ departure: Date, in context: ModelContext) -> Flight {
        let flight = Flight()
        flight.originICAO = origin
        flight.destinationICAO = destination
        flight.departureDateTime = departure
        flight.arrivalDateTime = departure.addingTimeInterval(3600)
        context.insert(flight)
        return flight
    }

    @Test("a person on the same flight as crew and passenger is counted once")
    func crewAndPassengerOnSameFlight() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(firstName: "Test", lastName: "Both")
        context.insert(person)
        let f = flight("EGTF", "LFAC", at(2026, 6, 1, 9), in: context)
        f.crew = [person]
        f.passengers = [person]
        try context.save()

        let (legs, flights) = StayLeg.legs(for: person)
        #expect(legs.count == 1)
        #expect(flights.count == 1)
    }

    @Test("crew on one leg and passenger on the next: both are used")
    func crewThenPassenger() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(firstName: "Test", lastName: "Mixed")
        context.insert(person)
        let out = flight("EGTF", "LFAC", at(2026, 6, 1, 9), in: context)
        out.crew = [person]
        let back = flight("LFAC", "EGTF", at(2026, 6, 3, 15), in: context)
        back.passengers = [person]
        try context.save()

        let (legs, flights) = StayLeg.legs(for: person)
        #expect(legs.count == 2)
        let r = StayReport.compute(legs: legs, asOf: at(2026, 6, 3, 20), zone: testZone, deviceZone: .gmt)
        #expect(r.days(in: .schengen) == 3)
        #expect(Set(r.flightsUsed.compactMap { flights[$0] }.map(\.persistentModelID))
                == [out.persistentModelID, back.persistentModelID])
    }
}
