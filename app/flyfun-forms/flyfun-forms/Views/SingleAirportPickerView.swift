import SwiftUI
import SwiftData
import RZFlight

/// Single-airport picker for selecting one airport (e.g. aircraft base).
/// Reuses the same search logic and AirportRow as AirportPickerView.
struct SingleAirportPickerView: View {
    @Binding var selectedICAO: String
    var title: String = "Airport"
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    @State private var searchText = ""

    private let airportDB = AirportDatabase.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectedField
                searchField
                resultsList
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    // MARK: - Selected Airport Display

    private var selectedField: some View {
        VStack(spacing: 4) {
            Text(selectedICAO.isEmpty ? "----" : selectedICAO)
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(selectedICAO.isEmpty ? .secondary : .primary)
            if let airport = airportDB.airport(icao: selectedICAO) {
                Text(airport.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(airport.city), \(airport.country)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        TextField("Search airport name or ICAO...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.vertical, 8)
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            #endif
    }

    // MARK: - Results

    private var resultsList: some View {
        List {
            if !searchText.isEmpty {
                airportResultsSection
            }
            recentAirportsSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    @ViewBuilder
    private var airportResultsSection: some View {
        let results = airportDB.search(needle: searchText)
        if !results.isEmpty {
            Section("Airports") {
                ForEach(results, id: \.icao) { airport in
                    Button {
                        selectedICAO = airport.icao
                        searchText = ""
                    } label: {
                        AirportRow(airport: airport, selectedICAO: selectedICAO)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentAirportsSection: some View {
        let airports = recentAirports
        if !airports.isEmpty {
            Section("Recent Airports") {
                ForEach(airports, id: \.icao) { airport in
                    Button {
                        selectedICAO = airport.icao
                        searchText = ""
                    } label: {
                        AirportRow(airport: airport, selectedICAO: selectedICAO)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Unique airports from recent flights, filtered by search text.
    private var recentAirports: [Airport] {
        let needle = searchText.uppercased()
        var seen = Set<String>()
        var airports: [Airport] = []

        for flight in flights {
            for icao in [flight.originICAO, flight.destinationICAO] {
                guard !icao.isEmpty, !seen.contains(icao) else { continue }
                if needle.isEmpty || icao.contains(needle) {
                    seen.insert(icao)
                    if let airport = airportDB.airport(icao: icao) {
                        airports.append(airport)
                    }
                }
                if airports.count >= 10 { break }
            }
            if airports.count >= 10 { break }
        }
        return airports
    }
}
