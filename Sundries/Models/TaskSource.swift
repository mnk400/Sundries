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

/// Lets a source classify its own errors, so the store never has to know which
/// adapter it is talking to. A Markdown folder that has gone missing and, later,
/// an expired API credential are the same shape of problem: the user has to
/// change something, not retry.
protocol SourceIssueRepresentable: Error {
    var sourceIssueKind: SourceIssue.Kind { get }
}

/// Something wrong with a configured source, attributed to the source it belongs to
/// so the UI can show it against that row rather than as a loose banner.
struct SourceIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The source cannot be used until its setup changes — a folder that no
        /// longer resolves today, a credential that expired tomorrow.
        case needsSetup
        /// Reading from or writing to an otherwise-configured source failed.
        case operationFailed
    }

    let sourceID: String
    let kind: Kind
    let message: String

    var symbolName: String {
        switch kind {
        case .needsSetup: "exclamationmark.triangle.fill"
        case .operationFailed: "exclamationmark.circle.fill"
        }
    }

    static let markdownFolderUnresolvable = SourceIssue(
        sourceID: TaskSourceDescriptor.markdown.id,
        kind: .needsSetup,
        message: "Sundries lost access to the folder you chose. Choose it again to reconnect."
    )

    /// Sources that describe their own errors get the kind they asked for.
    /// Anything else is treated as a transient failure of the operation.
    static func from(_ error: Error, sourceID: String) -> SourceIssue {
        SourceIssue(
            sourceID: sourceID,
            kind: (error as? SourceIssueRepresentable)?.sourceIssueKind ?? .operationFailed,
            message: error.localizedDescription
        )
    }
}

/// A source-owned place where a new task can be created.
///
/// Markdown exposes files, Apple Reminders can expose lists, and future adapters
/// can expose projects without the composer needing to understand any of them.
struct TaskDestination: Identifiable, Hashable, Sendable {
    let sourceID: String
    let adapterID: String
    let displayName: String
    let detail: String?
    let symbolName: String

    var id: String { "\(sourceID):\(adapterID)" }

    var compactDisplayName: String {
        guard let detail, !detail.isEmpty else { return displayName }
        return "\(detail)/\(displayName)"
    }
}
