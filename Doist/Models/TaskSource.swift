import Foundation

struct TaskSourceCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let read = Self(rawValue: 1 << 0)
    static let create = Self(rawValue: 1 << 1)
    static let complete = Self(rawValue: 1 << 2)
    static let dueDates = Self(rawValue: 1 << 3)
    static let notes = Self(rawValue: 1 << 4)
    static let tags = Self(rawValue: 1 << 5)
    static let locations = Self(rawValue: 1 << 6)
}

struct TaskSourceDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let symbolName: String
    let capabilities: TaskSourceCapabilities
    let availability: Availability

    enum Availability: String, Hashable, Sendable {
        case prototype = "Prototype"
        case planned = "Planned"
    }

    static let markdown = TaskSourceDescriptor(
        id: "markdown",
        displayName: "Markdown",
        symbolName: "doc.plaintext",
        capabilities: [.read, .create, .complete, .dueDates, .notes, .tags],
        availability: .prototype
    )

    static let reminders = TaskSourceDescriptor(
        id: "apple-reminders",
        displayName: "Apple Reminders",
        symbolName: "checklist",
        capabilities: [.read, .create, .complete, .dueDates, .notes, .tags, .locations],
        availability: .planned
    )
}
