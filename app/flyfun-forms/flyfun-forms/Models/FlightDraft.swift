import Foundation
import RZFlight

/// The result of any flight import, in the shape `NewFlightFlow` consumes.
///
/// Every import method produces one of these and nothing else, so adding a
/// method never touches the form: `NewFlightFlow.apply(_:)` is the single
/// writer of form state.
///
/// This is deliberately *not* `FlightExchange`. That type is the cross-app wire
/// format and is PII-free by design (see rzflight
/// `designs/flight_exchange_design.md`), while importing a previous flight has
/// to carry crew, passengers and the responsible person. `FlightExchange` stays
/// on the wire; `FlightDraft` is what the app works in.
struct FlightDraft {

    /// Where the draft came from, for provenance and for the confirmation the
    /// pilot sees after an import lands.
    enum Provenance: Equatable {
        case clipboard
        case weather(flightID: String)
        case autorouter(routeID: String)
        case previousFlight(route: String, departure: Date)

        /// One line describing the import, shown once it has been applied.
        var summary: String {
            switch self {
            case .clipboard:
                return String(localized: "Imported from the clipboard")
            case .weather:
                return String(localized: "Imported from FlyFun Weather")
            case .autorouter:
                return String(localized: "Imported from Autorouter")
            case .previousFlight(let route, _):
                return String(localized: "Copied from \(route)")
            }
        }
    }

    // MARK: - Route axis

    /// The route. `RZFlight.Route` is the single source of route truth across
    /// the flyfun apps, so every method converts into it rather than into a
    /// forms-local shape.
    var route: Route

    var registration: String?
    var aircraftType: String?

    // MARK: - Local axis (never crosses an app boundary)

    var crew: [Person] = []
    var passengers: [Person] = []
    var responsiblePerson: Person?
    var nature: String?
    var contact: String?
    var observations: String?

    var provenance: Provenance

    /// Whether the draft brought people with it. Only a previous-flight import
    /// does; the others leave the people step to the suggestion chip.
    var hasPeople: Bool { !crew.isEmpty || !passengers.isEmpty }
}

// MARK: - From a cross-app exchange payload

extension FlightDraft {
    /// Map a `FlightExchange` (weather, or an Autorouter row already parsed
    /// server-side) onto a draft. Only the origin/destination/time/aircraft
    /// subset forms cares about is consumed downstream; the full `Route` is
    /// kept so a later feature can show what was imported.
    init(_ exchange: FlightExchange, provenance: Provenance) {
        self.route = exchange.route
        self.registration = exchange.aircraft?.registration
        self.aircraftType = exchange.aircraft?.type ?? exchange.route.aircraftType
        self.provenance = provenance
    }
}

// MARK: - From a parsed ICAO flight plan

extension FlightDraft {
    /// Map a parsed ICAO flight plan onto a draft.
    ///
    /// `ICAOFlightPlanParser` composes field 13 and `DOF/` into a UTC instant
    /// and derives the arrival from `EET/`, so the plan's own `Route` already
    /// carries the schedule and no time arithmetic happens here. Forms used to
    /// add two "HH:mm" strings by hand, which wrapped at 24h and left the
    /// arrival a day behind on any overnight leg.
    init(_ plan: ICAOFlightPlan, provenance: Provenance = .clipboard) {
        self.route = plan.route
        self.registration = plan.aircraftRegistration
        self.aircraftType = plan.aircraftType
        self.provenance = provenance
    }

    /// The day of flight a plan carried in `DOF/` when field 13 gave no usable
    /// time, so the caller can still apply the date and leave the pilot only
    /// the time to correct.
    static func fallbackDayOfFlight(_ plan: ICAOFlightPlan) -> Date? {
        plan.route.departureTime == nil ? plan.dateOfFlight : nil
    }
}

// MARK: - From a previous flight

extension FlightDraft {
    /// Copy a previous flight forward: same route, aircraft, people and
    /// settings, rescheduled to its next occurrence from `now`.
    ///
    /// The schedule rule lives in `Flight.nextOccurrence(...)` so it can be
    /// unit-tested without a model context.
    init(repeating flight: Flight, now: Date = Date(), zone: TimeZone? = nil) {
        let schedule = Flight.nextOccurrence(
            departure: flight.departureDateTime,
            arrival: flight.arrivalDateTime,
            now: now,
            zone: zone
        )

        self.route = Route(
            departure: flight.originICAO,
            destination: flight.destinationICAO,
            aircraftType: flight.aircraft?.type,
            departureTime: schedule.departure,
            arrivalTime: schedule.arrival
        )
        self.registration = flight.aircraft?.registration
        self.aircraftType = flight.aircraft?.type
        self.crew = flight.crewList
        self.passengers = flight.passengerList
        self.responsiblePerson = flight.responsiblePerson
        self.nature = flight.nature
        self.contact = flight.contact
        self.observations = flight.observations
        self.provenance = .previousFlight(
            route: flight.displayName, departure: flight.departureDateTime
        )
    }
}
