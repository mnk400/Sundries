import Foundation
import Testing
@testable import Sundries

@Suite("MarkdownTaskParser")
struct MarkdownTaskParserTests {
    @Test("Reads an open task")
    func readsOpenTask() throws {
        let parsed = try #require(MarkdownTaskParser.parse("- [ ] Pay rent"))
        #expect(parsed.title == "Pay rent")
        #expect(parsed.isCompleted == false)
        #expect(parsed.dueDate == nil)
    }

    @Test("Reads a completed task in either case", arguments: ["- [x] Pay rent", "- [X] Pay rent"])
    func readsCompletedTask(line: String) throws {
        let parsed = try #require(MarkdownTaskParser.parse(line))
        #expect(parsed.isCompleted)
        #expect(parsed.title == "Pay rent")
    }

    @Test("Accepts every bullet character", arguments: ["-", "*", "+"])
    func acceptsBulletCharacters(bullet: String) throws {
        let parsed = try #require(MarkdownTaskParser.parse("\(bullet) [ ] Pay rent"))
        #expect(parsed.title == "Pay rent")
    }

    @Test("Accepts indented tasks")
    func acceptsIndentedTasks() throws {
        let parsed = try #require(MarkdownTaskParser.parse("    - [ ] Pay rent"))
        #expect(parsed.title == "Pay rent")
    }

    @Test("Strips the due date out of the title", arguments: [
        "- [ ] Pay rent 📅 2026-08-09",
        "- [ ] Pay rent @due(2026-08-09)"
    ])
    func stripsDueDateFromTitle(line: String) throws {
        let parsed = try #require(MarkdownTaskParser.parse(line))
        #expect(parsed.title == "Pay rent")

        let dueDate = try #require(parsed.dueDate)
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: dueDate)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 9)
    }

    @Test("Ignores lines that are not tasks", arguments: [
        "Just a paragraph",
        "- A plain bullet",
        "# A heading",
        "",
        "- [ ] ",
        "- [ ] 📅 2026-08-09"
    ])
    func ignoresNonTaskLines(line: String) {
        #expect(MarkdownTaskParser.parse(line) == nil)
    }

    /// The guarantee that keeps a vault safe: toggling completion may change the
    /// marker character and nothing else — not indentation, not the bullet, not
    /// trailing whitespace, not the date annotation.
    @Test("Toggling completion changes only the marker character")
    func togglingCompletionChangesOnlyTheMarker() throws {
        let line = "  * [ ] Pay rent 📅 2026-08-09  "
        let parsed = try #require(MarkdownTaskParser.parse(line))

        let completed = parsed.replacingMarker(with: MarkdownTaskParser.completedMarker)
        #expect(completed == "  * [x] Pay rent 📅 2026-08-09  ")

        let reparsed = try #require(MarkdownTaskParser.parse(completed))
        #expect(reparsed.isCompleted)
        #expect(reparsed.title == parsed.title)
        #expect(reparsed.replacingMarker(with: MarkdownTaskParser.openMarker) == line)
    }

    // MARK: - Alternate checkbox states

    /// Scope doc §4.2. These used to fail the checkbox pattern outright and
    /// vanish from the list, which reads as data loss rather than as filtering.
    @Test("Reads unrecognized markers as open tasks", arguments: ["/", ">", "?", "!"])
    func readsUnrecognizedMarkersAsOpen(marker: String) throws {
        let parsed = try #require(MarkdownTaskParser.parse("- [\(marker)] Pay rent"))
        #expect(parsed.title == "Pay rent")
        #expect(parsed.isCompleted == false)
    }

    /// `-` is the widely used "cancelled" convention, so it is settled rather
    /// than open — surfacing every cancelled task as outstanding would be its
    /// own kind of wrong.
    @Test("Treats cancelled as settled")
    func treatsCancelledAsSettled() throws {
        let parsed = try #require(MarkdownTaskParser.parse("- [-] Pay rent"))
        #expect(parsed.isCompleted)
    }

    @Test("Keeps the original marker available for round-tripping")
    func keepsOriginalMarker() throws {
        #expect(try #require(MarkdownTaskParser.parse("- [/] Pay rent")).marker == "/")
        #expect(try #require(MarkdownTaskParser.parse("- [ ] Pay rent")).marker == " ")
    }

    @Test("Still ignores wiki links and Markdown links", arguments: [
        "- [[A wiki link]]",
        "- [x](https://example.com)",
        "- [ ](https://example.com)"
    ])
    func ignoresLinkSyntax(line: String) {
        #expect(MarkdownTaskParser.parse(line) == nil)
    }
}
