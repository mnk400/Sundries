import Foundation
import Testing
@testable import Sundries

@Suite("TaskDraftParser")
struct TaskDraftParserTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now: Date

    init() throws {
        now = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 8, day: 9, hour: 9)
            )
        )
    }

    private func parse(_ input: String) -> TaskDraft {
        TaskDraftParser.parse(
            input,
            defaultSourceID: TaskSourceDescriptor.markdown.id,
            now: now,
            calendar: calendar
        )
    }

    private func dayOffset(of date: Date) -> Int? {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day
    }

    @Test("Reads a trailing date word", arguments: [
        ("Call mom tomorrow", "Call mom", 1),
        ("Call mom Tomorrow", "Call mom", 1),
        ("Ship the release today", "Ship the release", 0),
        ("Call mom, tomorrow", "Call mom", 1)
    ])
    func readsTrailingDateWord(input: String, expectedTitle: String, expectedOffset: Int) throws {
        let draft = parse(input)
        #expect(draft.title == expectedTitle)
        #expect(dayOffset(of: try #require(draft.dueDate)) == expectedOffset)
    }

    /// Scope doc §4.1. Matching the word anywhere in the sentence used to produce
    /// "Buy 's paper" and attach a due date nobody asked for.
    @Test("Leaves date words alone when they are part of the title", arguments: [
        "Buy today's paper",
        "Plan the Today View redesign",
        "Reschedule tomorrow's standup",
        "Write the README"
    ])
    func leavesNonTrailingDateWordsAlone(input: String) {
        let draft = parse(input)
        #expect(draft.title == input)
        #expect(draft.dueDate == nil)
    }

    @Test("A bare date word stays a title rather than becoming an empty task")
    func bareDateWordStaysATitle() {
        let draft = parse("tomorrow")
        #expect(draft.title == "tomorrow")
        #expect(draft.dueDate == nil)
    }

    @Test("Collapses stray whitespace in the title")
    func collapsesStrayWhitespace() {
        #expect(parse("  Call   the    dentist  ").title == "Call the dentist")
    }

    @Test("Carries the default source through")
    func carriesDefaultSource() {
        #expect(parse("Call mom").sourceID == TaskSourceDescriptor.markdown.id)
    }

    /// Drafted dates are day-granular, matching `TaskStore.selectDueDate` and what
    /// Markdown can store. The parser used to invent 17:00, so the same day held
    /// two different `Date` values depending on how it was chosen.
    @Test("Produces start-of-day dates", arguments: ["Call mom today", "Call mom tomorrow"])
    func producesStartOfDayDates(input: String) throws {
        let dueDate = try #require(parse(input).dueDate)
        #expect(dueDate == calendar.startOfDay(for: dueDate))
    }
}
