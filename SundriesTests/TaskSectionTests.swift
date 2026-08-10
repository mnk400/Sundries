import Foundation
import Testing
@testable import Sundries

@Suite("TaskSection")
struct TaskSectionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now: Date

    init() throws {
        now = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 8, day: 9, hour: 13, minute: 30)
            )
        )
    }

    private func sections(containing date: Date?) -> [TaskSection] {
        TaskSection.allCases.filter { $0.contains(date, now: now, calendar: calendar) }
    }

    private func offsetFromStartOfToday(days: Int, seconds: Int = 0) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: startOfToday)!
            .addingTimeInterval(TimeInterval(seconds))
    }

    @Test("A date belongs to exactly one section")
    func exactlyOneSection() {
        for days in -3...3 {
            #expect(sections(containing: offsetFromStartOfToday(days: days)).count == 1)
        }
        #expect(sections(containing: nil) == [.unscheduled])
    }

    @Test("Sorts dates into the expected section")
    func sortsDatesIntoSections() {
        #expect(sections(containing: offsetFromStartOfToday(days: -1)) == [.overdue])
        #expect(sections(containing: offsetFromStartOfToday(days: 0)) == [.today])
        #expect(sections(containing: offsetFromStartOfToday(days: 1)) == [.tomorrow])
        #expect(sections(containing: offsetFromStartOfToday(days: 2)) == [.upcoming])
    }

    @Test("Boundaries fall on the later side of midnight")
    func boundariesFallOnTheLaterSide() {
        #expect(sections(containing: offsetFromStartOfToday(days: 0, seconds: -1)) == [.overdue])
        #expect(sections(containing: offsetFromStartOfToday(days: 1, seconds: -1)) == [.today])
        #expect(sections(containing: offsetFromStartOfToday(days: 2, seconds: -1)) == [.tomorrow])
    }

    /// A task due at 08:00 when it is already 13:30 is still due *today*, not
    /// overdue — sectioning is by day, not by moment.
    @Test("Earlier today is not overdue")
    func earlierTodayIsNotOverdue() {
        #expect(sections(containing: offsetFromStartOfToday(days: 0, seconds: 8 * 3600)) == [.today])
    }
}
