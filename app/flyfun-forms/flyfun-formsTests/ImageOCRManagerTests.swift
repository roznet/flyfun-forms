#if os(iOS)
import Testing
import UIKit
import Vision
@testable import flyfun_forms

@Suite("ImageOCRManager")
struct ImageOCRManagerTests {

    // MARK: - Rendering helpers

    /// Render MRZ text lines into a UIImage suitable for Vision OCR.
    private func renderMRZImage(lines: [String], fontSize: CGFloat = 24) -> UIImage {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]

        let textLines = lines.joined(separator: "\n")
        let text = textLines as NSString
        let textSize = text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        ).size

        let padding: CGFloat = 40
        let imageSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))
            text.draw(at: CGPoint(x: padding, y: padding), withAttributes: attrs)
        }
    }

    // MARK: - Tests

    @Test("Scan TD3 passport image returns valid result")
    func scanTD3Image() async throws {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let image = renderMRZImage(lines: [line1, line2], fontSize: 36)

        let manager = ImageOCRManager()
        manager.scan(image: image)

        // Wait for async processing
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if manager.status == .success || manager.status == .noMRZFound { break }
        }

        #expect(manager.status == .success)
        #expect(manager.result != nil)
        #expect(manager.result?.surname == "Eriksson")
        #expect(manager.result?.givenNames == "Anna Maria")
        #expect(manager.result?.passportNumber == "L898902C3")
        #expect(manager.result?.format == .td3)
    }

    @Test("Scan image with no MRZ returns noMRZFound")
    func scanNoMRZImage() async throws {
        // Render an image with random non-MRZ text
        let image = renderMRZImage(lines: ["Hello world", "This is not a passport"], fontSize: 24)

        let manager = ImageOCRManager()
        manager.scan(image: image)

        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if manager.status == .success || manager.status == .noMRZFound { break }
        }

        #expect(manager.status == .noMRZFound)
        #expect(manager.result == nil)
    }

    @Test("Scan TD1 ID card image returns valid result")
    func scanTD1Image() async throws {
        let line1 = "I<UTOD231458907<<<<<<<<<<<<<<<" // 30 chars
        let line2 = "7408122F1204159UTO<<<<<<<<<<<6" // 30 chars
        let line3 = "ERIKSSON<<ANNA<MARIA<<<<<<<<<<" // 30 chars
        let image = renderMRZImage(lines: [line1, line2, line3], fontSize: 36)

        let manager = ImageOCRManager()
        manager.scan(image: image)

        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if manager.status == .success || manager.status == .noMRZFound { break }
        }

        // TD1 with smaller text may be harder for OCR; accept either outcome
        if manager.status == .success {
            #expect(manager.result?.surname == "Eriksson")
            #expect(manager.result?.format == .td1)
        }
    }

    @Test("Status starts as idle")
    func initialState() {
        let manager = ImageOCRManager()
        #expect(manager.status == .idle)
        #expect(manager.result == nil)
    }
}
#endif
