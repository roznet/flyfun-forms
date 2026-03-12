import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case people, aircraft, flights, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .people: "People"
        case .aircraft: "Aircraft"
        case .flights: "Flights"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .people: "person.2"
        case .aircraft: "airplane"
        case .flights: "arrow.triangle.swap"
        case .settings: "gear"
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            CompactContentView()
        } else {
            WideContentView()
        }
    }
}

// MARK: - iPhone layout (tabs)

struct CompactContentView: View {
    var body: some View {
        TabView {
            Tab("People", systemImage: "person.2") {
                NavigationStack {
                    PeopleListView()
                }
            }
            Tab("Aircraft", systemImage: "airplane") {
                NavigationStack {
                    AircraftListView()
                }
            }
            Tab("Flights", systemImage: "arrow.triangle.swap") {
                NavigationStack {
                    FlightsListView()
                }
            }
            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

// MARK: - iPad / Mac layout (sidebar + list + detail)

struct WideContentView: View {
    @State private var selectedSection: AppSection? = .people

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.icon)
                    }
                }
            }
            .navigationTitle("Flyfun Forms")
        } content: {
            Group {
                switch selectedSection {
                case .people:
                    PeopleListView()
                case .aircraft:
                    AircraftListView()
                case .flights:
                    FlightsListView()
                case .settings:
                    SettingsView()
                case nil:
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
                }
            }
        } detail: {
            ContentUnavailableView("Select an Item", systemImage: "doc.text")
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                Button("Sign Out", role: .destructive) {
                    appState.logout()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, Aircraft.self, Flight.self, Trip.self], inMemory: true)
}
