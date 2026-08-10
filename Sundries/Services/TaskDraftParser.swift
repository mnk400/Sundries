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

        // Day granularity, matching `TaskStore.selectDueDate` and what Markdown can
        // actually store. Inventing a time of day here meant a drafted date and the
        // same date read back from disk were different `Date` values.
        if containsWord("tomorrow", in: title) {
            dueDate = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: 1, to: now)!
            )
            title = removingWord("tomorrow", from: title)
        } else if containsWord("today", in: title) {
            dueDate = calendar.startOfDay(for: now)
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
        trailingWordRange(of: word, in: input) != nil
    }

    private static func removingWord(_ word: String, from input: String) -> String {
        guard let range = trailingWordRange(of: word, in: input) else { return input }
        return input.replacingCharacters(in: range, with: "")
    }

    /// Only a trailing date word counts as a date token. Matching it anywhere in
    /// the sentence mangles ordinary titles: "Buy today's paper" loses the word
    /// mid-string, and "Plan the Today View redesign" picks up a due date nobody
    /// asked for.
    private static func trailingWordRange(
        of word: String,
        in input: String
    ) -> Range<String.Index>? {
        input.range(
            of: "\\s+\\b\(NSRegularExpression.escapedPattern(for: word))\\b\\s*$",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
