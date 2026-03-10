#if os(iOS)
import AVFoundation
import Vision
import SwiftUI

enum ScanStatus: Equatable {
    case idle
    case scanning
    case processing
    case success
    case timeout
    case permissionDenied
}

@Observable
final class CameraOCRManager {
    var status: ScanStatus = .idle
    var result: MRZScanResult?

    let captureSession = AVCaptureSession()

    private let outputQueue = DispatchQueue(label: "mrz.camera.output", qos: .userInitiated)
    private var consecutiveMatches: [String: Int] = [:]
    private var lastPassportNumber: String?
    private var timeoutTask: Task<Void, Never>?
    private let requiredConsecutiveFrames = 5
    @ObservationIgnored private var _bufferDelegate: BufferDelegate?
    private var bufferDelegate: BufferDelegate {
        if let d = _bufferDelegate { return d }
        let d = BufferDelegate(manager: self)
        _bufferDelegate = d
        return d
    }

    func start() {
        Task {
            let granted = await requestCameraPermission()
            guard granted else {
                status = .permissionDenied
                return
            }
            setupSession()
            status = .scanning
            outputQueue.async { [captureSession] in
                captureSession.startRunning()
            }
            startTimeout()
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        outputQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    // MARK: - Camera Permission

    private func requestCameraPermission() async -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Session Setup

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(bufferDelegate, queue: outputQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Timeout

    private func startTimeout() {
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if status == .scanning {
                stop()
                status = .timeout
            }
        }
    }

    // MARK: - OCR Processing

    fileprivate nonisolated func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            self?.handleOCRResults(request)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    private nonisolated func handleOCRResults(_ request: VNRequest) {
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

        let allCandidates = observations.flatMap { $0.topCandidates(3).map(\.string) }

        // Match MRZ lines from ALL candidates (top 3 per observation)
        let mrzLines = allCandidates.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return (trimmed.count == 44 && trimmed.range(of: "^[A-Z0-9<]{44}$", options: .regularExpression) != nil)
                || (trimmed.count == 30 && trimmed.range(of: "^[A-Z0-9<]{30}$", options: .regularExpression) != nil)
        }.map { $0.trimmingCharacters(in: .whitespaces) }

        guard !mrzLines.isEmpty else { return }

        // Try TD3 (2 lines of 44)
        if let result = tryParseMRZ(mrzLines, lineLength: 44, lineCount: 2) {
            emitResult(result)
            return
        }
        // Try TD1 (3 lines of 30)
        if let result = tryParseMRZ(mrzLines, lineLength: 30, lineCount: 3) {
            emitResult(result)
            return
        }
    }

    private nonisolated func tryParseMRZ(_ lines: [String], lineLength: Int, lineCount: Int) -> MRZScanResult? {
        let filtered = lines.filter { $0.count == lineLength }
        guard filtered.count >= lineCount else { return nil }

        if lineCount == 2 {
            // Try all pairs of candidates (different OCR candidates for same line)
            for i in 0..<filtered.count {
                for j in 0..<filtered.count where j != i {
                    if let result = MRZParser.parse(lines: [filtered[i], filtered[j]]) {
                        return result
                    }
                }
            }
            // Also try same-index pair (both from top candidates)
            return MRZParser.parse(lines: Array(filtered.prefix(2)))
        } else {
            return MRZParser.parse(lines: Array(filtered.prefix(lineCount)))
        }
    }

    private nonisolated func emitResult(_ scanResult: MRZScanResult) {
        let key = scanResult.passportNumber
        Task { @MainActor [weak self] in
            guard let self, self.status == .scanning else { return }

            if self.lastPassportNumber == key {
                self.consecutiveMatches[key, default: 0] += 1
            } else {
                self.consecutiveMatches.removeAll()
                self.consecutiveMatches[key] = 1
                self.lastPassportNumber = key
            }

            if (self.consecutiveMatches[key] ?? 0) >= self.requiredConsecutiveFrames {
                self.status = .success
                self.result = scanResult
                self.stop()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

private final class BufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private unowned let manager: CameraOCRManager

    init(manager: CameraOCRManager) {
        self.manager = manager
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        manager.processFrame(sampleBuffer)
    }
}
#endif
