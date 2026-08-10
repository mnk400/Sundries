import Foundation
import Testing
@testable import Sundries

@Suite("MarkdownTaskSource")
struct MarkdownTaskSourceTests {
    @Test("Finds tasks across nested folders and records where they came from")
    func findsTasksAcrossNestedFolders() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Top level task\n", to: "Inbox.md")
        try vault.write("- [ ] Nested task\n", to: "Work/Launch.md")
        try vault.write("Not a task file.\n", to: "Notes/Prose.md")

        let tasks = try await vault.source().fetchTasks()

        #expect(tasks.count == 2)
        #expect(tasks.first { $0.title == "Top level task" }?.context == "Inbox.md")
        #expect(tasks.first { $0.title == "Nested task" }?.context == "Work/Launch.md")
    }

    @Test("Offers Inbox.md as a destination even when it does not exist yet")
    func offersInboxDestination() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Nested task\n", to: "Work/Launch.md")

        let destinations = try await vault.source().fetchDestinations()

        #expect(destinations.contains { $0.adapterID == "Inbox.md" })
        #expect(destinations.contains { $0.adapterID == "Work/Launch.md" })
    }

    @Test("Appends a new task without disturbing existing content")
    func appendsWithoutDisturbingContent() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        let original = """
        # Inbox

        Some prose that must survive.

        - [ ] Existing task

        """
        try vault.write(original, to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        let draft = TaskDraft(
            title: "Brand new task",
            dueDate: nil,
            sourceID: TaskSourceDescriptor.markdown.id
        )
        _ = try await source.createTask(draft, in: destination)

        #expect(try vault.read("Inbox.md") == original + "- [ ] Brand new task\n")
    }

    @Test("Separates an appended task from a file with no trailing newline")
    func separatesAppendedTaskFromUnterminatedFile() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Existing task", to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        _ = try await source.createTask(
            TaskDraft(title: "Second task", dueDate: nil, sourceID: TaskSourceDescriptor.markdown.id),
            in: destination
        )

        #expect(try vault.read("Inbox.md") == "- [ ] Existing task\n- [ ] Second task\n")
    }

    /// The guarantee that protects a real vault: completing a task rewrites the
    /// file, so everything that is not the checkbox marker must come back byte
    /// for byte — prose, blank lines, headings, blockquotes, trailing newline.
    @Test("Completing a task changes only the checkbox marker")
    func completingChangesOnlyTheMarker() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        let original = """
        # Inbox

        Some prose that must survive.

        - [ ] First task 📅 2026-08-09
        - [ ] Second task
            - [ ] An indented child

        > A blockquote with a - [ ] lookalike inside it.

        """
        try vault.write(original, to: "Inbox.md")

        let source = vault.source()
        let tasks = try await source.fetchTasks()
        let second = try #require(tasks.first { $0.title == "Second task" })
        try await source.setCompleted(second, isCompleted: true)

        #expect(
            try vault.read("Inbox.md") == original.replacingOccurrences(
                of: "- [ ] Second task",
                with: "- [x] Second task"
            )
        )
    }

    @Test("Completion round-trips back to the original file")
    func completionRoundTrips() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        let original = "- [ ] First task\n- [ ] Second task\n"
        try vault.write(original, to: "Inbox.md")

        let source = vault.source()
        let task = try #require(try await source.fetchTasks().first { $0.title == "First task" })

        try await source.setCompleted(task, isCompleted: true)
        try await source.setCompleted(task, isCompleted: false)

        #expect(try vault.read("Inbox.md") == original)
    }

    @Test("Finds a task that moved to a different line")
    func findsTaskThatMoved() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Move me\n", to: "Inbox.md")

        let source = vault.source()
        let task = try #require(try await source.fetchTasks().first)

        // Someone edits the file in another app, pushing the task down.
        try vault.write("# A heading added later\n\n- [ ] Move me\n", to: "Inbox.md")
        try await source.setCompleted(task, isCompleted: true)

        #expect(try vault.read("Inbox.md") == "# A heading added later\n\n- [x] Move me\n")
    }

    @Test("Refuses to guess when the task is gone")
    func refusesToGuessWhenTaskIsGone() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Delete me\n", to: "Inbox.md")

        let source = vault.source()
        let task = try #require(try await source.fetchTasks().first)

        try vault.write("- [ ] Something else entirely\n", to: "Inbox.md")

        await #expect(throws: MarkdownSourceError.self) {
            try await source.setCompleted(task, isCompleted: true)
        }
        #expect(try vault.read("Inbox.md") == "- [ ] Something else entirely\n")
    }

    @Test("Rejects a destination that escapes the vault")
    func rejectsEscapingDestination() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        let destination = TaskDestination(
            sourceID: TaskSourceDescriptor.markdown.id,
            adapterID: "../Escaped.md",
            displayName: "Escaped.md",
            detail: nil,
            symbolName: "doc.plaintext"
        )

        await #expect(throws: MarkdownSourceError.self) {
            try await vault.source().createTask(
                TaskDraft(title: "Nope", dueDate: nil, sourceID: TaskSourceDescriptor.markdown.id),
                in: destination
            )
        }
    }

    // MARK: - Dates

    /// The payoff of a single date convention: a date chosen in the composer and
    /// the same date read back off disk are the same `Date`, so a new task does
    /// not quietly change how it reads after the next refresh.
    @Test("A drafted due date survives the round trip unchanged")
    func draftedDueDateSurvivesRoundTrip() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("", to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        let draft = TaskDraftParser.parse(
            "File the paperwork tomorrow",
            defaultSourceID: TaskSourceDescriptor.markdown.id
        )
        let draftedDueDate = try #require(draft.dueDate)

        let created = try await source.createTask(draft, in: destination)
        #expect(created.dueDate == draftedDueDate)
        #expect(created.dueDateIncludesTime == false)

        let fetched = try #require(try await source.fetchTasks().first)
        #expect(fetched.dueDate == draftedDueDate)
    }

    @Test("Writes a due date Markdown can actually store")
    func writesStorableDueDate() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("", to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        let dueDate = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 8, day: 9)
            )
        )
        _ = try await source.createTask(
            TaskDraft(
                title: "File the paperwork",
                dueDate: dueDate,
                sourceID: TaskSourceDescriptor.markdown.id
            ),
            in: destination
        )

        #expect(try vault.read("Inbox.md") == "- [ ] File the paperwork 📅 2026-08-09\n")
    }

    // MARK: - Missing folder

    /// A folder that has gone missing must not read as a folder with no tasks.
    /// It used to: `fetchTasks` returned an empty list and `fetchDestinations`
    /// still offered its synthesized `Inbox.md`, so the composer would let you
    /// add a task and only then fail, blaming the file rather than the folder.
    @Test("Reports a missing folder rather than reporting no tasks")
    func reportsMissingFolder() async throws {
        let vault = try TemporaryVault()
        try vault.write("- [ ] A task\n", to: "Inbox.md")

        let source = vault.source()
        #expect(try await source.fetchTasks().count == 1)

        vault.destroy()

        await #expect(throws: MarkdownSourceError.folderUnavailable) {
            try await source.fetchTasks()
        }
        await #expect(throws: MarkdownSourceError.folderUnavailable) {
            try await source.fetchDestinations()
        }
    }

    @Test("Refuses to write into a missing folder")
    func refusesToWriteIntoMissingFolder() async throws {
        let vault = try TemporaryVault()
        try vault.write("- [ ] A task\n", to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        let task = try #require(try await source.fetchTasks().first)

        vault.destroy()

        await #expect(throws: MarkdownSourceError.folderUnavailable) {
            try await source.createTask(
                TaskDraft(title: "Nope", dueDate: nil, sourceID: TaskSourceDescriptor.markdown.id),
                in: destination
            )
        }
        await #expect(throws: MarkdownSourceError.folderUnavailable) {
            try await source.setCompleted(task, isCompleted: true)
        }
    }

    @Test("Treats a file chosen where a folder belongs as unavailable")
    func treatsFileAsUnavailableFolder() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("not a folder", to: "Notes.md")
        let source = MarkdownTaskSource(
            rootURL: vault.rootURL.appendingPathComponent("Notes.md", isDirectory: false)
        )

        await #expect(throws: MarkdownSourceError.folderUnavailable) {
            try await source.fetchTasks()
        }
    }

    // MARK: - Line endings

    /// Scope doc §4.3. Choosing one line ending for the whole file used to
    /// collapse the lone-\n runs into a single unparseable line, silently
    /// dropping those tasks.
    @Test("Reads every task from a file with mixed line endings")
    func readsMixedLineEndings() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] First\r\n- [ ] Second\n- [ ] Third\r\n", to: "Mixed.md")
        let tasks = try await vault.source().fetchTasks()

        #expect(tasks.count == 3)
        #expect(Set(tasks.map(\.title)) == ["First", "Second", "Third"])
    }

    @Test("Preserves each line's own ending when rewriting a mixed file")
    func preservesMixedLineEndingsOnWrite() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        let original = "- [ ] First\r\n- [ ] Second\n- [ ] Third\r\n"
        try vault.write(original, to: "Mixed.md")

        let source = vault.source()
        let second = try #require(try await source.fetchTasks().first { $0.title == "Second" })
        try await source.setCompleted(second, isCompleted: true)

        #expect(
            try vault.read("Mixed.md") == "- [ ] First\r\n- [x] Second\n- [ ] Third\r\n"
        )
    }

    @Test("Keeps a CRLF file on CRLF when appending")
    func keepsCRLFWhenAppending() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [ ] Existing\r\n", to: "Inbox.md")

        let source = vault.source()
        let destination = try #require(
            try await source.fetchDestinations().first { $0.adapterID == "Inbox.md" }
        )
        _ = try await source.createTask(
            TaskDraft(title: "Appended", dueDate: nil, sourceID: TaskSourceDescriptor.markdown.id),
            in: destination
        )

        #expect(try vault.read("Inbox.md") == "- [ ] Existing\r\n- [ ] Appended\r\n")
    }

    // MARK: - Alternate checkbox states

    @Test("Surfaces in-progress tasks rather than hiding them")
    func surfacesInProgressTasks() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write(
            "- [ ] Open\n- [/] In progress\n- [>] Forwarded\n- [x] Done\n- [-] Cancelled\n",
            to: "Inbox.md"
        )

        let tasks = try await vault.source().fetchTasks()
        let open = tasks.filter { !$0.isCompleted }.map(\.title)

        #expect(Set(open) == ["Open", "In progress", "Forwarded"])
        #expect(tasks.count == 5)
    }

    /// Undoing a completion must put back the state the line actually had, not
    /// flatten every reopened task to `[ ]`.
    @Test("Reopening restores the marker the task started with")
    func reopeningRestoresOriginalMarker() async throws {
        let vault = try TemporaryVault()
        defer { vault.destroy() }

        try vault.write("- [/] In progress\n", to: "Inbox.md")

        let source = vault.source()
        let task = try #require(try await source.fetchTasks().first)

        try await source.setCompleted(task, isCompleted: true)
        #expect(try vault.read("Inbox.md") == "- [x] In progress\n")

        try await source.setCompleted(task, isCompleted: false)
        #expect(try vault.read("Inbox.md") == "- [/] In progress\n")
    }
}
