import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published var query = ""
    @Published var defaultSourceID = TaskSourceDescriptor.markdown.id
    @Published private(set) var lastCompletedTask: TaskItem?
    @Published private(set) var markdownFolderURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var sourceError: String?

    let sources: [TaskSourceDescriptor] = [.markdown, .reminders]
    private var markdownSource: MarkdownTaskSource?

    init(tasks: [TaskItem]? = nil) {
        if let tasks {
            self.tasks = tasks
            return
        }

        self.tasks = []

        do {
            if let folderURL = try MarkdownFolderBookmark.restore() {
                markdownFolderURL = folderURL
                markdownSource = MarkdownTaskSource(rootURL: folderURL)
                refreshTasks()
            }
        } catch {
            sourceError = error.localizedDescription
        }
    }

    var overdueCount: Int {
        tasks.filter { !$0.isCompleted && TaskSection.overdue.contains($0.dueDate) }.count
    }

    var todayCount: Int {
        tasks.filter { !$0.isCompleted && TaskSection.today.contains($0.dueDate) }.count
    }

    var openCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    var parsedDraft: TaskDraft? {
        guard markdownSource != nil else { return nil }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        return TaskDraftParser.parse(trimmedQuery, defaultSourceID: defaultSourceID)
    }

    var visibleSections: [TaskSectionGroup] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleTasks = tasks.filter { task in
            guard !task.isCompleted else { return false }
            guard !trimmedQuery.isEmpty else { return true }

            return task.title.localizedCaseInsensitiveContains(trimmedQuery)
                || task.note?.localizedCaseInsensitiveContains(trimmedQuery) == true
                || task.context?.localizedCaseInsensitiveContains(trimmedQuery) == true
        }

        return TaskSection.allCases.compactMap { section in
            let sectionTasks = visibleTasks
                .filter { section.contains($0.dueDate) }
                .sorted { lhs, rhs in
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (left?, right?): left < right
                    case (nil, nil): lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    case (_?, nil): true
                    case (nil, _?): false
                    }
                }

            return sectionTasks.isEmpty ? nil : TaskSectionGroup(section: section, tasks: sectionTasks)
        }
    }

    func source(for id: String) -> TaskSourceDescriptor {
        sources.first(where: { $0.id == id }) ?? .markdown
    }

    func configureMarkdownFolder(_ folderURL: URL) {
        do {
            try MarkdownFolderBookmark.save(folderURL)
            markdownFolderURL = folderURL.standardizedFileURL
            markdownSource = MarkdownTaskSource(rootURL: folderURL)
            tasks = []
            sourceError = nil
            refreshTasks()
        } catch {
            sourceError = error.localizedDescription
        }
    }

    func refreshTasks() {
        guard markdownSource != nil, !isLoading else { return }
        Task { await reloadTasks() }
    }

    func createTask() {
        guard let draft = parsedDraft, let markdownSource else { return }

        query = ""

        Task {
            do {
                let task = try await markdownSource.createTask(draft)
                tasks.append(task)
                sourceError = nil
            } catch {
                query = draft.title
                sourceError = error.localizedDescription
            }
        }
    }

    func complete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              let markdownSource else { return }

        lastCompletedTask = tasks[index]
        tasks[index].isCompleted = true

        Task {
            do {
                try await markdownSource.setCompleted(task, isCompleted: true)
                sourceError = nil
            } catch {
                if let currentIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[currentIndex].isCompleted = false
                }
                lastCompletedTask = nil
                sourceError = error.localizedDescription
            }
        }
    }

    func undoLastCompletion() {
        guard let completedTask = lastCompletedTask,
              let index = tasks.firstIndex(where: { $0.id == completedTask.id }),
              let markdownSource else {
            return
        }

        tasks[index].isCompleted = false
        lastCompletedTask = nil

        Task {
            do {
                try await markdownSource.setCompleted(completedTask, isCompleted: false)
                sourceError = nil
            } catch {
                if let currentIndex = tasks.firstIndex(where: { $0.id == completedTask.id }) {
                    tasks[currentIndex].isCompleted = true
                }
                sourceError = error.localizedDescription
            }
        }
    }

    func dismissCompletionFeedback() {
        lastCompletedTask = nil
    }

    private func reloadTasks() async {
        guard let markdownSource, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try await markdownSource.fetchTasks()
            sourceError = nil
        } catch {
            sourceError = error.localizedDescription
        }
    }

    private static func sampleTasks(calendar: Calendar = .current) -> [TaskItem] {
        func date(dayOffset: Int, hour: Int = 17) -> Date {
            let shiftedDate = calendar.date(byAdding: .day, value: dayOffset, to: .now)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shiftedDate)!
        }

        return [
            TaskItem(
                title: "Send the project recap",
                note: "Capture decisions and open questions",
                dueDate: date(dayOffset: -2),
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Work/Launch.md"
            ),
            TaskItem(
                title: "Review the menu bar prototype",
                dueDate: date(dayOffset: 0, hour: 11),
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Inbox.md"
            ),
            TaskItem(
                title: "Write down plugin capability ideas",
                note: "Markdown first, Apple Reminders second",
                dueDate: date(dayOffset: 0, hour: 16),
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Doist.md"
            ),
            TaskItem(
                title: "Choose a folder for Markdown tasks",
                dueDate: date(dayOffset: 1, hour: 10),
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Inbox.md"
            ),
            TaskItem(
                title: "Explore keyboard-first navigation",
                dueDate: date(dayOffset: 5, hour: 9),
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Ideas.md"
            ),
            TaskItem(
                title: "Define a lossless Markdown editing policy",
                sourceID: TaskSourceDescriptor.markdown.id,
                context: "Doist.md"
            )
        ]
    }
}
