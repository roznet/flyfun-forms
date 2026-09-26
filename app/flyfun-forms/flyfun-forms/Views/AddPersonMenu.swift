import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The ways to bring a person into the app one at a time.
enum AddPersonMethod: Equatable {
    /// An empty person, to fill in by hand.
    case blank
    /// From a passport or ID card's machine-readable zone.
    case scan
    /// From the address book.
    case contact
}

/// The Add Person / Scan Document / Import from Contact menu items, shared by
/// the People tab and the crew/passenger picker. They only record which method
/// was chosen; `addPersonFlows` runs it.
struct AddPersonMenuItems: View {
    @Binding var request: AddPersonMethod?
    var addPersonIdentifier = "addPersonButton"

    var body: some View {
        Button {
            request = .blank
        } label: {
            Label("Add Person", systemImage: "person.badge.plus")
        }
        .accessibilityIdentifier(addPersonIdentifier)
        Button {
            request = .scan
        } label: {
            Label("Scan Document", systemImage: "doc.text.viewfinder")
        }
        Button {
            request = .contact
        } label: {
            Label("Import from Contact", systemImage: "person.crop.rectangle")
        }
    }
}

extension View {
    /// Runs the method `AddPersonMenuItems` put in `request` and hands over the
    /// person it ends with: a new one, or an existing one the scan matched or
    /// the contact was merged into.
    ///
    /// Sheets hang off the view this modifies rather than off the menu, which
    /// lives in a toolbar and can be rebuilt under an open sheet.
    func addPersonFlows(
        request: Binding<AddPersonMethod?>,
        onPerson: @escaping (Person, AddPersonMethod) -> Void
    ) -> some View {
        modifier(AddPersonFlows(request: request, onPerson: onPerson))
    }
}

private struct AddPersonFlows: ViewModifier {
    @Binding var request: AddPersonMethod?
    let onPerson: (Person, AddPersonMethod) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var showContactPicker = false
    @State private var pickedContact: ImportedContact?
    @State private var importedContact: ImportedContact?
    @State private var scanProcessingResult: MRZProcessingResult?
    /// The person a sheet ended with, handed over once that sheet has gone:
    /// the pickers call back before they dismiss, and presenting or pushing
    /// while a sheet is still leaving is silently dropped.
    @State private var pendingPerson: (person: Person, method: AddPersonMethod)?
    #if os(iOS)
    @State private var showingScanSheet = false
    @State private var pendingScan: MRZScanResult?
    #else
    @State private var showFilePicker = false
    @State private var imageOCR = ImageOCRManager()
    @State private var showNoMRZAlert = false
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, method in
                guard let method else { return }
                request = nil
                start(method)
            }
            #if os(iOS)
            .sheet(isPresented: $showContactPicker, onDismiss: showPickedContact) {
                ContactPickerSheet { contact in
                    pickedContact = ImportedContact(from: contact)
                }
            }
            .sheet(isPresented: $showingScanSheet, onDismiss: processPendingScan) {
                ScanDocumentSheet { result in
                    pendingScan = result
                }
            }
            #else
            .sheet(isPresented: $showContactPicker, onDismiss: showPickedContact) {
                ContactSearchView { contact in
                    pickedContact = ImportedContact(from: contact)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    imageOCR.scan(url: url)
                }
            }
            .onChange(of: imageOCR.status) { _, newStatus in
                if newStatus == .success, let result = imageOCR.result {
                    scanProcessingResult = MRZResultProcessor.process(result, context: .standalone, modelContext: modelContext)
                } else if newStatus == .noMRZFound {
                    showNoMRZAlert = true
                }
            }
            .alert("No Document Found", isPresented: $showNoMRZAlert) {
                Button("OK") {}
            } message: {
                Text("No machine-readable zone (MRZ) was found in the file. Try a clearer image or PDF of the passport page.")
            }
            #endif
            .sheet(item: $importedContact, onDismiss: deliverPendingPerson) { contact in
                ContactResolveView(contact: contact) { person in
                    pendingPerson = (person, .contact)
                }
            }
            .sheet(item: $scanProcessingResult, onDismiss: deliverPendingPerson) { processing in
                MRZResultActionView(
                    processingResult: processing,
                    onDismiss: { scanProcessingResult = nil },
                    onPersonSelected: { person in
                        pendingPerson = (person, .scan)
                    }
                )
            }
    }

    private func start(_ method: AddPersonMethod) {
        switch method {
        case .blank:
            let person = Person()
            modelContext.insert(person)
            onPerson(person, .blank)
        case .scan:
            #if os(iOS)
            showingScanSheet = true
            #else
            showFilePicker = true
            #endif
        case .contact:
            showContactPicker = true
        }
    }

    private func showPickedContact() {
        guard let contact = pickedContact else { return }
        pickedContact = nil
        importedContact = contact
    }

    #if os(iOS)
    private func processPendingScan() {
        guard let result = pendingScan else { return }
        pendingScan = nil
        scanProcessingResult = MRZResultProcessor.process(result, context: .standalone, modelContext: modelContext)
    }
    #endif

    private func deliverPendingPerson() {
        guard let pending = pendingPerson else { return }
        pendingPerson = nil
        onPerson(pending.person, pending.method)
    }
}
