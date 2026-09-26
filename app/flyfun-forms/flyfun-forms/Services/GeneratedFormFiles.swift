import Foundation

/// Where filled forms live between `/generate` and the share sheet or mail
/// composer that hands them on.
///
/// A filled form carries passport numbers, so it must not outlive its hand-off
/// (GDPR.md §9, SECURITY_AUDIT.md §16). Each form goes in its own directory
/// under `tmp/forms/`: the file keeps the server's filename (it is what the
/// recipient sees), two forms with the same name cannot overwrite each other,
/// and everything under `root` is ours, so a sweep never touches anything else
/// in the temp directory.
///
/// Deletion happens in three places:
/// - `remove(_:)` when the flow that uses the file has finished with it;
/// - `sweep(olderThan:)` before each new form, for hand-offs that outlive the
///   sheet (macOS Open / Reveal in Finder / sharing services, macOS mail);
/// - `removeAll()` at launch and on Delete All Data.
struct GeneratedFormFiles {
    let root: URL

    static let standard = GeneratedFormFiles(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("forms", isDirectory: true)
    )

    /// How long a handed-off form may stay before the next generation sweeps
    /// it: long enough for Preview, Mail or AirDrop to have read it.
    static let handOffGrace: TimeInterval = 15 * 60

    /// Form types the server returns. Only used to clear files that builds
    /// before `tmp/forms/` wrote straight into the temp directory.
    private static let legacyExtensions: Set<String> = ["pdf", "xlsx", "docx"]

    /// Writes `data` as `filename` in a fresh directory and returns its URL.
    func write(_ data: Data, filename: String) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The server's name, but never a path: a "/" would escape the directory.
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        let url = directory.appendingPathComponent(["", ".", ".."].contains(safeName) ? "form" : safeName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Deletes a form written by `write(_:filename:)`, with its directory.
    /// Anything outside `root` is left alone.
    func remove(_ url: URL) {
        let directory = url.deletingLastPathComponent().standardizedFileURL
        guard directory.deletingLastPathComponent().path == root.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Deletes every form written more than `age` seconds ago.
    func sweep(olderThan age: TimeInterval, now: Date = Date()) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if now.timeIntervalSince(created) > age {
                try? fm.removeItem(at: entry)
            }
        }
    }

    /// Deletes every form, including those an earlier build left at the top
    /// of the temp directory.
    func removeAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: root)

        let tmp = root.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        for entry in entries where Self.legacyExtensions.contains(entry.pathExtension.lowercased()) {
            if (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
