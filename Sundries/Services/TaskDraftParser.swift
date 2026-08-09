import Foundation

struct TaskDraft: Equatable, Sendable {
    let title: String
    let dueDate: Date?
    let sourceID: String
}

enum TaskDraftParser {
    static func parse(
        _ input: String,
        defaultSourceID: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskDraft {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = trimmedInput
        var dueDate: Date?

        if containsWord("tomorrow", in: title) {
            dueDate = calendar.date(
                bySettingHour: 17,
                minute: 0,
                second: 0,
                of: calendar.date(byAdding: .day, value: 1, to: now)!
            )
            title = removingWord("tomorrow", from: title)
        } else if containsWord("today", in: title) {
            dueDate = calendar.date(
                bySettingHour: 17,
                minute: 0,
                second: 0,
                of: now
            )
            title = removingWord("today", from: title)
        }

        let cleanTitle = title
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))

        return TaskDraft(
            title: cleanTitle.isEmpty ? trimmedInput : cleanTitle,
            dueDate: dueDate,
            sourceID: defaultSourceID
        )
    }

    private static func containsWord(_ word: String, in input: String) -> Bool {
        input.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func removingWord(_ word: String, from input: String) -> String {
        input.replacingOccurrences(
            of: "\\s*\\b\(NSRegularExpression.escapedPattern(for: word))\\b\\s*",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
