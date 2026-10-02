import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Settings → Move My Data and Download a Copy of My Data (GDPR).
//
// The flow and wording follow Android's `ui/settings/SettingsScreen.kt`
// (`strings_settings.xml`). Kept away from the Privacy section's sharing UI on
// purpose, and there is no per-person export: this moves the user's own data
// between their own devices (designs/future/move-my-data.md §8).
//
// `MoveMyDataSections` renders the rows; `.moveMyDataPresentation(_:)` hangs
// every sheet, file panel and alert on the Form once, so nothing is presented
// twice by being attached to each section.

/// Where the Move My Data flow is, for one Settings screen.
@MainActor
@Observable
final class MoveMyDataFlow {

    enum Sheet: Identifiable {
        /// Export: choose the passphrase, pre-filled with a suggestion.
        case exportPassphrase
        /// Import: an encrypted file was picked and needs its passphrase.
        case importPassphrase

        var id: Self { self }
    }

    enum Notice {
        /// The encrypted file was saved; show the passphrase once more.
        case passphraseReminder(String)
        /// Decoded, nothing written: confirm or cancel.
        case preview(DataTransfer.ImportPreview)
        case imported(MergeSummary)
        case failure(String)
    }

    var sheet: Sheet?
    var notice: Notice?

    var exportPassphrase = ""
    var importPassphrase = ""
    /// Shown inside the import passphrase sheet, so the user can retry.
    var importPassphraseError: String?

    var isExporterPresented = false
    var isImporterPresented = false
    private(set) var exportFile: DataFile?
    private(set) var exportFilename = ""

    /// The encrypted file waiting for its passphrase. Memory only.
    private var pendingImport: Data?
    /// Passphrase of the file being saved, for the reminder. Memory only.
    private var savedPassphrase: String?

    // SwiftUI drops a presentation started while another one is still
    // animating away: a file panel right after a sheet closes, an alert from
    // the button of the alert that is closing. So the next step waits for the
    // current one to be gone: `sheetDismissed`, `alertDismissed`, and the next
    // runloop turn after a file panel's callback.
    private var afterSheet: (() -> Void)?
    private var afterAlert: Notice?

    static let encryptedFilename = "flyfun-forms-data.ffdata"
    static let plainFilename = "flyfun-forms-export.json"

    // MARK: Export

    func startEncryptedExport() {
        exportPassphrase = DataFileCrypto.generatePassphrase()
        sheet = .exportPassphrase
    }

    func suggestAnotherPassphrase() {
        exportPassphrase = DataFileCrypto.generatePassphrase()
    }

