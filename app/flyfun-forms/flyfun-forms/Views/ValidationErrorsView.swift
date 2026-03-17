import SwiftUI

struct ValidationErrorsView: View {
    @Environment(\.dismiss) private var dismiss
    let errors: [ServerValidationError]

    var body: some View {
        NavigationStack {
            List(errors) { error in
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.displayField)
                        .font(.headline)
                    Text(error.error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let value = error.value, !value.isEmpty {
                        Text("Sent: \"\(value)\"")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Validation Errors")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
