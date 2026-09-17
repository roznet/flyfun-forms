import SwiftData
import SwiftUI

/// Picker for copying the people from an earlier flight onto this one.
///
/// The suggestion chip answers "same crew as last time" in one tap, but it
/// chooses the flight itself. This is the same idea with the choice handed
/// back: the pilot who flies with different people on different trips picks
/// which trip, rather than correcting the guess person by person.
///
/// Purely local, like `PreviousFlightPickerView` — the flights and people are
/// already in SwiftData, so it works offline and signed out.
struct CrewSourcePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    /// Delivers the crew and passengers of the chosen flight. The sheet
    /// dismisses itself afterward.
    var onSelect: (_ crew: [Person], _ passengers: [Person]) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var candidates: [Flight] { PeopleSuggestion.crewSources(from: flights) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Copy Crew From"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if candidates.isEmpty {
            ContentUnavailableView(
                String(localized: "No flights with people yet"),
                systemImage: "person.2",
                description: Text("Once a flight has crew or passengers, you can copy them here.")
            )
        } else {
            List(candidates) { flight in
                Button {
                    onSelect(flight.crewList, flight.passengerList)
                    dismiss()
                } label: {
                    row(flight)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ flight: Flight) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.displayName)
                    .font(.system(.body, design: .monospaced))
                Text(people(on: flight))
                Text(subtitle(for: flight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "person.2.badge.plus")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Who is on board — the point of the row, so it is named in full rather
    /// than counted.
    private func people(on flight: Flight) -> String {
        (flight.crewList + flight.passengerList)
            .map(\.displayName)
            .joined(separator: ", ")
    }

    /// Date and aircraft, which tell two trips with the same people apart.
    private func subtitle(for flight: Flight) -> String {
        var parts: [String] = [Self.dateFormatter.string(from: flight.departureDateTime)]
        if let registration = flight.aircraft?.registration, !registration.isEmpty {
            parts.append(registration)
        }
        return parts.joined(separator: " · ")
    }
}
