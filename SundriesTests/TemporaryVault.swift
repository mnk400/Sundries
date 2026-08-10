import Foundation
@testable import Sundries

/// A throwaway folder of Markdown files for exercising `MarkdownTaskSource`
/// against a real filesystem.
///
/// Tests build their own vault rather than reading `markdown-test-vault/`, which
/// is committed as contributor sample data — a fixture that tests mutate in place
/// stops being a fixture after the first run.
struct TemporaryVault {
    let rootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SundriesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    func write(_ contents: String, to relativePath: String) throws {
        let fileURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: rootURL.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    func source() -> MarkdownTaskSource {
        MarkdownTaskSource(rootURL: rootURL)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
