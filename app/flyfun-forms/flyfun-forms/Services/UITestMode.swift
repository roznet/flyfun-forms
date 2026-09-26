import Foundation

/// Launch-environment switches set by the XCUI suite (`flyfun-formsUITests`).
///
/// Read only in DEBUG builds: a release build cannot be put into test mode by
/// its environment, and every switch reads as off.
nonisolated enum UITestMode {
    /// `FLYFUN_UITEST=1`: skip the sign-in gate and run on an in-memory store
    /// seeded with `UITestFixtures`.
    ///
    /// Never the CloudKit-backed store: that would write fixture passports into
    /// whatever iCloud account the simulator is signed into, and leak state
    /// from one run into the next.
    static let isActive = flag("FLYFUN_UITEST")

    /// `FLYFUN_MOCK=1`: answer every HTTP request from `UITestURLProtocol`
    /// instead of the network. A request it has no answer for fails, and is
    /// logged to the capture directory, rather than reaching a server.
    static let isMocked = flag("FLYFUN_MOCK")

    /// `FLYFUN_UITEST_CAPTURE_DIR`: where the stub writes the body of each
    /// request it answers, so a journey can check what the app sent.
    static let captureDirectory: URL? = value("FLYFUN_UITEST_CAPTURE_DIR")
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// `FLYFUN_UITEST_CLIPBOARD`: text read in place of the pasteboard.
    ///
    /// Reading the real pasteboard from another process's content raises the
    /// system "Allow Paste" prompt, which XCUI cannot answer reliably. Only the
    /// read is replaced; the parse and apply path is the real one.
    static let clipboard = value("FLYFUN_UITEST_CLIPBOARD")

    /// `FLYFUN_MOCK_GENERATE=<status>`: the status `/generate` answers with.
    /// 422 returns a validation error body; unset returns a PDF.
    static let generateStatus = value("FLYFUN_MOCK_GENERATE").flatMap(Int.init)

    /// `FLYFUN_MOCK_REQUIRE_REASON=1`: `/generate` rejects a request without a
    /// reason for visit, as the GAR does, and accepts it once it has one.
    static let requireReasonForVisit = value("FLYFUN_MOCK_REQUIRE_REASON") == "1"

    private static func value(_ key: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[key]
        #else
        return nil
        #endif
    }

    private static func flag(_ key: String) -> Bool {
        value(key) == "1"
    }
}
