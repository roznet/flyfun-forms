import SwiftUI
import SwiftData

/// Adds the leg a Travel Days gap is missing, from the gap itself: the route
/// from where the person landed to where they next take off, the person on
/// board, and a day inside the gap. Usually an airline flight, a train or a
/// ferry, so no aircraft. See `designs/stay-report.md`.
struct MissingFlightSheet: View {
    let person: Person
    let gap: StayReport.Gap

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var originICAO: String
    @State private var destinationICAO: String
    @State private var day: Date
    @State private var setTime = false
    @State private var departureInstant = Date()
    @State private var showAirportPicker = false

    private static let dayFormat = Date.FormatStyle.dateTime.day().month().year()

    init(person: Person, gap: StayReport.Gap) {
        self.person = person
        self.gap = gap
        _originICAO = State(initialValue: gap.arrivedAt)
        _destinationICAO = State(initialValue: gap.departsFrom)
        let zone = AirportTimezoneCache.shared.timezone(for: gap.arrivedAt)
        _day = State(initialValue: (gap.dayAfterArriving(originZone: zone) ?? gap.arrivalDay).date())
    }

    /// Unresolved means UTC, as the report reads it; observed, so the days
    /// follow when the zone lands.
    private var originZone: TimeZone? {
        AirportTimezoneCache.shared.timezone(for: originICAO)
    }

    private var days: ClosedRange<StayDay>? { gap.missingLegDays(originZone: originZone) }

    private var selectedDay: StayDay { StayDay(day, in: .current) }

    /// The departure the flight is saved with: the time entered, or one the
    /// report places between the gap's two flights. nil when it would not
    /// sort between them, so the gap would stay open.
    private var departure: Date? {
        if setTime {
            return gap.fits(departureInstant) ? departureInstant : nil
        }
        return gap.missingLegDeparture(on: selectedDay, originZone: originZone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showAirportPicker = true
                    } label: {
                        LabeledContent("Route") {
                            Text(verbatim: "\(icaoOrDashes(originICAO)) → \(icaoOrDashes(destinationICAO))")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .accessibilityIdentifier("missingFlightRouteButton")
                    LabeledContent("Person") {
                        Text(verbatim: person.displayName)
                    }
                } footer: {
                    Text("Arrived \(gap.arrivedAt) \(gap.arrivalDay.date(), format: Self.dayFormat), next departs \(gap.departsFrom) \(gap.departureDay.date(), format: Self.dayFormat), no flight between")
                }

                Section {
                    if days == nil {
                        Text("These two flights leave no time for a flight between them. Check their dates and times.")
                            .foregroundStyle(.secondary)
                    } else if setTime {
                        FlightDateTimeField(
                            end: .departure,
                            instant: $departureInstant,
                            primaryICAO: originICAO,
                            zoneICAOs: [originICAO, destinationICAO]
                        )
                    } else if let days {
                        DatePicker("Day", selection: $day, in: days.lowerBound.date()...days.upperBound.date(), displayedComponents: .date)
                            .accessibilityIdentifier("missingFlightDayPicker")
                        if let after = gap.dayAfterArriving(originZone: originZone),
                           let before = gap.dayBeforeNextFlight(originZone: originZone),
                           after != before {
                            HStack {
                                quickPick("Day after arriving", after)
                                Spacer()
                                quickPick("Day before next flight", before)
                            }
                        }
                    }
                    if days != nil {
                        Toggle("Set a time", isOn: $setTime.animation())
                            .onChange(of: setTime) { _, on in
                                if on, let placed = gap.missingLegDeparture(on: selectedDay, originZone: originZone) {
                                    departureInstant = placed
                                }
                            }
                    }
                } header: {
                    Text("When")
                } footer: {
                    if days != nil {
                        if departure == nil {
                            Text("This isn't between the two flights, so it wouldn't fill the gap.")
                                .foregroundStyle(.red)
                        } else if !setTime {
                            Text("Without a time, the flight is placed between the two flights on that day.")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle("Missing Flight")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addFlight() }
                        .disabled(originICAO.isEmpty || destinationICAO.isEmpty || departure == nil)
                        .accessibilityIdentifier("missingFlightAddButton")
                }
            }
            .sheet(isPresented: $showAirportPicker) {
                AirportPickerView(originICAO: $originICAO, destinationICAO: $destinationICAO)
            }
            .task(id: originICAO) {
                AirportTimezoneCache.shared.resolve(icao: originICAO)
            }
            .onChange(of: days) { _, days in
                // The origin's zone resolved or the origin changed: keep the
                // day inside the days that now fit.
                guard let days else { return }
                day = min(max(selectedDay, days.lowerBound), days.upperBound).date()
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func quickPick(_ title: LocalizedStringKey, _ target: StayDay) -> some View {
        Button(title) { day = target.date() }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(selectedDay == target)
    }

    private func icaoOrDashes(_ icao: String) -> String {
        icao.isEmpty ? "----" : icao
    }

    private func addFlight() {
        guard let instant = departure else { return }
        let flight = Flight()
        flight.originICAO = originICAO
        flight.destinationICAO = destinationICAO
        flight.departureDateTime = instant
        flight.arrivalDateTime = instant
        flight.passengers = [person]
        flight.observations = String(
            localized: "Added from Travel Days",
            comment: "Observation on a flight added to fill a gap in the travel days report"
        )
        modelContext.insert(flight)
        dismiss()
    }
}
