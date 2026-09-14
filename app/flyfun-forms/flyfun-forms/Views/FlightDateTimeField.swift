import FlyFunCommon
import SwiftUI

/// Date, time and timezone entry for one end of a flight.
///
/// Binds to the absolute instant, and keeps the display timezone as view state.
/// Everything shown is derived from those two on each render through
/// ``ZonedWallClock``, so there is no second copy of the time to keep in sync,
/// and three things follow that the text field this replaces got wrong:
///
/// - switching the timezone re-displays the same moment rather than
///   reinterpreting the digits as a different one;
/// - an edit that crosses midnight moves the day, instead of wrapping the
///   clock inside a date the widget could not reach;
/// - DST resolves against the flight's own date rather than today's, so a
///   winter flight planned in summer keeps the right hour.
@MainActor
struct FlightDateTimeField: View {

    /// Row label prefix, e.g. "Departure".
    let label: String

    /// The absolute moment being edited.
    @Binding var instant: Date

    /// The airport whose local time this field defaults to showing: the origin
    /// for a departure, the destination for an arrival.
    var primaryICAO: String

    /// Airports whose timezones are offered, in route order.
    var zoneICAOs: [String]

    /// Minutes the picker steps by. Five keeps the menu short enough to scan
    /// while still covering the times a slot or an ETA is actually filed at.
    var minuteStep: Int = 5

    @State private var timeZoneId = ZonedWallClock.utcIdentifier

    private var clock: ZonedWallClock {
        ZonedWallClock(instant: instant, timeZoneId: timeZoneId)
    }

    /// Zones offered, in route order and de-duplicated.
    ///
    /// Read straight from the observable cache, so the list fills in and the
    /// view re-renders as airports resolve.
    private var availableZoneIds: [String] {
        let cache = AirportTimezoneCache.shared
        var ids: [String] = []
        for icao in zoneICAOs where !icao.isEmpty {
            if let id = cache.timeZoneId(for: icao), !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    private var preferredZoneId: String? {
        AirportTimezoneCache.shared.timeZoneId(for: primaryICAO)
    }

    private var zoneOptions: [ZonedTimeZoneOption] {
        ZonedWallClock.timeZoneOptions(for: availableZoneIds, at: instant)
    }

    var body: some View {
        Group {
            DatePicker(
                "\(label) Date",
                selection: Binding(
                    get: { clock.dateProxy },
                    set: { instant = clock.settingDateProxy($0).instant }
                ),
                displayedComponents: .date
            )

            LabeledContent("\(label) Time") {
                HStack(spacing: 2) {
                    Picker("Hour", selection: Binding(
                        get: { clock.hour },
                        set: { instant = clock.settingHour($0).instant }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("\(label)HourPicker")

                    Text(":").foregroundStyle(.secondary)

                    Picker("Minute", selection: Binding(
                        get: { clock.minuteOption(step: minuteStep) },
                        set: { instant = clock.settingMinute($0).instant }
                    )) {
                        ForEach(ZonedWallClock.minuteOptions(step: minuteStep), id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("\(label)MinutePicker")
                }
            }

            Picker("\(label) Zone", selection: $timeZoneId) {
                ForEach(zoneOptions) { option in
                    Text(option.label).tag(option.identifier)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("\(label)ZonePicker")
        }
        .task(id: zoneICAOs + [primaryICAO]) {
            let cache = AirportTimezoneCache.shared
            for icao in Set(zoneICAOs + [primaryICAO]) where !icao.isEmpty {
                cache.resolve(icao: icao)
            }
        }
        .onChange(of: availableZoneIds) { syncSelection() }
        .onChange(of: preferredZoneId) { syncSelection() }
    }

    /// Keep the selected zone present in the options, and adopt the relevant
    /// airport's zone while the selection is still the untouched UTC default.
    ///
    /// Done here rather than while building the options, because a picker whose
    /// selection is absent from its own list renders blank, and because
    /// adjusting state during a render is not allowed.
    private func syncSelection() {
        timeZoneId = ZonedWallClock.resolvedTimeZoneId(
            current: timeZoneId,
            available: availableZoneIds,
            preferred: preferredZoneId
        )
    }
}
