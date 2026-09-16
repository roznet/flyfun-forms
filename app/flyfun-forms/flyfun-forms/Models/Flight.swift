import Foundation
import SwiftData

@Model
final class Flight {

    // MARK: - Schedule
    //
    // `departureInstant` / `arrivalInstant` are the representation this app is
    // moving to: one absolute moment, with no question of which timezone a
    // stored calendar day is read in.
    //
    // They are not authoritative yet. The `departureDate` + `departureTimeUTC`
    // pair still is, and is still dual-written. CloudKit syncs this store
    // between devices that may be on different app versions, and a build
    // without the instants writes only the pair, so a release that trusted the
    // instants would silently ignore edits made on an older device. The
    // instants are populated now (see `backfillScheduleInstants` in
    // flyfun_formsApp) so a later release can flip the precedence, and the pair
    // is dropped in the release after that.
    //
    // `departureDate` carries the intended calendar day as **midnight in the
    // device's own timezone**. That is how every existing row was written, by a
    // device-timezone `DatePicker`, and how `FlightEditView` formats it for the
    // API. Reading it in any other zone shifts the day, which is exactly the
    // bug `departureDateTime` used to have: it read the day in UTC while the
    // API mapping read it locally, and the two disagreed for any flight stored
    // near midnight.
    var departureDate: Date = Date()
    var departureTimeUTC: String = ""
    var arrivalDate: Date = Date()
    var arrivalTimeUTC: String = ""
    var departureInstant: Date?
    var arrivalInstant: Date?

    var originICAO: String = ""
    var destinationICAO: String = ""
    var nature: String = "private"
    var observations: String?
    var contact: String?
    var reasonForVisit: String?
    var responsiblePerson: Person?

    // All relationships optional for CloudKit; inverses on the other side
    var aircraft: Aircraft?
    var crew: [Person]?
    var passengers: [Person]?

    var trip: Trip?
    var legOrder: Int = 0

    /// The absolute departure moment.
    ///
    /// Setting it writes the day and the UTC time-of-day *together*, so an edit
    /// that crosses midnight moves the day. The widget this replaces could only
    /// write the time field and wrapped it within the day instead, leaving the
    /// date silently wrong for any local time that fell on the other side of
    /// UTC midnight.
    var departureDateTime: Date {
        get {
            Self.scheduleInstant(
                instant: departureInstant, day: departureDate, timeUTC: departureTimeUTC
            )
        }
        set {
            departureInstant = newValue
            departureDate = Self.localDay(ofUTCDayIn: newValue)
            departureTimeUTC = Self.utcTimeOfDay(newValue)
        }
    }

    /// The absolute arrival moment. See ``departureDateTime``.
    var arrivalDateTime: Date {
        get {
            Self.scheduleInstant(
                instant: arrivalInstant, day: arrivalDate, timeUTC: arrivalTimeUTC
            )
        }
        set {
            arrivalInstant = newValue
            arrivalDate = Self.localDay(ofUTCDayIn: newValue)
            arrivalTimeUTC = Self.utcTimeOfDay(newValue)
        }
    }

    /// Whether a departure time has actually been entered, as opposed to the
    /// day defaulting to midnight.
    var hasDepartureTime: Bool { Self.parseTimeUTC(departureTimeUTC) != nil }

    /// Whether an arrival time has actually been entered.
    var hasArrivalTime: Bool { Self.parseTimeUTC(arrivalTimeUTC) != nil }

    // MARK: - Schedule conversion

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Resolve the absolute moment for one leg of the schedule.
    ///
    /// The legacy pair wins while it is still dual-written. It is a lossless
    /// encoding of the instant to minute precision, and it is the only thing a
    /// device on an older build updates, so trusting the instant over it would
    /// drop that device's edits. The instant is used only when the pair carries
    /// no usable time of day, which a backfilled instant may still have.
    static func scheduleInstant(instant: Date?, day: Date, timeUTC: String) -> Date {
        if let composed = composeSchedule(day: day, timeUTC: timeUTC) { return composed }
        return instant ?? day
    }

    /// Compose the stored pair into an absolute moment: the calendar day of
    /// `day` read in the device timezone, at `timeUTC` read as a UTC time of
    /// day. Returns nil when no time has been entered.
    static func composeSchedule(day: Date, timeUTC: String) -> Date? {
        guard let (hour, minute) = parseTimeUTC(timeUTC) else { return nil }
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var components = DateComponents()
        components.year = ymd.year
        components.month = ymd.month
        components.day = ymd.day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = .gmt
        return utcCalendar.date(from: components)
    }

