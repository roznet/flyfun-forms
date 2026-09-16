import SwiftUI

/// The import row on the new-flight form: one primary button showing the
/// method the current context ranks first, and a chevron that always opens the
/// full list.
///
/// The primary never hides a method — the list is one tap away and shows every
/// method, including the ones that aren't usable yet, with the reason.
struct FlightImportControl: View {
    let context: FlightImportContext
    /// Called with the ranked method when the primary button is tapped.
    let onSelect: (FlightImportMethod) -> Void
    /// Called when the chevron is tapped. The parent owns the method list, so
    /// the list and the method's own picker are never two sheets presented from
    /// the same view in one turn (SwiftUI drops the second transition).
    let onBrowse: () -> Void

    private var primary: FlightImportMethod { FlightImportMethod.ranked(for: context) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSelect(primary)
            } label: {
                Label(
                    FlightImportMethod.primaryLabel(for: primary, context: context),
                    systemImage: primary.systemImage
                )
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("importPrimaryButton")

            Spacer(minLength: 0)

            Button {
                onBrowse()
            } label: {
                Label(String(localized: "More import options"), systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("importMoreButton")
        }
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
            List(FlightImportMethod.allCases) { method in
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
