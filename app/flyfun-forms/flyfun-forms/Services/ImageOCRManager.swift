import Vision
import PDFKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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

    #if os(iOS)
    func scan(image: UIImage) {
        guard let cgImage = image.cgImage else {
            status = .noMRZFound
            return
        }
        scan(cgImage: cgImage)
    }
    #else
    func scan(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            status = .noMRZFound
            return
        }
        scan(cgImage: cgImage)
    }
    #endif

    /// Scan a file URL (PDF or image) for MRZ data.
    /// Handles security-scoped resource access, PDF rasterization, and image loading.
    func scan(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                status = .noMRZFound
                return
            }
            scanPDFPages(pdf)
            return
        } else {
            // Load image data fully before releasing security-scoped access
            guard let data = try? Data(contentsOf: url) else {
                status = .noMRZFound
                return
            }
            #if os(iOS)
            guard let image = UIImage(data: data) else {
                status = .noMRZFound
                return
            }
            scan(image: image)
            #else
            guard let image = NSImage(data: data) else {
                status = .noMRZFound
                return
            }
            scan(image: image)
            #endif
        }
    }

    #if os(macOS)
    /// Render a PDF page to a CGImage at the given size and scale.
    private func renderPDFPage(_ page: PDFPage, size: NSSize, scale: CGFloat) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
    #endif

    /// Try each page of a PDF until MRZ is found.
    private func scanPDFPages(_ pdf: PDFDocument) {
        status = .processing
        result = nil
        let scale: CGFloat = 300.0 / 72.0

        Task.detached { [weak self] in
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let pageRect = page.bounds(for: .mediaBox)
                let width = pageRect.width * scale
                let height = pageRect.height * scale

                let cgImage: CGImage?
                #if os(iOS)
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
                let uiImage = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    ctx.cgContext.translateBy(x: 0, y: height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                cgImage = uiImage.cgImage
                #else
                cgImage = self?.renderPDFPage(page, size: NSSize(width: width, height: height), scale: scale)
                #endif

                guard let cgImage else { continue }

                if let scanResult = Self.performOCR(on: cgImage) {
                    await MainActor.run {
                        self?.result = scanResult
                        self?.status = .success
                    }
                    return
                }
            }
            await MainActor.run {
                self?.status = .noMRZFound
            }
        }
    }

    func scan(cgImage: CGImage) {
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

    /// Normalize common OCR misreads in MRZ text.
    /// Vision often reads the `<` filler as `«`, `‹`, `K`, or similar characters.
    private static func normalizeMRZ(_ text: String) -> String {
        var result = text.uppercased()
        // Replace common OCR confusions for the < filler character
        for char: Character in ["«", "‹", "〈", "＜", "❮", "‹"] {
            result = result.map { $0 == char ? "<" : $0 }.reduce("", { $0 + String($1) })
        }
        // Also replace K when it appears in sequences typical of filler (K repeated or at end)
        // but only if the line looks like it could be MRZ
        return result
    }

    private static func extractMRZ(from request: VNRequest) -> MRZScanResult? {
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return nil }

        let allCandidates = observations.flatMap { $0.topCandidates(3).map(\.string) }

        let mrzLines = allCandidates.compactMap { line -> String? in
            let normalized = normalizeMRZ(line.trimmingCharacters(in: .whitespaces))

            // Exact match
            if (normalized.count == 44 && normalized.range(of: "^[A-Z0-9<]{44}$", options: .regularExpression) != nil)
                || (normalized.count == 30 && normalized.range(of: "^[A-Z0-9<]{30}$", options: .regularExpression) != nil) {
                return normalized
            }

            // Vision often truncates trailing < fillers or misreads them.
            // Strip any non-MRZ trailing chars, then pad with < to expected length.
            let cleaned = String(normalized.prefix(while: { $0.isLetter || $0.isNumber || $0 == "<" }))
            guard cleaned.count >= 20,
                  cleaned.range(of: "^[A-Z0-9<]+$", options: .regularExpression) != nil else {
                return nil
            }

            // TD3 line 1 starts with P<, I<, or V< — accept shorter strings
            // TD3 line 2 is mostly digits — accept if ≥28 chars
            if cleaned.count <= 44 && (cleaned.hasPrefix("P<") || cleaned.hasPrefix("I<") || cleaned.hasPrefix("V<") || cleaned.count >= 28) {
                return cleaned.padding(toLength: 44, withPad: "<", startingAt: 0)
            }
            // TD1: pad to 30 if plausible
            if cleaned.count <= 30 {
                return cleaned.padding(toLength: 30, withPad: "<", startingAt: 0)
            }

            return nil
        }

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
            return nil
        } else {
            return MRZParser.parse(lines: Array(filtered.prefix(lineCount)))
        }
    }
}