    /// Midnight in the device timezone on the UTC calendar day of `instant`.
    ///
    /// This is the inverse of what ``composeSchedule(day:timeUTC:)`` reads, so
    /// the pair round-trips: writing an instant and composing it back returns
    /// the same moment. It also keeps the stored value in the convention every
    /// existing row and every older build already uses.
    static func localDay(ofUTCDayIn instant: Date) -> Date {
        let ymd = utcCalendar.dateComponents([.year, .month, .day], from: instant)
        var components = DateComponents()
        components.year = ymd.year
        components.month = ymd.month
        components.day = ymd.day
        return Calendar.current.date(from: components) ?? instant
    }

    /// A default schedule moment for a new flight: the next whole hour, UTC.
    ///
    /// A picker always shows some time, unlike the free-text field this
    /// replaces which could be left blank. Rounding up to the hour makes the
    /// default read as a default, rather than as a precise-looking "now".
    static func defaultScheduleInstant(from now: Date = Date()) -> Date {
        let calendar = utcCalendar
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        guard let hourStart = calendar.date(from: components) else { return now }
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
    }

    /// `instant` moved onto the UTC calendar day of `reference`, keeping its
    /// own UTC time of day.
    static func alignUTCDay(of instant: Date, to reference: Date) -> Date {
        let day = utcCalendar.dateComponents([.year, .month, .day], from: reference)
        var components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: instant
        )
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.second = 0
        return utcCalendar.date(from: components) ?? instant
    }

    /// The next occurrence of a flight's schedule, for repeating a previous
    /// flight.
    ///
    /// The original **time of day** is kept, read in `zone` when the caller
    /// knows the origin airport's timezone and in UTC otherwise: a pilot thinks
    /// "the 09:00 out of EGTF", not "the 08:00Z". If that time of day is still
    /// ahead of `now` it lands today, otherwise tomorrow.
    ///
    /// The arrival is carried by the original leg's **duration**, not realigned
    /// onto the departure day, so an overnight leg keeps its length instead of
    /// being flattened back into the same day.
    static func nextOccurrence(
        departure: Date,
        arrival: Date,
        now: Date = Date(),
        zone: TimeZone? = nil
    ) -> (departure: Date, arrival: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? .gmt

        let timeOfDay = calendar.dateComponents([.hour, .minute], from: departure)
        var candidate = calendar.dateComponents([.year, .month, .day], from: now)
        candidate.hour = timeOfDay.hour
        candidate.minute = timeOfDay.minute
        candidate.second = 0

        guard var next = calendar.date(from: candidate) else {
            return (departure, arrival)
        }
        if next <= now {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }

        // A stored arrival that predates its departure means no arrival time
        // was ever entered; a negative duration would put the new arrival
        // before the new departure, so clamp it to zero.
        let duration = max(0, arrival.timeIntervalSince(departure))
        return (next, next.addingTimeInterval(duration))
    }

    /// The UTC time of day of `instant` as "HH:mm".
    static func utcTimeOfDay(_ instant: Date) -> String {
        let components = utcCalendar.dateComponents([.hour, .minute], from: instant)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// Parse an "HH:mm" UTC time of day, rejecting out-of-range values.
    ///
    /// Range-checked deliberately: the widget this replaces wrote whatever the
    /// pilot had typed so far straight into the model on every keystroke, so
    /// stored values like "1" or "25:70" exist in the wild and must read as
    /// "no time entered" rather than compose into a nonsense moment.
    static func parseTimeUTC(_ time: String) -> (hour: Int, minute: Int)? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    var displayName: String {
        let origin = originICAO.isEmpty ? "????" : originICAO
        let dest = destinationICAO.isEmpty ? "????" : destinationICAO
        return "\(origin) > \(dest)"
    }

    // Safe accessors for nil arrays
    var crewList: [Person] { crew ?? [] }
    var passengerList: [Person] { passengers ?? [] }

    init() {}

    /// Create a new flight copying shared properties (aircraft, crew, passengers, nature, etc.)
    func copyCommon(to newFlight: Flight) {
        newFlight.aircraft = aircraft
        newFlight.crew = crew
        newFlight.passengers = passengers
        newFlight.nature = nature
        newFlight.contact = contact
        newFlight.reasonForVisit = reasonForVisit
        newFlight.responsiblePerson = responsiblePerson
    }
}