    var canExport: Bool {
        !exportPassphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func exportEncrypted(in context: ModelContext) {
        guard canExport else { return }
        let passphrase = DataFileCrypto.normalisePassphrase(exportPassphrase)
        do {
            let data = try DataTransfer.exportEncrypted(in: context, passphrase: passphrase)
            savedPassphrase = passphrase
            afterSheet = { [weak self] in
                self?.present(DataFile(data: data, contentType: .data), named: Self.encryptedFilename)
            }
        } catch {
            afterSheet = { [weak self] in self?.fail(error, fallback: String(localized: "Export failed")) }
        }
        sheet = nil
    }

    /// GDPR Art. 20: machine-readable, and deliberately not encrypted.
    func exportPlain(in context: ModelContext) {
        do {
            let data = try DataTransfer.exportPlain(in: context)
            present(DataFile(data: data, contentType: .json), named: Self.plainFilename)
            savedPassphrase = nil
        } catch {
            fail(error, fallback: String(localized: "Export failed"))
        }
    }

    func exportFinished(_ result: Result<URL, Error>) {
        exportFile = nil
        defer { savedPassphrase = nil; exportPassphrase = "" }
        switch result {
        case .success:
            // The save panel is still closing; see `afterSheet`.
            if let savedPassphrase {
                DispatchQueue.main.async { [weak self] in self?.notice = .passphraseReminder(savedPassphrase) }
            }
        case .failure(let error):
            // Cancelling the save panel is not a failure worth reporting.
            if (error as? CocoaError)?.code == .userCancelled { return }
            fail(error, fallback: String(localized: "Export failed"))
        }
    }

    private func present(_ file: DataFile, named filename: String) {
        exportFile = file
        exportFilename = filename
        isExporterPresented = true
    }

    // MARK: Import

    func startImport() {
        isImporterPresented = true
    }

    func filePicked(_ result: Result<[URL], Error>, in context: ModelContext) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // The file panel is still closing; see `afterSheet`.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if DataFileCrypto.looksEncrypted(data) {
                        pendingImport = data
                        importPassphrase = ""
                        importPassphraseError = nil
                        sheet = .importPassphrase
                    } else {
                        showPreview(of: data, passphrase: nil, in: context)
                    }
                }
            } catch {
                fail(error, fallback: String(localized: "Could not read that file"))
            }
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            fail(error, fallback: String(localized: "Could not read that file"))
        }
    }

    var canOpen: Bool {
        !importPassphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openWithPassphrase(in context: ModelContext) {
        guard let data = pendingImport, canOpen else { return }
        do {
            let preview = try DataTransfer.preview(data, passphrase: importPassphrase, in: context)
            clearPendingImport()
            afterSheet = { [weak self] in self?.notice = .preview(preview) }
            sheet = nil
        } catch DataFileCrypto.Failure.wrongPassphrase {
            // Stay in the sheet: a typo should cost a retry, not a re-pick.
            importPassphraseError = DataFileCrypto.Failure.wrongPassphrase.errorDescription
        } catch {
            clearPendingImport()
            afterSheet = { [weak self] in
                self?.fail(error, fallback: String(localized: "Could not read that file"))
            }
            sheet = nil
        }
    }

    func cancelImportPassphrase() {
        clearPendingImport()
        sheet = nil
    }

    /// However the sheet went away - a button, or a swipe that bypasses
    /// Cancel - the encrypted bytes and the typed passphrase go with it,
    /// then whatever was waiting for the sheet to close is presented.
    func sheetDismissed() {
        clearPendingImport()
        let next = afterSheet
        afterSheet = nil
        next?()
    }

    func confirmImport(_ preview: DataTransfer.ImportPreview, in context: ModelContext) {
        // Called from the preview alert's button: the result is shown once
        // that alert has gone, or its dismissal would clear it.
        do {
            try DataTransfer.apply(preview.summary, in: context)
            afterAlert = .imported(preview.summary)
        } catch {
            afterAlert = .failure(Self.message(for: error, fallback: String(localized: "Import failed")))
        }
    }

    func alertDismissed() {
        notice = nil
        guard let next = afterAlert else { return }
        afterAlert = nil
        DispatchQueue.main.async { [weak self] in self?.notice = next }
    }

    private func showPreview(of data: Data, passphrase: String?, in context: ModelContext) {
        do {
            notice = .preview(try DataTransfer.preview(data, passphrase: passphrase, in: context))
        } catch {
            fail(error, fallback: String(localized: "Could not read that file"))
        }
    }

    private func clearPendingImport() {
        pendingImport = nil
        importPassphrase = ""
        importPassphraseError = nil
    }

    private func fail(_ error: Error, fallback: String) {
        notice = .failure(Self.message(for: error, fallback: fallback))
    }

    private static func message(for error: Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}

/// The file handed to `fileExporter`.
struct DataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json] }

    var data: Data
    var contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Rows

struct MoveMyDataSections: View {
    @Environment(\.modelContext) private var modelContext
    let flow: MoveMyDataFlow

