import Foundation

actor MarkdownTaskSource: TaskSourceAdapter {
    nonisolated let descriptor = TaskSourceDescriptor.markdown

    /// The URL exactly as the bookmark resolved it. Security-scoped access is tied
    /// to this instance, so deriving a new URL from it — even one pointing at the
    /// same folder — is not guaranteed to carry the scope.
    private let accessURL: URL
    /// A standardized copy, used only for path comparison and relative paths.
    private let rootURL: URL
    /// Both the chosen path and its symlink-resolved form. A vault reached
    /// through a symlink enumerates to resolved paths that share neither prefix
    /// with the path the user picked, and a relative path that cannot be derived
    /// stops being unique.
    private let rootPathCandidates: [String]
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        accessURL = rootURL

        let standardizedURL = rootURL.standardizedFileURL
        self.rootURL = standardizedURL

        let resolvedPath = standardizedURL.resolvingSymlinksInPath().path
        rootPathCandidates = standardizedURL.path == resolvedPath
            ? [standardizedURL.path]
            : [standardizedURL.path, resolvedPath]
    }

    func fetchTasks() async throws -> [TaskItem] {
        return try withFolderAccess {
            try markdownFiles().flatMap(tasks(in:))
        }
    }

    func fetchDestinations() async throws -> [TaskDestination] {
        try withFolderAccess {
            var files = try markdownFiles()
            let inboxURL = rootURL.appendingPathComponent("Inbox.md", isDirectory: false)

            if !files.contains(where: { $0.standardizedFileURL == inboxURL.standardizedFileURL }) {
                files.insert(inboxURL, at: 0)
            }

            return files.map(destination(for:))
        }
    }

    func createTask(_ draft: TaskDraft, in destination: TaskDestination) async throws -> TaskItem {
        guard destination.sourceID == descriptor.id else {
            throw MarkdownSourceError.invalidDestination
        }

        return try withFolderAccess {
            let fileURL = try fileURL(for: destination)
            let existingContents: String

            if fileManager.fileExists(atPath: fileURL.path) {
                existingContents = try String(contentsOf: fileURL, encoding: .utf8)
            } else {
                existingContents = ""
            }

            var document = MarkdownDocument(contents: existingContents)
            let line = makeTaskLine(from: draft)
            let lineNumber = document.appendLine(line)
            try document.text.write(to: fileURL, atomically: true, encoding: .utf8)

            return task(
                from: MarkdownTaskParser.parse(line)!,
                relativePath: destination.adapterID,
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
            var document = MarkdownDocument(contents: contents)

            let targetIndex = matchingLineIndex(
                for: task,
                location: location,
                in: document.lines
            )

            guard let targetIndex,
                  let parsedLine = MarkdownTaskParser.parse(document.lines[targetIndex]) else {
                throw MarkdownSourceError.taskMovedOrChanged
            }

            document.replaceLine(
                at: targetIndex,
                with: parsedLine.replacingMarker(
                    with: marker(isCompleted: isCompleted, reopeningTo: location)
                )
            )
            try document.text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Completing always writes `x`. Reopening restores whatever the line looked
    /// like before Sundries touched it, so undoing a completion on an in-progress
    /// `[/]` task does not quietly demote it to `[ ]`.
    private func marker(isCompleted: Bool, reopeningTo location: MarkdownTaskLocation) -> Character {
        guard !isCompleted else { return MarkdownTaskParser.completedMarker }

        guard let previousMarker = MarkdownTaskParser.parse(location.originalLine)?.marker,
              !MarkdownTaskParser.isResolved(previousMarker) else {
            return MarkdownTaskParser.openMarker
        }

        return previousMarker
    }

    private func tasks(in fileURL: URL) throws -> [TaskItem] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let relativePath = relativePath(for: fileURL)

        return MarkdownDocument(contents: contents)
            .lines
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

    private func markdownFiles() throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MarkdownSourceError.folderUnavailable
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard url.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
                      let values = try? url.resourceValues(forKeys: resourceKeys) else {
                    return false
                }
                return values.isRegularFile == true && values.isHidden != true
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func destination(for fileURL: URL) -> TaskDestination {
        let relativePath = relativePath(for: fileURL)
        let parentPath = (relativePath as NSString).deletingLastPathComponent

        return TaskDestination(
            sourceID: descriptor.id,
            adapterID: relativePath,
            displayName: fileURL.lastPathComponent,
            detail: parentPath == "." || parentPath.isEmpty ? nil : parentPath,
            symbolName: "doc.plaintext"
        )
    }

    private func fileURL(for destination: TaskDestination) throws -> URL {
        let pathExtension = (destination.adapterID as NSString).pathExtension
        guard pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else {
            throw MarkdownSourceError.invalidDestination
        }

        let fileURL = rootURL
            .appendingPathComponent(destination.adapterID, isDirectory: false)
            .standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path

        guard fileURL.path.hasPrefix(rootPath + "/") else {
            throw MarkdownSourceError.invalidDestination
        }

        return fileURL
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
        let filePath = fileURL.standardizedFileURL.path

        for rootPath in rootPathCandidates where filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }

        // Deliberately not the file name: two files in different folders would
        // then share a relative path, and so an identity — completing one would
        // flip the other. A full path keeps them distinct and makes any later
        // write fail loudly instead of hitting the wrong file.
        return filePath
    }

    private func withFolderAccess<T>(_ operation: () throws -> T) throws -> T {
        let didStartAccessing = accessURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                accessURL.stopAccessingSecurityScopedResource()
            }
        }

        // One reachability check covers reading, writing, and destination lookup.
        // Without it a deleted folder reads as an empty one, and `fetchDestinations`
        // still offers its synthesized Inbox.md — a destination pointing at nothing,
        // which turns into a confusing write failure naming a file rather than the
        // folder that actually went missing.
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MarkdownSourceError.folderUnavailable
        }

        return try operation()
    }

}

