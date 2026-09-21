#if DEBUG
import Foundation
import OSLog

/// Answers every HTTP request the app makes while `FLYFUN_MOCK=1`.
///
/// Registered globally, it sees all traffic through `URLSession.shared`, which
/// is every call the app makes: `RollingBearerSession` (and so `FormService`
/// and the Autorouter client) defaults to it, as do the catalog sync and the
/// notice fetch. Stubbing at the HTTP layer rather than behind a protocol keeps
/// the app's real decoding, 422 parsing and status handling under test.
///
/// A request without a stub fails as if offline and is appended to
/// `unstubbed.log` in the capture directory, which the suite checks after each
/// journey, so a new network call cannot slip through unnoticed.
nonisolated final class UITestURLProtocol: URLProtocol {
    private static let logger = Logger(subsystem: "net.ro-z.flyfun-forms", category: "UITestURLProtocol")
    private static let sequence = OSAllocatedUnfairLock(initialState: 0)

    static func install() {
        URLProtocol.registerClass(UITestURLProtocol.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "http" || request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.body(of: request)
        Self.capture(request, body: body)

        guard let stub = Self.stub(for: request, url: url) else {
            Self.logger.error("No stub for \(self.request.httpMethod ?? "GET") \(url)")
            Self.appendUnstubbed("\(request.httpMethod ?? "GET") \(url.absoluteString)")
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Stubs

    private struct Stub {
        var status = 200
        var headers = ["Content-Type": "application/json"]
        var body: Data
    }

    private static func stub(for request: URLRequest, url: URL) -> Stub? {
        let path = url.pathComponents.filter { $0 != "/" }
        let method = request.httpMethod ?? "GET"

        if url.host == "maps.flyfun.aero", path.starts(with: ["api", "notifications"]), let icao = path.last {
            return json(#"{"found":false,"icao":"\#(icao)"}"#)
        }

        switch (method, path) {
        case ("GET", ["airports"]):
            // The snapshot bundled for offline launches is a real catalog.
            guard let file = Bundle.main.url(forResource: "airports", withExtension: "json"),
                  let data = try? Data(contentsOf: file) else { return nil }
            return Stub(body: data)
        case ("GET", let p) where p.count == 2 && p[0] == "airports":
            guard let detail = UITestAirportFixtures.detail[p[1]] else {
                return json(#"{"detail":"No forms available for \#(p[1])"}"#, status: 404)
            }
            return json(detail)
        case ("POST", ["generate"]):
            return generate(request)
        case ("POST", ["email-text"]):
            return json(#"""
                {"subject_en":"UI test","body_en":"UI test","subject_local":"UI test","body_local":"UI test","local_language":null}
                """#)
        case ("GET", ["api", "autorouter", "status"]):
            return json(#"{"linked":false}"#)
        default:
            return nil
        }
    }

    private static func generate(_ request: URLRequest) -> Stub {
        if UITestMode.generateStatus == 422 {
            return json(#"""
                {"detail":[{"field":"crew[0].id_number","error":"Field required","value":""}]}
                """#, status: 422)
        }
        let pdf = Data("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n".utf8)
        return Stub(
            headers: [
                "Content-Type": "application/pdf",
                "Content-Disposition": #"attachment; filename="uitest.pdf""#,
            ],
            body: pdf
        )
    }

    private static func json(_ text: String, status: Int = 200) -> Stub {
        Stub(status: status, body: Data(text.utf8))
    }

    // MARK: - Capture

    /// URLSession hands a protocol the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Writes each request body as `<n>-<METHOD>-<path>.json`, numbered in
    /// arrival order so a journey can take the latest of a kind.
    private static func capture(_ request: URLRequest, body: Data?) {
        guard let directory = UITestMode.captureDirectory, let body, !body.isEmpty,
              let url = request.url else { return }
        let n = sequence.withLock { value -> Int in
            value += 1
            return value
        }
        let path = url.pathComponents.filter { $0 != "/" }.joined(separator: "_")
        let name = String(format: "%03d-%@-%@.json", n, request.httpMethod ?? "GET", path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: directory.appendingPathComponent(name))
    }

    private static func appendUnstubbed(_ line: String) {
        guard let directory = UITestMode.captureDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("unstubbed.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
#endif
