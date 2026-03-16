#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A reusable sheet that lets the user choose between camera scan, photo library,
/// or file picker, then delivers an MRZScanResult.
struct ScanDocumentSheet: View {
    let onResult: (MRZScanResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ScanMode?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFilePicker = false
    @State private var imageOCR = ImageOCRManager()

    enum ScanMode: Identifiable {
        case camera
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Scan Travel Document")
                    .font(.title2.weight(.semibold))

                Text("Scan the MRZ (machine readable zone) on a passport or ID card.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button {
                        mode = .camera
                    } label: {
                        Label("Scan with Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)

                if imageOCR.status == .processing {
                    ProgressView("Scanning image...")
                } else if imageOCR.status == .noMRZFound {
                    Label("No MRZ found in image. Try another photo.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .navigationTitle("Scan Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(item: $mode) { _ in
                MRZScannerView { result in
                    onResult(result)
                    dismiss()
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
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        imageOCR.scan(image: image)
                    }
                }
            }
            .onChange(of: imageOCR.status) { _, newStatus in
                if newStatus == .success, let result = imageOCR.result {
                    onResult(result)
                    dismiss()
                }
            }
        }
    }
}
#endif
