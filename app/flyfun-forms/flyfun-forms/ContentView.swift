import FlyFunCommon
import SwiftUI
import SwiftData

/// In display order: Flights first, as the most used.
enum AppSection: String, CaseIterable, Identifiable {
    case flights, people, aircraft, settings
    var id: String { rawValue }

    var title: LocalizedStringResource {
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
            Tab("Flights", systemImage: "arrow.triangle.swap") {
                NavigationStack {
                    FlightsListView()
                }
            }
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
    @State private var selectedSection: AppSection? = .flights

    private var emptyDetailTitle: LocalizedStringResource {
        switch selectedSection {
        case .people: "No Person Selected"
        case .aircraft: "No Aircraft Selected"
        case .flights: "No Flight Selected"
        default: "Nothing Selected"
        }
    }

    private var emptyDetailMessage: LocalizedStringResource {
        switch selectedSection {
        case .people: "Pick someone from the list, or add a new person."
        case .aircraft: "Pick an aircraft from the list, or add a new one."
        case .flights: "Pick a flight from the list, or add a new one."
        default: "Pick a section in the sidebar to get started."
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(String(localized: section.title), systemImage: section.icon)
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
            ContentUnavailableView {
                Label(String(localized: emptyDetailTitle), systemImage: selectedSection?.icon ?? "doc.text")
            } description: {
                Text(emptyDetailMessage)
            }
        }
    }
}

// MARK: - Spoken Languages

/// Languages a pilot may declare they speak, beyond English. When an
/// airport's local language matches, emails go out in that language;
/// otherwise English. Codes are ISO 639-1, matching the server's
/// EmailTextResponse.localLanguage.
enum SpokenLanguage: String, CaseIterable, Identifiable {
    case french = "fr"
    case german = "de"
    case italian = "it"
    case spanish = "es"
    case portuguese = "pt"
    case dutch = "nl"

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        }
    }
}

/// Helpers for the comma-separated `@AppStorage("spokenLanguageCodes")`.
enum SpokenLanguageStorage {
    static let key = "spokenLanguageCodes"

    static func parse(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func serialize(_ codes: Set<String>) -> String {
        codes.sorted().joined(separator: ",")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SpokenLanguageStorage.key) private var spokenLanguageCodes: String = ""
    @AppStorage("useDevServer") private var useDevServer = false

    private func languageBinding(for lang: SpokenLanguage) -> Binding<Bool> {
        Binding(
            get: { SpokenLanguageStorage.parse(spokenLanguageCodes).contains(lang.rawValue) },
            set: { isOn in
                var set = SpokenLanguageStorage.parse(spokenLanguageCodes)
                if isOn { set.insert(lang.rawValue) } else { set.remove(lang.rawValue) }
                spokenLanguageCodes = SpokenLanguageStorage.serialize(set)
            }
        )
    }

    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var errorMessage: String?
    @State private var showDeleteAllDataConfirmation = false
    @State private var deleteAllDataError: String?

    /// What a pilot shows passengers about their details (GDPR Art. 14): the
    /// passport data reaches the app from the pilot, not from the passenger.
    private var passengerPrivacyNote: String {
        String(localized: """
            How I use your details for this flight

            I keep your name and travel-document details in the FlightForms app on my own devices, synced through my private iCloud account. I use them only to fill in the customs, immigration and airport forms this flight requires, and I send those forms to the authorities that ask for them. The FlightForms server fills each form and keeps no copy. Ask me any time to see, correct or delete your details.

            More: \(APIConfig.passengerPrivacyURL.absoluteString)
            """, comment: "Text a pilot shares with passengers about how their details are used. The argument is the privacy policy URL.")
    }

    private var authService: FlyFunAuthService {
        FlyFunAuthService(config: .init(
            baseURL: APIConfig.baseURL,
            callbackScheme: "flyfunforms"
        ))
    }

    var body: some View {
        Form {
            Section {
                ForEach(SpokenLanguage.allCases) { lang in
                    Toggle(String(localized: lang.label), isOn: languageBinding(for: lang))
                }
            } header: {
                Text("Languages You Speak")
            } footer: {
                Text("When an airport's local language matches one you speak, emails are written in that language. Otherwise English is used.")
            }

            if APIConfig.canToggleServer {
                Section("Server") {
                    Toggle("Use Dev Server", isOn: $useDevServer)
                    Text(APIConfig.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
            Section {
                Button {
                    Task { await simulateExpiredToken() }
                } label: {
                    Text("Simulate Expired Token")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Corrupts the stored JWT and fires an authenticated request so the server returns 401. Verifies the rolling-session unauthorized callback flips back to the login screen.")
            }
            #endif

            Section {
                Link(destination: APIConfig.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                ShareLink(item: passengerPrivacyNote) {
                    Label("Privacy Note for Passengers", systemImage: "person.2.badge.gearshape")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Passengers' details come from you, not them — share this so they know how they're used.")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    appState.logout()
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Delete Account")
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("Deletes your FlightForms account and its usage records on the server. People, aircraft, flights and trips stay on this device and in iCloud.")
                }
            }

            Section {
                Button("Delete All Data", role: .destructive) {
                    showDeleteAllDataConfirmation = true
                }
                .confirmationDialog(
                    "Delete All Data",
                    isPresented: $showDeleteAllDataConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete All Data", role: .destructive) {
                        deleteAllData()
                    }
                } message: {
                    Text("Deletes all people, documents, aircraft, flights and trips from this device and from your iCloud, so from all your devices signed into this Apple ID. This cannot be undone. Your FlightForms account is not affected.")
                }
            } footer: {
                if let deleteAllDataError {
                    Text(deleteAllDataError)
                        .foregroundStyle(.red)
                } else {
                    Text("Removes people, documents, aircraft, flights and trips from all your devices. You stay signed in.")
                }
            }
        }
        .platformFormStyle()
        .frame(maxWidth: FormLayout.columnMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your FlightForms account and its usage records on the server. It cannot be undone. People, aircraft, flights and trips stay on this device and in iCloud: use Delete All Data to remove them.")
        }
    }

    private func deleteAllData() {
        deleteAllDataError = nil
        do {
            try LocalDataEraser.eraseAll(in: modelContext)
            appState.localDataErased()
        } catch {
            deleteAllDataError = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        guard let jwt = appState.jwt else { return }
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccount(jwt: jwt)
            appState.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func simulateExpiredToken() async {
        appState.tokenStore.token = "expired-test-token"
        // Trigger an authenticated call so the server (must not be the
        // dev server, which auto-accepts) returns 401 and the rolling
        // session's onUnauthorized callback fires.
        let formService = FormService(baseURL: APIConfig.baseURL, session: appState.rollingSession)
        _ = try? await formService.airportDetail(icao: "LFMD")
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, Aircraft.self, Flight.self, Trip.self], inMemory: true)
}
