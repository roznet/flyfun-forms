import SwiftUI

/// The banner at the top of the wide flight editor: what this flight *is*.
///
/// The route used to be a form row behind a small pencil, three sections deep
/// in a scroll view, which left the detail pane with nothing identifying it —
/// `navigationTitle` goes to the window title bar on macOS, and that belongs to
/// the flights list. Here the route is the largest thing on screen and the
/// whole of it is the control that changes it.
struct FlightDetailHeader: View {
    let flight: Flight
    var onEditRoute: () -> Void

    private var origin: String { flight.originICAO.isEmpty ? "????" : flight.originICAO }
    private var destination: String { flight.destinationICAO.isEmpty ? "????" : flight.destinationICAO }

    var body: some View {
        DetailHeader {
            Button(action: onEditRoute) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(origin)
                        .font(.system(.title, design: .monospaced).bold())
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(destination)
                        .font(.system(.title, design: .monospaced).bold())
                    Image(systemName: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change Route")
            .accessibilityLabel("Change Route")

            subtitle
        }
    }

    /// `Fri 20 Sep 2026 · 13:30 LSGS → 15:30 EGTF · 2h00 · N122DR`
    private var subtitle: some View {
        HStack(spacing: 6) {
            Text(Self.dayText(flight.departureDateTime, zone: zone(for: flight.originICAO)))
            separator
            Text(verbatim: "\(timeText(flight.departureDateTime, icao: flight.originICAO)) \(origin)")
            Image(systemName: "arrow.right").imageScale(.small)
            Text(verbatim: "\(timeText(flight.arrivalDateTime, icao: flight.destinationICAO)) \(destination)")
            if let duration = durationText {
                separator
                Text(verbatim: duration)
            }
            if let registration = flight.aircraft?.registration, !registration.isEmpty {
                separator
                Text(verbatim: registration)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(.tertiary)
    }

    // MARK: - Formatting

    /// Each end is shown in its own airport's local time, which is the same
    /// default the schedule fields below pick, so the two never disagree.
    private func zone(for icao: String) -> TimeZone {
        AirportTimezoneCache.shared.timezone(for: icao) ?? .gmt
    }

    private func timeText(_ date: Date, icao: String) -> String {
        Self.text(date, zone: zone(for: icao), template: "Hm")
    }

    private static func dayText(_ date: Date, zone: TimeZone) -> String {
        text(date, zone: zone, template: "EEEdMMMy")
    }

    private static func text(_ date: Date, zone: TimeZone, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Nil rather than "0h00" when the two ends have not been set apart yet.
    private var durationText: String? {
        let seconds = flight.arrivalDateTime.timeIntervalSince(flight.departureDateTime)
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }
}
