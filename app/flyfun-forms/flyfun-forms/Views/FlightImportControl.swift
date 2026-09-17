import SwiftUI

/// The import row on the new-flight form: one button that opens the list of
/// methods.
///
/// It used to lead with the method the context ranked first, labelled with what
/// it would do ("Repeat EGTF → LFAT"). That put the same choice in two places —
/// the primary and the list behind the chevron — and made the row's meaning
/// change under the pilot as the clipboard or the flight history changed.
/// Ranking still decides the order inside the list, where it costs nothing to
/// be wrong.
struct FlightImportControl: View {
    let context: FlightImportContext
    /// Called when the button is tapped. The parent owns the method list, so
    /// the list and the method's own picker are never two sheets presented from
    /// the same view in one turn (SwiftUI drops the second transition).
    let onBrowse: () -> Void

    var body: some View {
        Button {
            onBrowse()
        } label: {
            Label(String(localized: "Import…"), systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("importButton")
    }
}

/// The full list of import methods, with unavailable ones greyed and explained
/// rather than hidden.
struct FlightImportMethodList: View {
    let context: FlightImportContext
    let onSelect: (FlightImportMethod) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(FlightImportMethod.rankedOrder(for: context)) { method in
                let availability = method.availability(in: context)
                Button {
                    onSelect(method)
                } label: {
                    row(method, availability: availability)
                }
                .disabled(!availability.isAvailable)
            }
            .navigationTitle(String(localized: "Import Flight"))
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
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    @ViewBuilder
    private func row(
        _ method: FlightImportMethod, availability: FlightImportMethod.Availability
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: method.systemImage)
                .frame(width: 24)
                .foregroundStyle(availability.isAvailable ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(method.title)
                if case .unavailable(let reason) = availability {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(method.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
