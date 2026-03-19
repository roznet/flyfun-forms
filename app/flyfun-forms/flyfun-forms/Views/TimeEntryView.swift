import SwiftUI

/// Reusable time entry widget that stores UTC but lets the user view/edit in a chosen timezone.
/// Shows an HStack with a time TextField and a timezone Picker.
/// Timezone options: UTC + origin TZ + destination TZ (deduped). Default = relevant airport's local TZ.
struct TimeEntryView: View {
    /// The UTC time string binding (HH:mm format), stored in the model.
    @Binding var utcTimeString: String

    /// ICAO code of the relevant airport (used to pick default timezone).
    var airportICAO: String

    /// ICAO code of the origin airport (for timezone options).
    var originICAO: String

    /// ICAO code of the destination airport (for timezone options).
    var destinationICAO: String

    @State private var displayTime: String = ""
    @State private var selectedTimezoneId: String = "GMT"
    @State private var isUpdating = false
    @State private var originTZ: TimeZone?
    @State private var destTZ: TimeZone?

    private var selectedTimezone: TimeZone {
        availableTimezones.first(where: { $0.identifier == selectedTimezoneId }) ?? .gmt
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("11:00", text: $displayTime)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .multilineTextAlignment(.trailing)
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
            resolveTimezones()
        }
        .onChange(of: utcTimeString) {
            guard !isUpdating else { return }
            updateDisplayFromUTC()
        }
        .onChange(of: airportICAO) { resolveTimezones() }
        .onChange(of: originICAO) { resolveTimezones() }
        .onChange(of: destinationICAO) { resolveTimezones() }
    }

    // MARK: - Timezone Resolution

    private func resolveTimezones() {
        let cache = AirportTimezoneCache.shared

        // Check if already cached
        originTZ = cache.timezone(for: originICAO)
        destTZ = cache.timezone(for: destinationICAO)
        applyDefaults()

        // Resolve if needed, update when done
        cache.resolve(icao: originICAO) {
            originTZ = cache.timezone(for: originICAO)
            applyDefaults()
        }
        cache.resolve(icao: destinationICAO) {
            destTZ = cache.timezone(for: destinationICAO)
            applyDefaults()
        }
    }

    private func applyDefaults() {
        let cache = AirportTimezoneCache.shared
        if let localTZ = cache.timezone(for: airportICAO) {
            if selectedTimezoneId == "GMT" {
                selectedTimezoneId = localTZ.identifier
            }
        }
        updateDisplayFromUTC()
    }

    // MARK: - Available Timezones

    private var availableTimezones: [TimeZone] {
        var tzs: [TimeZone] = [.gmt]
        for tz in [originTZ, destTZ].compactMap({ $0 }) {
            if !tzs.contains(where: { $0.identifier == tz.identifier }) {
                tzs.append(tz)
            }
        }
        return tzs
    }

    private func tzLabel(_ tz: TimeZone) -> String {
        if tz.identifier == TimeZone.gmt.identifier { return "UTC" }
        let city = tz.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
        let seconds = tz.secondsFromGMT()
        if seconds == 0 { return city }
        let sign = seconds >= 0 ? "+" : ""
        return "\(city) (\(sign)\(seconds / 3600))"
    }

    // MARK: - Conversion

    private func updateUTCFromDisplay() {
        isUpdating = true
        defer { isUpdating = false }

        guard let (hour, minute) = parseTime(displayTime) else {
            utcTimeString = displayTime
            return
        }

        let tz = selectedTimezone
        if tz.secondsFromGMT() == 0 {
            utcTimeString = formatTime(hour: hour, minute: minute)
            return
        }

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
