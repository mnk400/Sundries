import Foundation

struct TaskItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var note: String?
    var dueDate: Date?
    var dueDateIncludesTime: Bool
    var isCompleted: Bool
    var sourceID: String
    var context: String?
    var sourceLocation: TaskSourceLocation?

    init(
        id: String = UUID().uuidString,
        title: String,
        note: String? = nil,
        dueDate: Date? = nil,
        // Date-only by default. Sources that genuinely carry a time of day — an
        // issue tracker's SLA, say — opt in; showing a time nobody set is worse
        // than omitting one.
        dueDateIncludesTime: Bool = false,
        isCompleted: Bool = false,
        sourceID: String,
        context: String? = nil,
        sourceLocation: TaskSourceLocation? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.dueDateIncludesTime = dueDateIncludesTime
        self.isCompleted = isCompleted
        self.sourceID = sourceID
        self.context = context
        self.sourceLocation = sourceLocation
    }
}

enum TaskSourceLocation: Hashable, Sendable {
    case markdown(MarkdownTaskLocation)
}

enum TaskSection: Int, CaseIterable, Identifiable, Sendable {
    case overdue
    case today
    case tomorrow
    case upcoming
    case unscheduled

    var id: Self { self }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .upcoming: "Upcoming"
        case .unscheduled: "Unscheduled"
        }
    }

    func contains(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let date else { return self == .unscheduled }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfFollowingDay = calendar.date(byAdding: .day, value: 2, to: startOfToday)!

        switch self {
        case .overdue:
            return date < startOfToday
        case .today:
            return date >= startOfToday && date < startOfTomorrow
        case .tomorrow:
            return date >= startOfTomorrow && date < startOfFollowingDay
        case .upcoming:
            return date >= startOfFollowingDay
        case .unscheduled:
            return false
        }
    }
}

struct TaskSectionGroup: Identifiable, Sendable {
    let section: TaskSection
    let tasks: [TaskItem]

    var id: TaskSection { section }
}
