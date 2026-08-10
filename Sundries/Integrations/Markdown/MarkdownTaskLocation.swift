import Foundation

/// Where a task lives inside the vault, and the line it was read from.
///
/// `originalLine` is what lets a write find its task again after the file has
/// been edited elsewhere, and what a reopened task restores its marker from.
struct MarkdownTaskLocation: Hashable, Sendable {
    let relativePath: String
    let lineNumber: Int
    let originalLine: String
}
