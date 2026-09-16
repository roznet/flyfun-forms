import SwiftData
import SwiftUI

/// Picker for repeating an earlier flight. Purely local: the flights are
/// already in SwiftData, so this method works offline and signed out.
///
/// Routes are deduplicated so a weekly trip shows once, as its most recent
/// occurrence, rather than filling the list with the same pair of airports.
struct PreviousFlightPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    /// Delivers the chosen flight. The sheet dismisses itself afterward.
    var onSelect: (Flight) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Most recent first, one row per distinct route.
    private var candidates: [Flight] {
        var seen = Set<String>()
        return flights
            .sorted { $0.departureDateTime > $1.departureDateTime }
            .filter { flight in
                let key = "\(flight.originICAO)-\(flight.destinationICAO)"
                guard !flight.originICAO.isEmpty || !flight.destinationICAO.isEmpty else {
                    return false
                }
                return seen.insert(key).inserted
            }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Repeat a Flight"))
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
                String(localized: "No earlier flights"),
                systemImage: "airplane",
                description: Text("Flights you create appear here, ready to repeat.")
            )
        } else {
            List(candidates) { flight in
                Button {
                    onSelect(flight)
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
                Text(subtitle(for: flight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Date, aircraft and people count — what tells two flights on the same
    /// route apart.
    private func subtitle(for flight: Flight) -> String {
        var parts: [String] = [Self.dateFormatter.string(from: flight.departureDateTime)]
        if let registration = flight.aircraft?.registration, !registration.isEmpty {
            parts.append(registration)
        }
        let people = flight.crewList.count + flight.passengerList.count
        if people > 0 {
            parts.append(String(localized: "\(people) on board"))
        }
        return parts.joined(separator: " · ")
    }
}