/// A Markdown file split into lines, remembering each line's own terminator.
///
/// Picking one line ending for the whole file and splitting on it loses tasks in
/// a file with mixed endings: the lone-`\n` runs collapse into a single line the
/// parser cannot match, and those tasks silently disappear. Tracking terminators
/// per line also means rewriting a file puts back exactly what was there.
struct MarkdownDocument {
    private(set) var lines: [String]
    private var terminators: [String]

    init(contents: String) {
        var lines: [String] = []
        var terminators: [String] = []
        var lineStart = contents.startIndex
        var index = contents.startIndex

        while index < contents.endIndex {
            let character = contents[index]
            let next = contents.index(after: index)

            if Self.isLineBreak(character) {
                lines.append(String(contents[lineStart..<index]))
                terminators.append(String(character))
                lineStart = next
            }

            index = next
        }

        // Anything after the final terminator is a last, unterminated line. When
        // the file ends with a terminator this is empty and adds no phantom line.
        let trailing = contents[lineStart...]
        if !trailing.isEmpty {
            lines.append(String(trailing))
            terminators.append("")
        }

        self.lines = lines
        self.terminators = terminators
    }

    var text: String {
        zip(lines, terminators).reduce(into: "") { result, line in
            result += line.0
            result += line.1
        }
    }

    mutating func replaceLine(at index: Int, with line: String) {
        lines[index] = line
    }

    /// Appends a line, terminating the previous last line first if the file did
    /// not end with a newline. Returns the index the new line landed on.
    mutating func appendLine(_ line: String) -> Int {
        let terminator = preferredTerminator

        if let lastIndex = terminators.indices.last, terminators[lastIndex].isEmpty {
            terminators[lastIndex] = terminator
        }

        lines.append(line)
        terminators.append(terminator)
        return lines.count - 1
    }

    private var preferredTerminator: String {
        terminators.first(where: { !$0.isEmpty }) ?? "\n"
    }

    /// Swift treats CRLF as a single `Character`, so all three common endings are
    /// covered without any look-ahead.
    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }
}

enum MarkdownTaskParser {
    static let openMarker: Character = " "
    static let completedMarker: Character = "x"

    /// Markers that mean the task is settled and belongs out of the list.
    ///
    /// `x` is done and `-` is the widely used "cancelled" convention. Everything
    /// else counts as open — including `/` (in progress) and `>` (forwarded) —
    /// because refusing to display a marker we do not recognize reads as data
    /// loss rather than as filtering. Source-defined status arrives in 0.2.
    static func isResolved(_ marker: Character) -> Bool {
        marker == "x" || marker == "X" || marker == "-"
    }

    struct ParsedLine {
        let title: String
        let dueDate: Date?
        let marker: Character
        let markerRange: Range<String.Index>
        let originalLine: String

        var isCompleted: Bool { MarkdownTaskParser.isResolved(marker) }

        func replacingMarker(with marker: Character) -> String {
            originalLine.replacingCharacters(in: markerRange, with: String(marker))
        }
    }

    /// Compiled once rather than per line. Every line of every Markdown file used
    /// to pay for three regex compilations, which dominated the cost of reading a
    /// vault of any real size.
    private static let checkboxExpression = try! NSRegularExpression(
        pattern: #"^(\s*[-*+]\s+\[)([^\]])(\]\s+)(.*)$"#
    )
    private static let dueDateExpression = try! NSRegularExpression(
        pattern: #"(?:📅\s*|@due\()(\d{4}-\d{2}-\d{2})\)?"#
    )
    private static let dueDateStrippingExpression = try! NSRegularExpression(
        pattern: #"\s*(?:📅\s*\d{4}-\d{2}-\d{2}|@due\(\d{4}-\d{2}-\d{2}\))\s*"#
    )

    static func parse(_ line: String) -> ParsedLine? {
        guard let match = checkboxExpression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ),
              let markerRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 4), in: line),
              let marker = line[markerRange].first else {
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
            marker: marker,
            markerRange: markerRange,
            originalLine: line
        )
    }

    private static func parseDueDate(in content: String) -> Date? {
        guard let match = dueDateExpression.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let dateRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return MarkdownDueDate.parse(String(content[dateRange]))
    }

    private static func removingDueDate(from content: String) -> String {
        dueDateStrippingExpression.stringByReplacingMatches(
            in: content,
            range: NSRange(content.startIndex..., in: content),
            withTemplate: " "
        )
    }
}

private enum MarkdownDueDate {
    /// Built once instead of per date, and never mutated afterwards.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        formatter.date(from: value)
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

enum MarkdownSourceError: LocalizedError, SourceIssueRepresentable {
    /// Moved, renamed, deleted, or on a volume that is no longer mounted.
    case folderUnavailable
    case invalidDestination
    case missingLocation
    case taskMovedOrChanged

    var errorDescription: String? {
        switch self {
        case .folderUnavailable:
            "Sundries can't reach the folder you chose. It may have been moved, renamed, or deleted."
        case .invalidDestination:
            "That Markdown destination is no longer available."
        case .missingLocation:
            "This task is missing its Markdown file location."
        case .taskMovedOrChanged:
            "The task moved or changed in its Markdown file. Refresh and try again."
        }
    }

    var sourceIssueKind: SourceIssue.Kind {
        switch self {
        case .folderUnavailable:
            .needsSetup
        case .invalidDestination, .missingLocation, .taskMovedOrChanged:
            .operationFailed
        }
    }
}
