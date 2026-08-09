import Foundation

actor MarkdownTaskSource: TaskSourceAdapter {
    nonisolated let descriptor = TaskSourceDescriptor.markdown

    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func fetchTasks() async throws -> [TaskItem] {
        try withFolderAccess {
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw MarkdownSourceError.cannotReadFolder
            }

            let markdownFiles = enumerator
                .compactMap { $0 as? URL }
                .filter { url in
                    guard url.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
                          let values = try? url.resourceValues(forKeys: resourceKeys) else {
                        return false
                    }
                    return values.isRegularFile == true && values.isHidden != true
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            return try markdownFiles.flatMap(tasks(in:))
        }
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskItem {
        try withFolderAccess {
            let inboxURL = rootURL.appendingPathComponent("Inbox.md", isDirectory: false)
            let existingContents: String

            if fileManager.fileExists(atPath: inboxURL.path) {
                existingContents = try String(contentsOf: inboxURL, encoding: .utf8)
            } else {
                existingContents = ""
            }

            let lineEnding = existingContents.contains("\r\n") ? "\r\n" : "\n"
            let prefix = existingContents.isEmpty || existingContents.hasSuffix(lineEnding) ? "" : lineEnding
            let line = makeTaskLine(from: draft)
            let updatedContents = existingContents + prefix + line + lineEnding
            try updatedContents.write(to: inboxURL, atomically: true, encoding: .utf8)

            let existingLines = existingContents.components(separatedBy: lineEnding)
            let lineNumber: Int
            if existingContents.isEmpty {
                lineNumber = 0
            } else if existingContents.hasSuffix(lineEnding) {
                lineNumber = existingLines.count - 1
            } else {
                lineNumber = existingLines.count
            }

            return task(
                from: MarkdownTaskParser.parse(line)!,
                relativePath: "Inbox.md",
                lineNumber: lineNumber,
                originalLine: line
            )
        }
    }

    func setCompleted(_ task: TaskItem, isCompleted: Bool) async throws {
        guard case let .markdown(location) = task.sourceLocation else {
            throw MarkdownSourceError.missingLocation
        }

        try withFolderAccess {
            let fileURL = rootURL.appendingPathComponent(location.relativePath, isDirectory: false)
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let lineEnding = contents.contains("\r\n") ? "\r\n" : "\n"
            var lines = contents.components(separatedBy: lineEnding)

            let targetIndex = matchingLineIndex(
                for: task,
                location: location,
                in: lines
            )

            guard let targetIndex,
                  let parsedLine = MarkdownTaskParser.parse(lines[targetIndex]) else {
                throw MarkdownSourceError.taskMovedOrChanged
            }

            lines[targetIndex] = parsedLine.replacingCompletion(with: isCompleted)
            try lines.joined(separator: lineEnding).write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func tasks(in fileURL: URL) throws -> [TaskItem] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let relativePath = relativePath(for: fileURL)
        let lineEnding = contents.contains("\r\n") ? "\r\n" : "\n"

        return contents
            .components(separatedBy: lineEnding)
            .enumerated()
            .compactMap { lineNumber, line in
                guard let parsedLine = MarkdownTaskParser.parse(line) else { return nil }
                return task(
                    from: parsedLine,
                    relativePath: relativePath,
                    lineNumber: lineNumber,
                    originalLine: line
                )
            }
    }

    private func task(
        from parsedLine: MarkdownTaskParser.ParsedLine,
        relativePath: String,
        lineNumber: Int,
        originalLine: String
    ) -> TaskItem {
        TaskItem(
            id: "markdown:\(relativePath):\(lineNumber)",
            title: parsedLine.title,
            dueDate: parsedLine.dueDate,
            dueDateIncludesTime: false,
            isCompleted: parsedLine.isCompleted,
            sourceID: descriptor.id,
            context: relativePath,
            sourceLocation: .markdown(
                MarkdownTaskLocation(
                    relativePath: relativePath,
                    lineNumber: lineNumber,
                    originalLine: originalLine
                )
            )
        )
    }

    private func makeTaskLine(from draft: TaskDraft) -> String {
        var line = "- [ ] \(draft.title)"
        if let dueDate = draft.dueDate {
            line += " 📅 \(MarkdownDueDate.format(dueDate))"
        }
        return line
    }

    private func matchingLineIndex(
        for task: TaskItem,
        location: MarkdownTaskLocation,
        in lines: [String]
    ) -> Int? {
        if lines.indices.contains(location.lineNumber),
           let parsed = MarkdownTaskParser.parse(lines[location.lineNumber]),
           parsed.title == task.title {
            return location.lineNumber
        }

        if let exactMatch = lines.firstIndex(of: location.originalLine) {
            return exactMatch
        }

        let titleMatches = lines.indices.filter { index in
            MarkdownTaskParser.parse(lines[index])?.title == task.title
        }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    private func relativePath(for fileURL: URL) -> String {
        let rootPath = rootURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func withFolderAccess<T>(_ operation: () throws -> T) throws -> T {
        let didStartAccessing = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

}

enum MarkdownTaskParser {
    struct ParsedLine {
        let title: String
        let dueDate: Date?
        let isCompleted: Bool
        let markerRange: Range<String.Index>
        let originalLine: String

        func replacingCompletion(with isCompleted: Bool) -> String {
            originalLine.replacingCharacters(
                in: markerRange,
                with: isCompleted ? "x" : " "
            )
        }
    }

    static func parse(_ line: String) -> ParsedLine? {
        let checkboxPattern = #"^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*)$"#
        guard let expression = try? NSRegularExpression(pattern: checkboxPattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ),
              let markerRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 4), in: line) else {
            return nil
        }

        let content = String(line[contentRange])
        let dueDate = parseDueDate(in: content)
        let title = removingDueDate(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return nil }

        return ParsedLine(
            title: title,
            dueDate: dueDate,
            isCompleted: line[markerRange] != " ",
            markerRange: markerRange,
            originalLine: line
        )
    }

    private static func parseDueDate(in content: String) -> Date? {
        let datePattern = #"(?:📅\s*|@due\()(\d{4}-\d{2}-\d{2})\)?"#
        guard let expression = try? NSRegularExpression(pattern: datePattern),
              let match = expression.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let dateRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return MarkdownDueDate.parse(String(content[dateRange]))
    }

    private static func removingDueDate(from content: String) -> String {
        let datePattern = #"\s*(?:📅\s*\d{4}-\d{2}-\d{2}|@due\(\d{4}-\d{2}-\d{2}\))\s*"#
        return content.replacingOccurrences(
            of: datePattern,
            with: " ",
            options: .regularExpression
        )
    }
}

private enum MarkdownDueDate {
    static func parse(_ value: String) -> Date? {
        formatter().date(from: value)
    }

    static func format(_ date: Date) -> String {
        formatter().string(from: date)
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

enum MarkdownSourceError: LocalizedError {
    case cannotReadFolder
    case missingLocation
    case taskMovedOrChanged

    var errorDescription: String? {
        switch self {
        case .cannotReadFolder:
            "Doist couldn't read that Markdown folder."
        case .missingLocation:
            "This task is missing its Markdown file location."
        case .taskMovedOrChanged:
            "The task moved or changed in its Markdown file. Refresh and try again."
        }
    }
}
