#if os(iOS)
import Vision
import UIKit

enum ImageScanStatus: Equatable {
    case idle
    case processing
    case success
    case noMRZFound
}

@Observable
final class ImageOCRManager {
    var status: ImageScanStatus = .idle
    var result: MRZScanResult?

    func scan(image: UIImage) {
        guard let cgImage = image.cgImage else {
            status = .noMRZFound
            return
        }
        status = .processing
        result = nil

        Task.detached { [weak self] in
            let scanResult = Self.performOCR(on: cgImage)
            await MainActor.run {
                guard let self else { return }
                if let scanResult {
                    self.result = scanResult
                    self.status = .success
                } else {
                    self.status = .noMRZFound
                }
            }
        }
    }

    private static func performOCR(on cgImage: CGImage) -> MRZScanResult? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var ocrResult: MRZScanResult?
        let request = VNRecognizeTextRequest { request, _ in
            ocrResult = Self.extractMRZ(from: request)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        try? handler.perform([request])
        return ocrResult
    }

    private static func extractMRZ(from request: VNRequest) -> MRZScanResult? {
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return nil }

        let allCandidates = observations.flatMap { $0.topCandidates(3).map(\.string) }

        let mrzLines = allCandidates.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return (trimmed.count == 44 && trimmed.range(of: "^[A-Z0-9<]{44}$", options: .regularExpression) != nil)
                || (trimmed.count == 30 && trimmed.range(of: "^[A-Z0-9<]{30}$", options: .regularExpression) != nil)
        }.map { $0.trimmingCharacters(in: .whitespaces) }

        guard !mrzLines.isEmpty else { return nil }

        // Try TD3 (2 lines of 44)
        if let result = tryParseMRZ(mrzLines, lineLength: 44, lineCount: 2) {
            return result
        }
        // Try TD1 (3 lines of 30)
        if let result = tryParseMRZ(mrzLines, lineLength: 30, lineCount: 3) {
            return result
        }
        return nil
    }

    private static func tryParseMRZ(_ lines: [String], lineLength: Int, lineCount: Int) -> MRZScanResult? {
        let filtered = lines.filter { $0.count == lineLength }
        guard filtered.count >= lineCount else { return nil }

        if lineCount == 2 {
            for i in 0..<filtered.count {
                for j in 0..<filtered.count where j != i {
                    if let result = MRZParser.parse(lines: [filtered[i], filtered[j]]) {
                        return result
                    }
                }
            }
            return MRZParser.parse(lines: Array(filtered.prefix(2)))
        } else {
            return MRZParser.parse(lines: Array(filtered.prefix(lineCount)))
        }
    }
}
#endif