    var body: some View {
        Section {
            Button {
                flow.startEncryptedExport()
            } label: {
                Label("Export Encrypted File", systemImage: "lock.doc")
            }
            Button {
                flow.startImport()
            } label: {
                Label("Import from a File", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Move My Data")
        } footer: {
            Text("Creates one encrypted file holding your people, aircraft and flights, protected by a passphrase you choose. Use it to move everything to another device.")
        }

        Section {
            Button {
                flow.exportPlain(in: modelContext)
            } label: {
                Label("Export Unencrypted JSON", systemImage: "doc.text")
            }
        } header: {
            Text("Download a Copy of My Data (GDPR)")
        } footer: {
            Text("A plain JSON copy of everything this app holds about you, for your own records. It is NOT encrypted, and it contains passport details: keep it somewhere safe.")
        }
    }
}

// MARK: - Presentation

extension View {
    /// Every sheet, file panel and alert of the Move My Data flow. Attach once,
    /// to the Form that holds `MoveMyDataSections`.
    func moveMyDataPresentation(_ flow: MoveMyDataFlow) -> some View {
        modifier(MoveMyDataPresentation(flow: flow))
    }
}

private struct MoveMyDataPresentation: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Bindable var flow: MoveMyDataFlow

    func body(content: Content) -> some View {
        content
            .sheet(item: $flow.sheet, onDismiss: { flow.sheetDismissed() }) { sheet in
                switch sheet {
                case .exportPassphrase:
                    ExportPassphraseSheet(flow: flow)
                case .importPassphrase:
                    ImportPassphraseSheet(flow: flow)
                }
            }
            .fileExporter(
                isPresented: $flow.isExporterPresented,
                document: flow.exportFile,
                contentType: flow.exportFile?.contentType ?? .data,
                defaultFilename: flow.exportFilename
            ) { result in
                flow.exportFinished(result)
            }
            .fileImporter(
                // Any file: `.ffdata` is not a registered type, and the GDPR
                // copy is plain JSON.
                isPresented: $flow.isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                flow.filePicked(result, in: modelContext)
            }
            .alert(
                title,
                isPresented: Binding(
                    get: { flow.notice != nil },
                    set: { if !$0 { flow.alertDismissed() } }
                ),
                presenting: flow.notice
            ) { notice in
                switch notice {
                case .preview(let preview):
                    Button("Import") { flow.confirmImport(preview, in: modelContext) }
                    Button("Cancel", role: .cancel) {}
                default:
                    Button("OK", role: .cancel) {}
                }
            } message: { notice in
                switch notice {
                case .passphraseReminder(let passphrase):
                    Text("Type this on the other device to open the file. It is not stored anywhere. If you lose it, export a new file.\n\n\(passphrase)")
                case .preview(let preview):
                    Text("\(preview.summary.localizedDescription)\n\nNothing already on this device is removed unless the file says it was deleted.")
                case .imported(let summary):
                    Text(summary.localizedDescription)
                case .failure(let message):
                    Text(message)
                }
            }
    }

    private var title: Text {
        switch flow.notice {
        case .passphraseReminder: Text("Passphrase")
        case .preview: Text("Import this file?")
        case .imported: Text("Imported")
        case .failure, nil: Text("Could not do that")
        }
    }
}

// MARK: - Sheets

private struct ExportPassphraseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var flow: MoveMyDataFlow

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Passphrase", text: $flow.exportPassphrase)
                        .passphraseField()
                    Button("Suggest Another") { flow.suggestAnotherPassphrase() }
                } footer: {
                    Text("The file is encrypted with this passphrase. Keep the suggestion or type your own: you will need it on the other device.")
                }
            }
            .platformFormStyle()
            .navigationTitle("Passphrase")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { flow.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { flow.exportEncrypted(in: modelContext) }
                        .disabled(!flow.canExport)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 220)
        #endif
    }
}

private struct ImportPassphraseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var flow: MoveMyDataFlow

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Passphrase from the other device", text: $flow.importPassphrase)
                        .passphraseField()
                        .onSubmit { flow.openWithPassphrase(in: modelContext) }
                } footer: {
                    if let error = flow.importPassphraseError {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle("Passphrase")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { flow.cancelImportPassphrase() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { flow.openWithPassphrase(in: modelContext) }
                        .disabled(!flow.canOpen)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 180)
        #endif
    }
}

private extension View {
    /// A passphrase is read off one screen and typed on another: shown in the
    /// clear, never auto-corrected or auto-capitalised (case matters).
    func passphraseField() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        #else
        self
            .autocorrectionDisabled()
            .font(.body.monospaced())
        #endif
    }
}
