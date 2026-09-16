import Foundation
import SwiftData

/// A one-tap suggestion for the people step: who was on board last time.
///
/// The route step is four fields; the people step is the slow one, so an import
/// that only fills the route has left most of the typing in place. Every import
/// method that cannot carry people (clipboard, weather, autorouter) offers this
/// instead.
struct PeopleSuggestion {
    let crew: [Person]
    let passengers: [Person]
    /// What the suggestion is drawn from, shown on the chip.
    let label: String

    var isEmpty: Bool { crew.isEmpty && passengers.isEmpty }

    /// Suggest the people for a new flight, preferring the most specific
    /// evidence available.
    ///
    /// 1. the most recent flight in the same aircraft
    /// 2. the most recent flight with anyone on board
    /// 3. everyone flagged `isUsualCrew`
    ///
    /// The first two reuse what the app already records rather than adding a
    /// second notion of "who normally flies with me" alongside
    /// `Person.coTravelers(minimumFlights:)` in `PeoplePickerView`.
    static func suggest(
        from flights: [Flight],
        aircraft: Aircraft?,
        usualCrew: [Person]
    ) -> PeopleSuggestion? {
        let withPeople = flights
            .filter { !$0.crewList.isEmpty || !$0.passengerList.isEmpty }
            .sorted { $0.departureDateTime > $1.departureDateTime }

        if let aircraft,
           let match = withPeople.first(where: {
               $0.aircraft?.persistentModelID == aircraft.persistentModelID
           }) {
            return PeopleSuggestion(
                crew: match.crewList,
                passengers: match.passengerList,
                label: String(localized: "Same as \(match.displayName)")
            )
        }

        if let latest = withPeople.first {
            return PeopleSuggestion(
                crew: latest.crewList,
                passengers: latest.passengerList,
                label: String(localized: "Same as \(latest.displayName)")
            )
        }

        guard !usualCrew.isEmpty else { return nil }
        return PeopleSuggestion(
            crew: usualCrew,
            passengers: [],
            label: String(localized: "Usual crew")
        )
    }

    /// A short "Anne, Bob and 2 more" for the chip's second line.
    var summary: String {
        let names = (crew + passengers).map(\.displayName)
        switch names.count {
        case 0: return ""
        case 1, 2: return names.joined(separator: ", ")
        default:
            return String(localized: "\(names[0]), \(names[1]) and \(names.count - 2) more")
        }
    }
}
