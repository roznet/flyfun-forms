import SwiftUI
import SwiftData
import RZFlight

/// Airport picker with dual origin/destination fields and autocomplete search.
/// Tap a route field to make it active, then search below to fill it.
struct AirportPickerView: View {
    @Binding var originICAO: String
    @Binding var destinationICAO: String
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    @State private var searchText = ""
    @State private var activeField: RouteField = .origin

    private let airportDB = AirportDatabase.shared

    enum RouteField {
        case origin, destination
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                routeFields
                searchField
                resultsList
            }
            .navigationTitle("Route")
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

    // MARK: - Route Fields

    private var routeFields: some View {
        HStack(spacing: 12) {
            routeFieldButton(label: "FROM", icao: originICAO, field: .origin)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            routeFieldButton(label: "TO", icao: destinationICAO, field: .destination)
        }
        .padding()
    }

    private func routeFieldButton(label: String, icao: String, field: RouteField) -> some View {
        Button {
            activeField = field
            searchText = ""
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(icao.isEmpty ? "----" : icao)
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(icao.isEmpty ? .secondary : .primary)
                if let airport = airportDB.airport(icao: icao) {
                    Text(airport.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(activeField == field ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(activeField == field ? Color.accentColor : .secondary.opacity(0.3), lineWidth: activeField == field ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchField: some View {
        TextField("Search airport name or ICAO...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.bottom, 8)
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
            recentRoutesSection
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
                        selectAirport(airport)
                    } label: {
                        AirportRow(airport: airport, selectedICAO: activeFieldICAO)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentRoutesSection: some View {
        let routes = recentRoutes
        if !routes.isEmpty {
            Section("Recent Routes") {
                ForEach(routes, id: \.id) { route in
                    Button {
                        originICAO = route.origin
                        destinationICAO = route.destination
                        searchText = ""
                    } label: {
                        HStack {
                            Text(route.origin)
                                .font(.system(.body, design: .monospaced).bold())
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(route.destination)
                                .font(.system(.body, design: .monospaced).bold())
                            Spacer()
                            Text(route.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var activeFieldICAO: String {
        activeField == .origin ? originICAO : destinationICAO
    }

    private func selectAirport(_ airport: Airport) {
        switch activeField {
        case .origin:
            originICAO = airport.icao
        case .destination:
            destinationICAO = airport.icao
        }
        searchText = ""
        // Advance to next empty field
        if activeField == .origin && destinationICAO.isEmpty {
            activeField = .destination
        }
    }

    private var recentRoutes: [RecentRoute] {
        let needle = searchText.uppercased()
        var seen = Set<String>()
        var routes: [RecentRoute] = []

        for flight in flights {
            let origin = flight.originICAO
            let dest = flight.destinationICAO
            guard !origin.isEmpty, !dest.isEmpty else { continue }

            let key = "\(origin)-\(dest)"
            guard !seen.contains(key) else { continue }

            if needle.isEmpty || origin.contains(needle) || dest.contains(needle) {
                seen.insert(key)
                routes.append(RecentRoute(origin: origin, destination: dest, date: flight.departureDate))
            }
            if routes.count >= 10 { break }
        }
        return routes
    }
}

private struct RecentRoute: Identifiable {
    let origin: String
    let destination: String
    let date: Date
    var id: String { "\(origin)-\(destination)" }
}

struct AirportRow: View {
    let airport: Airport
    var selectedICAO: String = ""

    var body: some View {
        HStack {
            Text(airport.icao)
                .font(.system(.body, design: .monospaced).bold())
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading) {
                Text(airport.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(airport.city), \(airport.country)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if airport.icao == selectedICAO {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}
