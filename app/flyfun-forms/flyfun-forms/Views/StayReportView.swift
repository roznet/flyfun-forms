import SwiftUI
import SwiftData

/// Days per region over the last 180 days, on the flights this app knows
/// about. A thin view on `StayReport`: it counts and shows where the record
/// has holes, with no thresholds or warnings. See `designs/stay-report.md`.
struct StayReportView: View {
    let person: Person

    /// Observed, so the report recomputes as airport timezones resolve.
    private var timezones: AirportTimezoneCache { .shared }

    @Environment(\.modelContext) private var modelContext

    /// The gap whose missing flight is being added.
    @State private var fillingGap: StayReport.Gap?
    @State private var openedFlight: Flight?
    @State private var flightToDelete: Flight?

    private static let dayFormat = Date.FormatStyle.dateTime.day().month().year()

    var body: some View {
        let legs = StayLeg.legs(for: person)
        let report = makeReport(legs.legs)
        let status = StayReport.ruleStatus(issuingCountries: person.documentList.map(\.issuingCountry))

        Form {
            Section {
                ForEach(AirportRegion.allCases, id: \.self) { region in
                    regionRow(region, report: report, status: status)
                }
            } header: {
                Text("From \(report.windowStart.date(), format: Self.dayFormat) to \(report.today.date(), format: Self.dayFormat)")
            } footer: {
                Text("Based on \(report.flightsInWindow) flights in this app. Counts only flights recorded in this app; it is not a legal calculation.")
            }

            ForEach(Array(report.gaps.enumerated()), id: \.offset) { index, gap in
                Section {
                    gapRows(gap, flights: legs.flights)
                } header: {
                    if index == 0 { Text("Gaps") }
                } footer: {
                    if index == report.gaps.count - 1 {
                        Text("The region changes between these flights with no flight recorded in between. Add the missing flight, or remove a flight that didn't happen.")
                    }
                }
            }

            notesSection(report)
        }
        .platformFormStyle()
        .navigationTitle("Travel Days")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $fillingGap) { gap in
            MissingFlightSheet(person: person, gap: gap)
        }
        .navigationDestination(item: $openedFlight) { flight in
            FlightEditView(flight: flight)
                .id(flight.persistentModelID)
        }
        .confirmationDialog(
            "Delete \(flightToDelete?.displayName ?? "")?",
            isPresented: Binding(
                get: { flightToDelete != nil },
                set: { if !$0 { flightToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: flightToDelete
        ) { flight in
            Button("Delete Flight", role: .destructive) {
                modelContext.deleteRecordingTombstone(flight)
                flightToDelete = nil
            }
        } message: { _ in
            Text("The flight is deleted for everyone on it. If only this person wasn't on it, remove them from the flight instead.")
        }
        .task {
            for leg in legs.legs {
                timezones.resolve(icao: leg.origin)
                timezones.resolve(icao: leg.destination)
            }
        }
    }

    private func makeReport(_ legs: [StayLeg]) -> StayReport {
        // Read the zones here, on the main actor, and hand the calculator
        // plain values.
        var zones: [String: TimeZone] = [:]
        for leg in legs {
            for icao in [leg.origin, leg.destination] where zones[icao] == nil {
                zones[icao] = timezones.timezone(for: icao)
            }
        }
        return StayReport.compute(legs: legs, asOf: Date(), zone: { zones[$0] })
    }

    // MARK: - Rows

    @ViewBuilder
    private func regionRow(_ region: AirportRegion, report: StayReport, status: StayReport.RuleStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(region.title)
                Spacer()
                Text("\(report.days(in: region)) days")
                    .monospacedDigit()
            }
            if region == .schengen {
                if report.schengenUpperBound > report.days(in: .schengen) {
                    Text("Up to \(report.schengenUpperBound) days with gaps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func gapRows(_ gap: StayReport.Gap, flights: [UUID: Flight]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arrived \(gap.arrivedAt) \(gap.arrivalDay.date(), format: Self.dayFormat), next departs \(gap.departsFrom) \(gap.departureDay.date(), format: Self.dayFormat), no flight between")
            if gap.unknownDayCount > 0 {
                Text("Unknown days: \(gap.unknownDayCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Button {
            fillingGap = gap
        } label: {
            Label("Add Missing Flight", systemImage: "plus.circle")
        }
        .accessibilityIdentifier("addMissingFlightButton")
        if let flight = flights[gap.previousFlightID] {
            flightMenu(flight, label: "Previous flight")
        }
        if let flight = flights[gap.nextFlightID] {
            flightMenu(flight, label: "Next flight")
        }
    }

    /// A flight on either side of a gap, with what fixes a flight that
    /// shouldn't be there: open it, take this person off it, or delete it.
    private func flightMenu(_ flight: Flight, label: LocalizedStringKey) -> some View {
        Menu {
            Button {
                openedFlight = flight
            } label: {
                Label("Open Flight", systemImage: "airplane")
            }
            Button {
                remove(person, from: flight)
            } label: {
                Label("Remove \(person.displayName) from This Flight", systemImage: "person.badge.minus")
            }
            Button(role: .destructive) {
                flightToDelete = flight
            } label: {
                Label("Delete Flight", systemImage: "trash")
            }
        } label: {
            LabeledContent {
                Text(verbatim: flight.displayName)
            } label: {
                Text(label)
            }
            .contentShape(Rectangle())
        }
    }

    private func remove(_ person: Person, from flight: Flight) {
        let id = person.persistentModelID
        flight.crew?.removeAll { $0.persistentModelID == id }
        flight.passengers?.removeAll { $0.persistentModelID == id }
    }

    @ViewBuilder
    private func notesSection(_ report: StayReport) -> some View {
        let hasNotes = report.openEnded != nil || !report.overlaps.isEmpty
            || !report.flightsIgnored.isEmpty || !report.flightsFuture.isEmpty
        if hasNotes {
            Section("Notes") {
                if let open = report.openEnded {
                    Text("Assumed in \(open.airport) (\(open.region.title)) since \(open.since.date(), format: Self.dayFormat), the last recorded flight, and counted up to today.")
                }
                if !report.overlaps.isEmpty {
                    Text("Flights overlapping in time: \(report.overlaps.count). Check their times.")
                }
                if !report.flightsIgnored.isEmpty {
                    Text("Flights missing an airport, not counted: \(report.flightsIgnored.count)")
                }
                if !report.flightsFuture.isEmpty {
                    Text("Planned flights, not counted yet: \(report.flightsFuture.count)")
                }
            }
        }
    }
}

// MARK: - Display names

extension AirportRegion {
    var title: String {
        switch self {
        case .schengen: String(localized: "Schengen", comment: "Region in the travel days report")
        case .uk: String(localized: "UK", comment: "Region in the travel days report")
        case .euNonSchengen: String(localized: "EU outside Schengen", comment: "Region in the travel days report")
        case .other: String(localized: "Other")
        }
    }
}

extension StayReport.RuleStatus {
    var title: String {
        switch self {
        case .notSubject:
            String(localized: "Not subject to 90/180: holds an EU or Schengen document")
        case .subject:
            String(localized: "No EU or Schengen document: 90/180 may apply")
        case .unknown:
            String(localized: "No documents: can't tell whether 90/180 applies")
        }
    }
}
