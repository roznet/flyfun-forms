import Foundation
import SwiftData

// MARK: - Calendar day

/// A calendar day with no timezone attached, counted as days since
/// 1970-01-01. Day arithmetic is plain integer arithmetic, so a DST change or
/// a leap day inside a stay cannot shift a count the way 86 400-second steps
/// would.
nonisolated struct StayDay: Hashable, Comparable, Strideable, Sendable, CustomStringConvertible {
    let ordinal: Int

    init(ordinal: Int) {
        self.ordinal = ordinal
    }

    init(year: Int, month: Int, day: Int) {
        let midnight = Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
        ordinal = Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The calendar day `instant` falls on in `zone`.
    init(_ instant: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ymd = calendar.dateComponents([.year, .month, .day], from: instant)
        self.init(year: ymd.year!, month: ymd.month!, day: ymd.day!)
    }

    /// Midnight at the start of this day in `zone`, for display.
    func date(in zone: TimeZone = .current) -> Date {
        let utcMidnight = Date(timeIntervalSince1970: Double(ordinal) * 86_400)
        let ymd = Self.utcCalendar.dateComponents([.year, .month, .day], from: utcMidnight)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: ymd) ?? utcMidnight
    }

    static func < (lhs: StayDay, rhs: StayDay) -> Bool { lhs.ordinal < rhs.ordinal }
    func advanced(by n: Int) -> StayDay { StayDay(ordinal: ordinal + n) }
    func distance(to other: StayDay) -> Int { other.ordinal - ordinal }

    var description: String {
        let ymd = Self.utcCalendar.dateComponents(
            [.year, .month, .day], from: Date(timeIntervalSince1970: Double(ordinal) * 86_400)
        )
        return String(format: "%04d-%02d-%02d", ymd.year!, ymd.month!, ymd.day!)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

// MARK: - Input

/// One flight as the stay report sees it. Independent of `Flight`, so tests
/// build legs directly; `legs(for:)` makes them from a person's flights.
nonisolated struct StayLeg: Sendable {
    /// When a leg leaves or arrives.
    enum Moment: Sendable {
        /// An absolute moment; its calendar day is read at the airport.
        case instant(Date)
        /// A flight stored with no time: only its day is known.
        case day(StayDay)
    }

    let flightID: UUID
    let origin: String
    let destination: String
    let departure: Moment
    let arrival: Moment
}

// MARK: - Report

/// Days per region on the flights this app knows about, over the last 180
/// days. It counts; it does not judge. See `designs/stay-report.md` for the
/// rules and the assumptions behind them, each of which has a named test in
/// `StayReportTests`.
nonisolated struct StayReport: Sendable {

    /// The window is this many calendar days ending today, inclusive.
    static let windowLength = 180

    /// A change of region between two flights that no flight in the app
    /// explains: the person got from one to the other some other way.
    struct Gap: Equatable, Sendable {
        let previousFlightID: UUID
        let nextFlightID: UUID
        /// Where the previous flight arrived.
        let arrivedAt: String
        /// Where the next flight departs from.
        let departsFrom: String
        let fromRegion: AirportRegion
        let toRegion: AirportRegion
        let arrivalDay: StayDay
        let departureDay: StayDay
        /// The days strictly between the two flight days, nil when they are
        /// the same or adjacent days.
        let unknownDays: ClosedRange<StayDay>?

        var unknownDayCount: Int { unknownDays.map { $0.count } ?? 0 }
    }

    /// Two flights where the second departs before the first has arrived.
    struct Overlap: Equatable, Sendable {
        let firstFlightID: UUID
        let secondFlightID: UUID
    }

    /// The days after the last flight, assumed spent where it arrived.
    struct OpenEnded: Equatable, Sendable {
        let airport: String
        let region: AirportRegion
        let since: StayDay
    }

    /// Whether the person looks subject to the Schengen short-stay rule.
    enum RuleStatus: Equatable, Sendable {
        case subject
        case notSubject
        case unknown
    }

    let windowStart: StayDay
    let today: StayDay
    /// Distinct days seen in each region, inside the window.
    let seenDays: [AirportRegion: Int]
    /// Distinct days inside the window that fall in a gap.
    let unknownDays: Int
    /// Schengen days if every unknown day was spent in Schengen.
    let schengenUpperBound: Int
    /// Gaps whose next flight departs inside the window.
    let gaps: [Gap]
    let openEnded: OpenEnded?
    /// Flights walked, oldest first. The whole history, not just the window:
    /// the state on the window's first day comes from earlier flights.
    let flightsUsed: [UUID]
    /// Flights missing an origin or destination.
    let flightsIgnored: [UUID]
    /// Flights that have not departed yet.
    let flightsFuture: [UUID]
    let overlaps: [Overlap]

    func days(in region: AirportRegion) -> Int { seenDays[region] ?? 0 }

    // MARK: Compute

    /// - Parameters:
    ///   - legs: the person's flights, any order; duplicates by `flightID` are
    ///     counted once.
    ///   - asOf: now. Its day in `deviceZone` is "today", the window's last day.
    ///   - region: the region of an airport.
    ///   - zone: an airport's timezone, nil when not known yet (UTC is used).
    ///   - deviceZone: the zone "today" is read in.
    static func compute(
        legs: [StayLeg],
        asOf: Date,
        region: (String) -> AirportRegion = AirportRegion.region(for:),
        zone: (String) -> TimeZone?,
        deviceZone: TimeZone = .current
    ) -> StayReport {
        let today = StayDay(asOf, in: deviceZone)
        let windowStart = today.advanced(by: -(windowLength - 1))
        let window = windowStart...today

        struct Resolved {
            let leg: StayLeg
            let departureSort: Date
            let arrivalSort: Date
            let departureDay: StayDay
            let arrivalDay: StayDay
            let from: AirportRegion
            let to: AirportRegion
        }

        func resolve(_ moment: StayLeg.Moment, zone: TimeZone?) -> (sort: Date, day: StayDay) {
            switch moment {
            case .instant(let date):
                return (date, StayDay(date, in: zone ?? .gmt))
            case .day(let day):
                return (day.date(in: deviceZone), day)
            }
        }

        // 1. Collect: dedupe, drop legs without airports, drop future legs.
        var seenIDs: Set<UUID> = []
        var ignored: [UUID] = []
        var future: [UUID] = []
        var resolved: [Resolved] = []
        for leg in legs {
            guard seenIDs.insert(leg.flightID).inserted else { continue }
            let origin = leg.origin.trimmingCharacters(in: .whitespaces)
            let destination = leg.destination.trimmingCharacters(in: .whitespaces)
            guard !origin.isEmpty, !destination.isEmpty else {
                ignored.append(leg.flightID)
                continue
            }
            let departure = resolve(leg.departure, zone: zone(origin))
            let arrival = resolve(leg.arrival, zone: zone(destination))
            guard departure.sort <= asOf else {
                future.append(leg.flightID)
                continue
            }
            resolved.append(Resolved(
                leg: leg,
                departureSort: departure.sort,
                arrivalSort: arrival.sort,
                departureDay: departure.day,
                arrivalDay: arrival.day,
                from: region(origin),
                to: region(destination)
            ))
        }

        // 2. Sort by departure. Ties are broken so the result never depends
        // on the order the flights came in.
        resolved.sort {
            if $0.departureSort != $1.departureSort { return $0.departureSort < $1.departureSort }
            if $0.arrivalSort != $1.arrivalSort { return $0.arrivalSort < $1.arrivalSort }
            return $0.leg.flightID.uuidString < $1.leg.flightID.uuidString
        }

        // 3. Walk. Only days inside the window are recorded.
        var seen: [AirportRegion: Set<StayDay>] = [:]
        var unknown: Set<StayDay> = []
        var gaps: [Gap] = []
        var overlaps: [Overlap] = []

        func mark(_ days: ClosedRange<StayDay>, in region: AirportRegion) {
            guard days.overlaps(window) else { return }
            seen[region, default: []].formUnion(days.clamped(to: window))
        }

        var previous: Resolved?
        for leg in resolved {
            if let previous {
                if leg.departureSort < previous.arrivalSort {
                    overlaps.append(Overlap(
                        firstFlightID: previous.leg.flightID, secondFlightID: leg.leg.flightID
                    ))
                }
                if previous.to == leg.from {
                    // Stayed put between the two flights.
                    if previous.arrivalDay <= leg.departureDay {
                        mark(previous.arrivalDay...leg.departureDay, in: leg.from)
                    }
                } else {
                    // Changed region by some means the app did not see.
                    let first = previous.arrivalDay.advanced(by: 1)
                    let last = leg.departureDay.advanced(by: -1)
                    let between: ClosedRange<StayDay>? = first <= last ? first...last : nil
                    if let between, between.overlaps(window) {
                        unknown.formUnion(between.clamped(to: window))
                    }
                    if leg.departureDay >= windowStart {
                        gaps.append(Gap(
                            previousFlightID: previous.leg.flightID,
                            nextFlightID: leg.leg.flightID,
                            arrivedAt: previous.leg.destination,
                            departsFrom: leg.leg.origin,
                            fromRegion: previous.to,
                            toRegion: leg.from,
                            arrivalDay: previous.arrivalDay,
                            departureDay: leg.departureDay,
                            unknownDays: between
                        ))
                    }
                }
            }
            mark(leg.departureDay...leg.departureDay, in: leg.from)
            mark(leg.arrivalDay...leg.arrivalDay, in: leg.to)
            previous = leg
        }

        // 4. Before the first flight nothing is known, so nothing was marked.
        // 5. After the last flight, assume the person stayed where it landed.
        var openEnded: OpenEnded?
        if let last = previous, last.arrivalDay < today {
            mark(last.arrivalDay...today, in: last.to)
            openEnded = OpenEnded(airport: last.leg.destination, region: last.to, since: last.arrivalDay)
        }

        let schengen = seen[.schengen] ?? []
        return StayReport(
            windowStart: windowStart,
            today: today,
            seenDays: seen.mapValues(\.count),
            unknownDays: unknown.count,
            schengenUpperBound: schengen.union(unknown).count,
            gaps: gaps,
            openEnded: openEnded,
            flightsUsed: resolved.map(\.leg.flightID),
            flightsIgnored: ignored,
            flightsFuture: future,
            overlaps: overlaps
        )
    }

    // MARK: Rule status

    /// Not subject when any document, active or not, was issued by an EU or
    /// Schengen country: an expired passport doesn't end a citizenship.
    /// Unknown when no document names an issuing country. Residence permits
    /// and long-stay visas are not known to the app, so this is a label, not
    /// a filter.
    static func ruleStatus(issuingCountries: [String?]) -> RuleStatus {
        let countries = issuingCountries
            .compactMap { $0?.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        if countries.contains(where: { AirportRegion.euOrSchengenCountries.contains($0) }) {
            return .notSubject
        }
        return countries.isEmpty ? .unknown : .subject
    }
}

// MARK: - From the model

extension StayLeg {
    /// A person's crew and passenger flights as legs, each flight once, with
    /// a lookup back to the flight for each leg's `flightID`.
    @MainActor
    static func legs(for person: Person) -> (legs: [StayLeg], flights: [UUID: Flight]) {
        var seen: Set<PersistentIdentifier> = []
        var legs: [StayLeg] = []
        var flights: [UUID: Flight] = [:]
        for flight in (person.crewFlights ?? []) + (person.passengerFlights ?? []) {
            guard seen.insert(flight.persistentModelID).inserted else { continue }
            // A flight from before stable identities has no uuid yet; any id
            // unique to this computation will do.
            let id = flight.uuid ?? UUID()
            flights[id] = flight
            legs.append(StayLeg(
                flightID: id,
                origin: flight.originICAO,
                destination: flight.destinationICAO,
                departure: flight.hasDepartureTime || flight.departureInstant != nil
                    ? .instant(flight.departureDateTime)
                    : .day(StayDay(flight.departureDate, in: .current)),
                arrival: flight.hasArrivalTime || flight.arrivalInstant != nil
                    ? .instant(flight.arrivalDateTime)
                    : .day(StayDay(flight.arrivalDate, in: .current))
            ))
        }
        return (legs, flights)
    }
}
