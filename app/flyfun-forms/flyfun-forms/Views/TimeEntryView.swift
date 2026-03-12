import SwiftUI

/// Reusable time entry widget that stores UTC but lets the user view/edit in a chosen timezone.
/// Shows an HStack with a time TextField and a timezone Picker.
/// Timezone options: Zulu + origin TZ + destination TZ (deduped). Default = relevant airport's local TZ.
struct TimeEntryView: View {
    /// The UTC time string binding (HH:mm format), stored in the model.
    @Binding var utcTimeString: String

    /// ICAO code of the relevant airport (used to pick default timezone).
    var airportICAO: String

    /// ICAO code of the origin airport (for timezone options).
    var originICAO: String

    /// ICAO code of the destination airport (for timezone options).
    var destinationICAO: String

    /// Placeholder text for the text field.
    var placeholder: String = "HH:mm"

    @State private var displayTime: String = ""
    @State private var selectedTimezoneId: String = "GMT"
    @State private var isUpdating = false

    private var tzCache: AirportTimezoneCache { .shared }

    private var selectedTimezone: TimeZone {
        availableTimezones.first(where: { $0.identifier == selectedTimezoneId }) ?? .gmt
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $displayTime)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .onChange(of: displayTime) {
                    guard !isUpdating else { return }
                    updateUTCFromDisplay()
                }

            Picker("", selection: $selectedTimezoneId) {
                ForEach(availableTimezones, id: \.identifier) { tz in
                    Text(tzLabel(tz)).tag(tz.identifier)
                }
            }
            .labelsHidden()
            .fixedSize()
            #if os(iOS)
            .pickerStyle(.menu)
            #endif
            .onChange(of: selectedTimezoneId) {
                guard !isUpdating else { return }
                updateDisplayFromUTC()
            }
        }
        .onAppear {
            initializeTimezone()
            updateDisplayFromUTC()
        }
        .onChange(of: utcTimeString) {
            guard !isUpdating else { return }
            updateDisplayFromUTC()
        }
        .onChange(of: airportICAO) {
            initializeTimezone()
            updateDisplayFromUTC()
        }
    }

    // MARK: - Available Timezones

    private var availableTimezones: [TimeZone] {
        var tzs: [TimeZone] = [.gmt]
        if let originTZ = tzCache.timezone(for: originICAO), originTZ.secondsFromGMT() != 0 {
            tzs.append(originTZ)
        }
        if let destTZ = tzCache.timezone(for: destinationICAO),
           destTZ.secondsFromGMT() != 0,
           !tzs.contains(where: { $0.identifier == destTZ.identifier }) {
            tzs.append(destTZ)
        }
        return tzs
    }

    private func tzLabel(_ tz: TimeZone) -> String {
        if tz == .gmt || tz.secondsFromGMT() == 0 { return "UTC" }

        // Try to get city name from cache
        let icaos = [originICAO, destinationICAO]
        for icao in icaos {
            if let entry = tzCache.entry(for: icao), entry.timezone.identifier == tz.identifier {
                let offsetHours = tz.secondsFromGMT() / 3600
                let sign = offsetHours >= 0 ? "+" : ""
                return "\(entry.city) (GMT\(sign)\(offsetHours))"
            }
        }

        let abbr = tz.abbreviation() ?? tz.identifier
        return abbr
    }

    // MARK: - Timezone Initialization

    private func initializeTimezone() {
        if let localTZ = tzCache.timezone(for: airportICAO) {
            selectedTimezoneId = localTZ.identifier
        } else {
            selectedTimezoneId = TimeZone.gmt.identifier
        }
    }

    // MARK: - Conversion

    private func updateUTCFromDisplay() {
        isUpdating = true
        defer { isUpdating = false }

        guard let (hour, minute) = parseTime(displayTime) else {
            utcTimeString = displayTime // pass through if not parseable
            return
        }

        let tz = selectedTimezone
        if tz.secondsFromGMT() == 0 {
            utcTimeString = formatTime(hour: hour, minute: minute)
            return
        }

        // Convert from selected TZ to UTC
        let offset = tz.secondsFromGMT() / 60
        var totalMinutes = hour * 60 + minute - offset
        if totalMinutes < 0 { totalMinutes += 1440 }
        if totalMinutes >= 1440 { totalMinutes -= 1440 }

        utcTimeString = formatTime(hour: totalMinutes / 60, minute: totalMinutes % 60)
    }

    private func updateDisplayFromUTC() {
        isUpdating = true
        defer { isUpdating = false }

        guard let (hour, minute) = parseTime(utcTimeString) else {
            displayTime = utcTimeString
            return
        }

        let tz = selectedTimezone
        if tz.secondsFromGMT() == 0 {
            displayTime = formatTime(hour: hour, minute: minute)
            return
        }

        // Convert from UTC to selected TZ
        let offset = tz.secondsFromGMT() / 60
        var totalMinutes = hour * 60 + minute + offset
        if totalMinutes < 0 { totalMinutes += 1440 }
        if totalMinutes >= 1440 { totalMinutes -= 1440 }

        displayTime = formatTime(hour: totalMinutes / 60, minute: totalMinutes % 60)
    }

    private func parseTime(_ str: String) -> (Int, Int)? {
        let parts = str.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return (h, m)
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}
