import SwiftUI
import SwiftData
#if os(iOS)
import MessageUI
#endif

struct FlightEditView: View {
    @Bindable var flight: Flight
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]
    @Query(sort: \Person.lastName) private var allPeople: [Person]
    @Environment(\.airportCatalog) private var catalog
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showAirportPicker = false
    @State private var showPeoplePicker = false
    @State private var showResponsiblePersonPicker = false
    @State private var editingCrew: [Person] = []
    @State private var editingPassengers: [Person] = []
    @State private var isGenerating = false
    @State private var generatingForm: String?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var validationErrors: [ServerValidationError] = []
    @State private var showingValidationErrors = false
    @State private var shareFileURL: URL?
    @State private var emailFileURL: URL?
    @State private var emailFormInfo: FormInfo?
    @State private var formDetails: [String: [FormInfo]] = [:]
    @State private var extraFieldValues: [String: [String: ExtraFieldValue]] = [:]
    @State private var previousDepartureDate: Date?

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let reasonOptions = [
        "Based",
        "Short Term Visit",
        "Maintenance",
        "Permanent Import",
        "Repair",
    ]

    var body: some View {
        Group {
            if sizeClass == .regular {
                wideLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle(flight.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showingValidationErrors) {
            ValidationErrorsView(errors: validationErrors)
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { shareFileURL != nil },
            set: { if !$0 { shareFileURL = nil } }
        )) {
            if let url = shareFileURL {
                ActivityView(activityItems: [url])
            }
        }
        .sheet(isPresented: Binding(
            get: { emailFileURL != nil },
            set: { if !$0 { emailFileURL = nil; emailFormInfo = nil } }
        )) {
            if let url = emailFileURL, let info = emailFormInfo {
                MailComposeView(
                    fileURL: url,
                    formInfo: info,
                    flight: flight
                )
            }
        }
        #else
        .sheet(isPresented: Binding(
            get: { shareFileURL != nil },
            set: { if !$0 { shareFileURL = nil } }
        )) {
            if let url = shareFileURL {
                MacShareView(url: url, formInfo: emailFormInfo, flight: flight) {
                    shareFileURL = nil
                    emailFormInfo = nil
                }
            }
        }
        #endif
        .sheet(isPresented: $showAirportPicker) {
            AirportPickerView(originICAO: $flight.originICAO, destinationICAO: $flight.destinationICAO)
        }
        .sheet(isPresented: $showPeoplePicker, onDismiss: applyPeopleSelection) {
            PeoplePickerView(selectedCrew: $editingCrew, selectedPassengers: $editingPassengers)
        }
        .sheet(isPresented: $showResponsiblePersonPicker) {
            SinglePersonPickerView(selectedPerson: responsiblePersonObjectBinding)
        }
        .onChange(of: flight.originICAO) {
            fetchFormDetails(icao: flight.originICAO)
        }
        .onChange(of: flight.destinationICAO) {
            fetchFormDetails(icao: flight.destinationICAO)
        }
        .onChange(of: flight.departureDate) { oldValue, newValue in
            autoSyncArrivalDate(oldDeparture: oldValue, newDeparture: newValue)
        }
        .onAppear {
            previousDepartureDate = flight.departureDate
            fetchFormDetails(icao: flight.originICAO)
            fetchFormDetails(icao: flight.destinationICAO)
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        Form {
            routeSection
            scheduleSection
            aircraftSection
            flightDetailsSection
            peopleButton
            crewSection
            passengersSection
            formSections
            actionsSection
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                routeSection
                scheduleSection
                aircraftSection
                flightDetailsSection
                formSections
                actionsSection
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            Form {
                peopleButton
                crewSection
                passengersSection
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var routeSection: some View {
        Section("Route") {
            Button {
                showAirportPicker = true
            } label: {
                HStack {
                    let origin = flight.originICAO.isEmpty ? "----" : flight.originICAO
                    let dest = flight.destinationICAO.isEmpty ? "----" : flight.destinationICAO
                    Text("\(origin)  \(Image(systemName: "arrow.right"))  \(dest)")
                        .font(.system(.title3, design: .monospaced).bold())
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Departure Date", selection: $flight.departureDate, displayedComponents: .date)
            LabeledContent("Departure Time") {
                TimeEntryView(
                    utcTimeString: $flight.departureTimeUTC,
                    airportICAO: flight.originICAO,
                    originICAO: flight.originICAO,
                    destinationICAO: flight.destinationICAO
                )
            }
            DatePicker("Arrival Date", selection: $flight.arrivalDate, displayedComponents: .date)
            LabeledContent("Arrival Time") {
                TimeEntryView(
                    utcTimeString: $flight.arrivalTimeUTC,
                    airportICAO: flight.destinationICAO,
                    originICAO: flight.originICAO,
                    destinationICAO: flight.destinationICAO
                )
            }
        }
    }

    @ViewBuilder
    private var aircraftSection: some View {
        Section("Aircraft") {
            Picker("Aircraft", selection: $flight.aircraft) {
                Text("None").tag(nil as Aircraft?)
                ForEach(allAircraft) { ac in
                    Text("\(ac.registration) (\(ac.type))").tag(ac as Aircraft?)
                }
            }
        }
    }

    @ViewBuilder
    private var flightDetailsSection: some View {
        Section("Flight Details") {
            Picker("Nature", selection: $flight.nature) {
                Text("Private", comment: "Flight nature").tag("private")
                Text("Commercial", comment: "Flight nature").tag("commercial")
            }
            Picker("Reason for Visit", selection: reasonForVisitBinding) {
                Text("—").tag("")
                ForEach(Self.reasonOptions, id: \.self) { reason in
                    Text(LocalizedStringKey(reason)).tag(reason)
                }
            }
            Button {
                showResponsiblePersonPicker = true
            } label: {
                HStack {
                    Text("Responsible Person")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(flight.responsiblePerson?.displayName ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
            if let person = flight.responsiblePerson {
                if let phone = person.phone, !phone.isEmpty {
                    LabeledContent("Phone", value: phone)
                        .foregroundStyle(.secondary)
                }
                if let address = person.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Observations", text: Binding(
                get: { flight.observations ?? "" },
                set: { flight.observations = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var peopleButton: some View {
        Section {
            Button {
                editingCrew = flight.crewList
                editingPassengers = flight.passengerList
                showPeoplePicker = true
            } label: {
                Label("Edit Crew & Passengers", systemImage: "person.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var crewSection: some View {
        Section("Crew") {
            ForEach(flight.crewList) { person in
                Text(person.displayName)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            flight.crew?.removeAll { $0.persistentModelID == person.persistentModelID }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var passengersSection: some View {
        Section("Passengers") {
            ForEach(flight.passengerList) { person in
                Text(person.displayName)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            flight.passengers?.removeAll { $0.persistentModelID == person.persistentModelID }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        if !flight.destinationICAO.isEmpty {
            formSection(airport: flight.destinationICAO, direction: "arrival")
        }
        if !flight.originICAO.isEmpty {
            formSection(airport: flight.originICAO, direction: "departure")
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Actions") {
            Button {
                createReturnFlight()
            } label: {
                Label("Create Return Flight", systemImage: "arrow.uturn.left")
            }
            Button {
                duplicateFlight()
            } label: {
                Label("Duplicate Flight", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Bindings

    private var reasonForVisitBinding: Binding<String> {
        Binding(
            get: { flight.reasonForVisit ?? "" },
            set: { flight.reasonForVisit = $0.isEmpty ? nil : $0 }
        )
    }

    private var responsiblePersonObjectBinding: Binding<Person?> {
        Binding(
            get: { flight.responsiblePerson },
            set: { newValue in
                flight.responsiblePerson = newValue
                // Also sync contact field for backward compat
                flight.contact = newValue?.phone
            }
        )
    }

    // MARK: - Arrival Date Auto-sync

    private func autoSyncArrivalDate(oldDeparture: Date, newDeparture: Date) {
        // Only sync if arrival was matching old departure (user hasn't manually changed it)
        if Calendar.current.isDate(flight.arrivalDate, inSameDayAs: oldDeparture) {
            flight.arrivalDate = newDeparture
        }
    }

    // MARK: - Form Sections

    @ViewBuilder
    private func formSection(airport: String, direction: String) -> some View {
        let forms = formDetails[airport] ?? []
        if !forms.isEmpty {
            ForEach(forms) { formInfo in
                Section("\(airport) — \(formInfo.label) (\(direction))") {
                    extraFieldsView(airport: airport, formInfo: formInfo)

                    HStack {
                        Button {
                            Task { await generateAndShare(airport: airport, form: formInfo.id) }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isGenerating)

                        Spacer()

                        if generatingForm == "\(airport)_\(formInfo.id)" {
                            ProgressView()
                        }

                        Spacer()

                        Button {
                            Task { await generateAndEmail(airport: airport, formInfo: formInfo) }
                        } label: {
                            Label("Email", systemImage: "envelope")
                        }
                        .disabled(isGenerating)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func extraFieldsView(airport: String, formInfo: FormInfo) -> some View {
        let formKey = "\(airport)_\(formInfo.id)"
        let hiddenKeys: Set<String> = ["reason_for_visit", "responsible_person"]
        ForEach(formInfo.extraFields.filter({ !hiddenKeys.contains($0.key) })) { field in
            switch field.type {
            case "choice":
                Picker(field.label, selection: extraFieldBinding(formKey: formKey, fieldKey: field.key, defaultValue: field.options?.first ?? "")) {
                    ForEach(field.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            case "person":
                let allPeopleOnFlight = flight.crewList + flight.passengerList
                Picker(field.label, selection: personExtraFieldBinding(formKey: formKey, fieldKey: field.key, people: allPeopleOnFlight)) {
                    Text("—").tag("")
                    ForEach(allPeopleOnFlight) { person in
                        Text(person.displayName).tag(person.displayName)
                    }
                }
                if case .person(let dict) = extraFieldValues[formKey]?[field.key],
                   !dict.isEmpty {
                    TextField("Address", text: personAddressBinding(formKey: formKey, fieldKey: field.key))
                        .foregroundStyle(.secondary)
                }
            default:
                TextField(field.label, text: textExtraFieldBinding(formKey: formKey, fieldKey: field.key))
            }
        }
    }

    // MARK: - Extra field bindings

    private func extraFieldBinding(formKey: String, fieldKey: String, defaultValue: String) -> Binding<String> {
        Binding(
            get: {
                if case .text(let val) = extraFieldValues[formKey]?[fieldKey] { return val }
                return defaultValue
            },
            set: { newValue in
                if extraFieldValues[formKey] == nil { extraFieldValues[formKey] = [:] }
                extraFieldValues[formKey]?[fieldKey] = .text(newValue)
            }
        )
    }

    private func textExtraFieldBinding(formKey: String, fieldKey: String) -> Binding<String> {
        extraFieldBinding(formKey: formKey, fieldKey: fieldKey, defaultValue: "")
    }

    private func personExtraFieldBinding(formKey: String, fieldKey: String, people: [Person]) -> Binding<String> {
        Binding(
            get: {
                if case .person(let dict) = extraFieldValues[formKey]?[fieldKey] { return dict["name"] ?? "" }
                return ""
            },
            set: { newValue in
                if extraFieldValues[formKey] == nil { extraFieldValues[formKey] = [:] }
                if let person = people.first(where: { $0.displayName == newValue }) {
                    extraFieldValues[formKey]?[fieldKey] = .person([
                        "name": person.displayName,
                        "address": person.address ?? "",
                    ])
                } else {
                    extraFieldValues[formKey]?[fieldKey] = .person([:])
                }
            }
        )
    }

    private func personAddressBinding(formKey: String, fieldKey: String) -> Binding<String> {
        Binding(
            get: {
                if case .person(let dict) = extraFieldValues[formKey]?[fieldKey] { return dict["address"] ?? "" }
                return ""
            },
            set: { newValue in
                if case .person(var dict) = extraFieldValues[formKey]?[fieldKey] {
                    dict["address"] = newValue
                    extraFieldValues[formKey]?[fieldKey] = .person(dict)
                }
            }
        )
    }

    // MARK: - Fetch form details

    private func fetchFormDetails(icao: String) {
        guard !icao.isEmpty, formDetails[icao] == nil else { return }
        let formService = FormService(baseURL: APIConfig.baseURL, jwt: appState.jwt)
        Task {
            if let detail = try? await formService.airportDetail(icao: icao) {
                formDetails[icao] = detail.forms
            }
        }
    }

    private func generateForm(airport: String, form: String) async -> URL? {
        isGenerating = true
        generatingForm = "\(airport)_\(form)"
        defer {
            isGenerating = false
            generatingForm = nil
        }

        let formService = FormService(baseURL: APIConfig.baseURL, jwt: appState.jwt)
        let request = buildRequest(airport: airport, form: form)
        do {
            let (data, filename) = try await formService.generate(request: request, flatten: true)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)
            return tempURL
        } catch let FormService.FormError.validationErrors(errors) {
            validationErrors = errors
            showingValidationErrors = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        return nil
    }

    private func generateAndShare(airport: String, form: String) async {
        if let url = await generateForm(airport: airport, form: form) {
            shareFileURL = url
        }
    }

    private func generateAndEmail(airport: String, formInfo: FormInfo) async {
        if let url = await generateForm(airport: airport, form: formInfo.id) {
            emailFormInfo = formInfo
            #if os(iOS)
            if MFMailComposeViewController.canSendMail() {
                emailFileURL = url
            } else {
                // No mail account configured — fall back to share sheet
                shareFileURL = url
            }
            #else
            // On macOS, open email directly via NSSharingService
            sendEmailDirectly(url: url, formInfo: formInfo)
            #endif
        }
    }

    #if os(macOS)
    private func sendEmailDirectly(url: URL, formInfo: FormInfo) {
        guard let service = NSSharingService(named: .composeEmail) else {
            // No email service — fall back to share sheet
            shareFileURL = url
            return
        }
        service.recipients = formInfo.email?.to ?? (formInfo.sendTo.map { [$0] } ?? [])
        service.subject = emailSubject(formInfo: formInfo, flight: flight)
        service.perform(withItems: [
            emailBody(formInfo: formInfo, flight: flight),
            url,
        ])
    }
    #endif

    private func buildRequest(airport: String, form: String) -> GenerateRequest {
        // Derive contact name from responsible person
        let contactValue = flight.responsiblePerson?.displayName ?? flight.contact

        let flightPayload = FlightPayload(
            origin: flight.originICAO,
            destination: flight.destinationICAO,
            departureDate: dateFmt.string(from: flight.departureDate),
            departureTimeUtc: flight.departureTimeUTC,
            arrivalDate: dateFmt.string(from: flight.arrivalDate),
            arrivalTimeUtc: flight.arrivalTimeUTC,
            nature: flight.nature,
            contact: contactValue
        )

        let aircraftPayload: AircraftPayload
        if let ac = flight.aircraft {
            aircraftPayload = AircraftPayload(
                registration: ac.registration,
                type: ac.type,
                owner: ac.owner,
                ownerAddress: ac.ownerAddress,
                isAirplane: ac.isAirplane,
                usualBase: ac.usualBase
            )
        } else {
            aircraftPayload = AircraftPayload(registration: "", type: "")
        }

        let crewPayloads = flight.crewList.enumerated().map { (i, p) in
            personPayload(p, function: i == 0 ? "Pilot" : "Crew", airport: airport)
        }
        let paxPayloads = flight.passengerList.map { personPayload($0, airport: airport) }

        let formKey = "\(airport)_\(form)"
        var extras = extraFieldValues[formKey] ?? [:]

        // Inject reason_for_visit into extra fields for forms that need it
        if let reason = flight.reasonForVisit, !reason.isEmpty {
            extras["reason_for_visit"] = .text(reason)
        }

        // Inject responsible_person into extra fields for forms that need it
        if let person = flight.responsiblePerson {
            extras["responsible_person"] = .person([
                "name": person.displayName,
                "address": person.address ?? "",
            ])
            // Auto-fill telephone and email from responsible person if not already set
            if extras["telephone"] == nil, let phone = person.phone, !phone.isEmpty {
                extras["telephone"] = .text(phone)
            }
            if extras["email"] == nil, let email = person.email, !email.isEmpty {
                extras["email"] = .text(email)
            }
        }

        return GenerateRequest(
            airport: airport,
            form: form,
            flight: flightPayload,
            aircraft: aircraftPayload,
            crew: crewPayloads,
            passengers: paxPayloads,
            extraFields: extras.isEmpty ? nil : extras,
            observations: flight.observations
        )
    }

    private func personPayload(_ p: Person, function: String? = nil, airport: String) -> PersonPayload {
        let doc = DocumentResolver.resolve(person: p, airport: airport)
        return PersonPayload(
            function: function,
            firstName: p.firstName,
            lastName: p.lastName,
            dob: p.dateOfBirth.map { dateFmt.string(from: $0) },
            nationality: doc?.issuingCountry,
            idNumber: doc?.docNumber,
            idType: doc?.docType,
            idIssuingCountry: doc?.issuingCountry,
            idExpiry: doc?.expiryDate.map { dateFmt.string(from: $0) },
            sex: p.sex,
            placeOfBirth: p.placeOfBirth,
            address: p.address
        )
    }

    private var availablePeople: [Person] {
        let crewIDs = Set(flight.crewList.map(\.persistentModelID))
        let paxIDs = Set(flight.passengerList.map(\.persistentModelID))
        return allPeople.filter { !crewIDs.contains($0.persistentModelID) && !paxIDs.contains($0.persistentModelID) }
    }

    // MARK: - People Picker

    private func applyPeopleSelection() {
        flight.crew = editingCrew.isEmpty ? nil : editingCrew
        flight.passengers = editingPassengers.isEmpty ? nil : editingPassengers
    }

    // MARK: - Return / Duplicate

    @Environment(\.modelContext) private var modelContext

    private func createReturnFlight() {
        let newFlight = Flight()
        newFlight.originICAO = flight.destinationICAO
        newFlight.destinationICAO = flight.originICAO
        newFlight.departureDate = flight.arrivalDate
        newFlight.arrivalDate = flight.arrivalDate
        newFlight.aircraft = flight.aircraft
        newFlight.crew = flight.crew
        newFlight.passengers = flight.passengers
        newFlight.nature = flight.nature
        newFlight.contact = flight.contact
        newFlight.reasonForVisit = flight.reasonForVisit
        newFlight.responsiblePerson = flight.responsiblePerson
        modelContext.insert(newFlight)
    }

    private func duplicateFlight() {
        let newFlight = Flight()
        newFlight.originICAO = flight.originICAO
        newFlight.destinationICAO = flight.destinationICAO
        newFlight.departureDate = flight.departureDate
        newFlight.departureTimeUTC = flight.departureTimeUTC
        newFlight.arrivalDate = flight.arrivalDate
        newFlight.arrivalTimeUTC = flight.arrivalTimeUTC
        newFlight.aircraft = flight.aircraft
        newFlight.crew = flight.crew
        newFlight.passengers = flight.passengers
        newFlight.nature = flight.nature
        newFlight.contact = flight.contact
        newFlight.observations = flight.observations
        newFlight.reasonForVisit = flight.reasonForVisit
        newFlight.responsiblePerson = flight.responsiblePerson
        modelContext.insert(newFlight)
    }
}

// MARK: - Email helpers

private func emailSubject(formInfo: FormInfo, flight: Flight) -> String {
    let reg = flight.aircraft?.registration ?? ""
    let date = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: flight.departureDate)
    }()
    let airport = flight.destinationICAO
    return "\(formInfo.label) - \(airport) - \(date) - \(reg)"
}

private func emailBody(formInfo: FormInfo, flight: Flight) -> String {
    let reg = flight.aircraft?.registration ?? ""
    let date = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: flight.departureDate)
    }()
    return "Please find attached the \(formInfo.label) for flight \(flight.originICAO) \u{2192} \(flight.destinationICAO) on \(date), aircraft \(reg)."
}

private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "pdf": return "application/pdf"
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    default: return "application/octet-stream"
    }
}

#if os(iOS)
// MARK: - Share Sheet

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail Compose

struct MailComposeView: UIViewControllerRepresentable {
    let fileURL: URL
    let formInfo: FormInfo
    let flight: Flight
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator

        // Recipients
        let toList = formInfo.email?.to ?? (formInfo.sendTo.map { [$0] } ?? [])
        if !toList.isEmpty { vc.setToRecipients(toList) }
        let ccList = formInfo.email?.cc ?? []
        if !ccList.isEmpty { vc.setCcRecipients(ccList) }

        // Subject & body
        vc.setSubject(emailSubject(formInfo: formInfo, flight: flight))
        vc.setMessageBody(emailBody(formInfo: formInfo, flight: flight), isHTML: false)

        // Attachment
        if let data = try? Data(contentsOf: fileURL) {
            vc.addAttachmentData(data, mimeType: mimeType(for: fileURL), fileName: fileURL.lastPathComponent)
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
#else
// MARK: - macOS Share View

struct MacShareView: View {
    let url: URL
    var formInfo: FormInfo?
    var flight: Flight?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            List {
                Button {
                    saveToFile()
                } label: {
                    Label("Save to File\u{2026}", systemImage: "folder")
                }
                .buttonStyle(.plain)

                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(url)
                    onDismiss()
                } label: {
                    Label("Open", systemImage: "doc")
                }
                .buttonStyle(.plain)

                Button {
                    sendEmail()
                } label: {
                    Label("Email", systemImage: "envelope")
                }
                .buttonStyle(.plain)

                Section("Share") {
                    ForEach(sharingServices, id: \.title) { service in
                        Button {
                            service.perform(withItems: [url])
                            onDismiss()
                        } label: {
                            HStack {
                                Image(nsImage: service.image)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(service.title)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }

    private var sharingServices: [NSSharingService] {
        NSSharingService.sharingServices(forItems: [url])
    }

    private func sendEmail() {
        guard let service = NSSharingService(named: .composeEmail) else {
            // Fallback: open the file (user can email manually)
            NSWorkspace.shared.open(url)
            onDismiss()
            return
        }
        if let info = formInfo, let fl = flight {
            service.recipients = info.email?.to ?? (info.sendTo.map { [$0] } ?? [])
            service.subject = emailSubject(formInfo: info, flight: fl)
        }
        service.perform(withItems: [url])
        onDismiss()
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        onDismiss()
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onDismiss()
    }
}
#endif
