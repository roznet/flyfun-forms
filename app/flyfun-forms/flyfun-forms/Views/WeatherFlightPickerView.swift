import SwiftUI
import RZFlight

/// Sheet that lists the pilot's flights from flyfun-weather and imports the
/// chosen one as a `FlightExchange`. The caller maps the payload into the new
/// flight's route step — same review-then-create path as a pasted flight plan.
struct WeatherFlightPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Delivers the chosen flight. The sheet dismisses itself afterward.
    var onImport: (FlightExchange) -> Void

    @State private var phase: Phase = .loading
    @State private var flights: [WeatherFlightSummary] = []
    @State private var importingID: String?
    @State private var errorMessage: String?

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var service: WeatherImportService {
        WeatherImportService(baseURL: APIConfig.weatherBaseURL, session: appState.rollingSession)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy HH:mm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Weather")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await load() }
        .alert("Import failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading your flights…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load flights", systemImage: "cloud.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        case .loaded:
            if flights.isEmpty {
                ContentUnavailableView(
                    "No flights",
                    systemImage: "airplane",
                    description: Text("Flights you plan in FlyFun Weather appear here.")
                )
            } else {
                List(flights) { flight in
                    Button {
                        Task { await importFlight(flight) }
                    } label: {
                        row(flight)
                    }
                    .disabled(importingID != nil)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ flight: WeatherFlightSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.routeLabel)
                    .font(.system(.body, design: .monospaced))
                Text(Self.dateFormatter.string(from: flight.departureTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if importingID == flight.id {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil && phase == .loaded },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func load() async {
        phase = .loading
        do {
            flights = try await service.listFlights()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func importFlight(_ flight: WeatherFlightSummary) async {
        guard importingID == nil else { return }
        importingID = flight.id
        defer { importingID = nil }
        do {
            let exchange = try await service.exportFlight(id: flight.id)
            onImport(exchange)
            dismiss()
        } catch {
            // Stay on the list so the pilot can pick another flight.
            errorMessage = error.localizedDescription
        }
    }
}
