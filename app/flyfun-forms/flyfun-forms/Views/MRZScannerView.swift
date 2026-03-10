#if os(iOS)
import SwiftUI

struct MRZScannerView: View {
    let onResult: (MRZScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraOCRManager()

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            // Semi-transparent overlay with cutout guide
            GeometryReader { geo in
                let guideHeight = geo.size.height * 0.2
                let guideY = geo.size.height * 0.65
                let guideInset: CGFloat = 20

                ZStack {
                    // Darkened overlay
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .ignoresSafeArea()

                    // Clear cutout for MRZ guide zone
                    RoundedRectangle(cornerRadius: 12)
                        .frame(width: geo.size.width - guideInset * 2, height: guideHeight)
                        .position(x: geo.size.width / 2, y: guideY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                // Guide border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.7), lineWidth: 2)
                    .frame(width: geo.size.width - guideInset * 2, height: guideHeight)
                    .position(x: geo.size.width / 2, y: guideY)
            }

            // Status and controls
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                    Spacer()
                }

                // Debug overlay
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OCR debug (\(camera.debugLines.count) lines)")
                            .font(.caption2.bold())
                        ForEach(Array(camera.debugLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                        }
                    }
                    .foregroundStyle(.green)
                    .padding(8)
                }
                .frame(maxHeight: 150)
                .background(.black.opacity(0.7))

                Spacer()

                statusView
                    .padding(.bottom, 60)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.status) { _, newStatus in
            if newStatus == .success, let result = camera.result {
                onResult(result)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch camera.status {
        case .idle, .scanning:
            Label("Hold passport MRZ in the guide area", systemImage: "viewfinder")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())

        case .processing:
            Label("Scanning...", systemImage: "text.viewfinder")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())

        case .success:
            Label("Scanned!", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())

        case .timeout:
            VStack(spacing: 12) {
                Text("Having trouble reading the MRZ")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Button("Enter details manually") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

        case .permissionDenied:
            VStack(spacing: 12) {
                Text("Camera access is required to scan documents")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
#endif
