import SwiftUI

/// Sheet listing the pilot's recent Autorouter routes. The chosen route's ICAO
/// flight plan is parsed on-device and handed back as a `FlightDraft`, the same
/// path a pasted plan takes.
struct AutorouterRoutePickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Delivers the chosen route as a draft. The sheet dismisses itself after.
    var onImport: (FlightDraft) -> Void

    @State private var phase: Phase = .loading
    @State private var routes: [AutorouterRouteSummary] = []
    @State private var errorMessage: String?

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var service: AutorouterImportService {
        AutorouterImportService(baseURL: APIConfig.baseURL, session: appState.rollingSession)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Import from Autorouter"))
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
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .task { await load() }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { errorMessage != nil && phase == .loaded },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView(String(localized: "Loading your routes…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load routes", systemImage: "arrow.down.doc")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        case .loaded:
            if routes.isEmpty {
                ContentUnavailableView(
                    String(localized: "No recent routes"),
                    systemImage: "arrow.down.doc",
                    description: Text("Routes you plan in Autorouter appear here.")
                )
            } else {
                List(routes) { route in
                    Button {
                        select(route)
                    } label: {
                        row(route)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ route: AutorouterRouteSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.routeLabel)
                    .font(.system(.body, design: .monospaced))
                Text(subtitle(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "square.and.arrow.down")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Date, distance and aircraft — what tells two flights on the same route
    /// apart. Missing parts are dropped rather than shown blank.
    private func subtitle(for route: AutorouterRouteSummary) -> String {
        var parts: [String] = []
        if let departureTime = route.departureTime {
            parts.append(Self.dateFormatter.string(from: departureTime))
        }
        if let distance = route.routeDistanceNm {
            parts.append(String(localized: "\(distance) nm"))
        }
        if let aircraft = route.aircraftDescription, !aircraft.isEmpty {
            parts.append(aircraft)
        } else if let callsign = route.callsign, !callsign.isEmpty {
            parts.append(callsign)
        }
        return parts.joined(separator: " · ")
    }

    /// Parsing is local and synchronous, so a pick either lands or reports why
    /// without leaving the pilot on a spinner.
    private func select(_ route: AutorouterRouteSummary) {
        do {
            onImport(try AutorouterImportService.draft(from: route))
            dismiss()
        } catch {
            // Stay on the list so the pilot can pick another route.
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        phase = .loading
        errorMessage = nil
        do {
            routes = try await service.listRoutes()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
