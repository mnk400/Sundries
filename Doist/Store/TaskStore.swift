import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dueDateOverride = .automatic
            }
        }
    }
    @Published var defaultSourceID = TaskSourceDescriptor.markdown.id {
        didSet {
            guard defaultSourceID != oldValue else { return }
            destinations = []
            selectedDestinationID = nil
            refreshDestinations()
        }
    }
    @Published private(set) var lastCompletedTask: TaskItem?
    @Published private(set) var markdownFolderURL: URL?
    @Published private(set) var destinations: [TaskDestination] = []
    @Published private(set) var selectedDestinationID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var sourceError: String?
    @Published private var dueDateOverride = TaskDueDateOverride.automatic

    let sources: [TaskSourceDescriptor] = [.markdown, .reminders]
    private var sourceAdapters: [String: any TaskSourceAdapter] = [:]
    private var recentDestinationIDs = UserDefaults.standard.stringArray(
        forKey: DestinationPreferences.recentIDsKey
    ) ?? []

    init(tasks: [TaskItem]? = nil) {
        if let tasks {
            self.tasks = tasks
            return
        }

        self.tasks = []

        do {
            if let folderURL = try MarkdownFolderBookmark.restore() {
                markdownFolderURL = folderURL
                let source = MarkdownTaskSource(rootURL: folderURL)
                sourceAdapters[source.descriptor.id] = source
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
        guard sourceAdapters[defaultSourceID] != nil else { return nil }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        let parsedDraft = TaskDraftParser.parse(trimmedQuery, defaultSourceID: defaultSourceID)
        let dueDate: Date?

        switch dueDateOverride {
        case .automatic:
            dueDate = parsedDraft.dueDate
        case .noDate:
            dueDate = nil
        case let .date(date):
            dueDate = date
        }

        return TaskDraft(
            title: parsedDraft.title,
            dueDate: dueDate,
            sourceID: parsedDraft.sourceID
        )
    }

    var selectedDestination: TaskDestination? {
        guard let selectedDestinationID else { return nil }
        return destinations.first(where: { $0.id == selectedDestinationID })
    }

    var recentDestinations: [TaskDestination] {
        let destinationsByID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) })
        return recentDestinationIDs.compactMap { destinationsByID[$0] }
    }

    var remainingDestinations: [TaskDestination] {
        let recentIDs = Set(recentDestinationIDs)
        return destinations.filter { !recentIDs.contains($0.id) }
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
            let source = MarkdownTaskSource(rootURL: folderURL)
            sourceAdapters[source.descriptor.id] = source
            tasks = []
            destinations = []
            selectedDestinationID = nil
            sourceError = nil
            refreshTasks()
        } catch {
            sourceError = error.localizedDescription
        }
    }

    func refreshTasks() {
        guard !sourceAdapters.isEmpty, !isLoading else { return }
        Task { await reloadTasks() }
    }

    func refreshDestinations() {
        guard sourceAdapters[defaultSourceID] != nil else { return }
        Task { await reloadDestinations() }
    }

    func selectDestination(_ destination: TaskDestination) {
        guard destinations.contains(destination) else { return }
        selectedDestinationID = destination.id
        UserDefaults.standard.set(
            destination.id,
            forKey: DestinationPreferences.lastIDKey(for: destination.sourceID)
        )
    }

    func selectDueDate(_ dueDate: Date?) {
        if let dueDate {
            dueDateOverride = .date(Calendar.current.startOfDay(for: dueDate))
        } else {
            dueDateOverride = .noDate
        }
    }

    func createTask() {
        guard let draft = parsedDraft,
              let adapter = sourceAdapters[draft.sourceID],
              let destination = selectedDestination,
              destination.sourceID == draft.sourceID else { return }

        let originalQuery = query
        let originalDueDateOverride = dueDateOverride
        query = ""

        Task {
            do {
                let task = try await adapter.createTask(draft, in: destination)
                tasks.append(task)
                recordUse(of: destination)
                sourceError = nil
            } catch {
                query = originalQuery
                dueDateOverride = originalDueDateOverride
                sourceError = error.localizedDescription
            }
        }
    }

    func complete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              let adapter = sourceAdapters[task.sourceID] else { return }

        lastCompletedTask = tasks[index]
        tasks[index].isCompleted = true

        Task {
            do {
                try await adapter.setCompleted(task, isCompleted: true)
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
              let adapter = sourceAdapters[completedTask.sourceID] else {
            return
        }

        tasks[index].isCompleted = false
        lastCompletedTask = nil

        Task {
            do {
                try await adapter.setCompleted(completedTask, isCompleted: false)
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
        guard !sourceAdapters.isEmpty, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            var fetchedTasks: [TaskItem] = []
            for adapter in sourceAdapters.values {
                fetchedTasks += try await adapter.fetchTasks()
            }
            tasks = fetchedTasks
            await reloadDestinations()
            sourceError = nil
        } catch {
            sourceError = error.localizedDescription
        }
    }

    private func reloadDestinations() async {
        let sourceID = defaultSourceID
        guard let adapter = sourceAdapters[sourceID] else {
            destinations = []
            selectedDestinationID = nil
            return
        }

        do {
            let fetchedDestinations = try await adapter.fetchDestinations()
            guard sourceID == defaultSourceID else { return }

            destinations = fetchedDestinations
            selectPreferredDestination(in: fetchedDestinations, sourceID: sourceID)
            sourceError = nil
        } catch {
            guard sourceID == defaultSourceID else { return }
            destinations = []
            selectedDestinationID = nil
            sourceError = error.localizedDescription
        }
    }

    private func selectPreferredDestination(
        in availableDestinations: [TaskDestination],
        sourceID: String
    ) {
        if let selectedDestinationID,
           availableDestinations.contains(where: { $0.id == selectedDestinationID }) {
            return
        }

        let rememberedID = UserDefaults.standard.string(
            forKey: DestinationPreferences.lastIDKey(for: sourceID)
        )
        let preferredDestination = availableDestinations.first { $0.id == rememberedID }
            ?? availableDestinations.first { $0.adapterID.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame }
            ?? availableDestinations.first

        selectedDestinationID = preferredDestination?.id
    }

    private func recordUse(of destination: TaskDestination) {
        recentDestinationIDs.removeAll(where: { $0 == destination.id })
        recentDestinationIDs.insert(destination.id, at: 0)
        recentDestinationIDs = Array(recentDestinationIDs.prefix(4))
        UserDefaults.standard.set(recentDestinationIDs, forKey: DestinationPreferences.recentIDsKey)
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

private enum TaskDueDateOverride: Equatable {
    case automatic
    case noDate
    case date(Date)
}

private enum DestinationPreferences {
    static let recentIDsKey = "recentTaskDestinationIDs"

    static func lastIDKey(for sourceID: String) -> String {
        "lastTaskDestinationID.\(sourceID)"
    }
}
