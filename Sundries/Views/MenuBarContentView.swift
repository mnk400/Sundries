import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchIsFocused: Bool
    @State private var composerDrawer = DrawerState<ComposerPanel>()

    private var feedbackAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
    }

    private var drawerAnimation: Animation? {
        DrawerMotion.animation(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            if let draft = taskStore.parsedDraft {
                Divider()
                QuickAddComposer(
                    draft: draft,
                    selectedDestination: taskStore.selectedDestination,
                    recentDestinations: taskStore.recentDestinations,
                    remainingDestinations: taskStore.remainingDestinations,
                    drawer: $composerDrawer,
                    selectDueDate: { dueDate in
                        taskStore.selectDueDate(dueDate)
                        withAnimation(drawerAnimation) {
                            composerDrawer.dismiss()
                        }
                        searchIsFocused = true
                    },
                    selectDestination: { destination in
                        taskStore.selectDestination(destination)
                        withAnimation(drawerAnimation) {
                            composerDrawer.dismiss()
                        }
                        searchIsFocused = true
                    },
                    addTask: {
                        withAnimation(drawerAnimation) {
                            composerDrawer.dismiss()
                            taskStore.createTask()
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            TaskListView()
                .environmentObject(taskStore)

            // One slot, and a problem outranks a confirmation: a failed write is
            // the thing the user needs to know about, and the undo it would be
            // covering is stale anyway.
            if let issue = taskStore.sourceIssue {
                SourceIssueBar(
                    issue: issue,
                    openSettings: { openSettings() },
                    dismiss: {
                        withAnimation(feedbackAnimation) {
                            taskStore.dismissSourceIssue()
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let completedTask = taskStore.lastCompletedTask {
                UndoBar(
                    task: completedTask,
                    undo: {
                        withAnimation(feedbackAnimation) {
                            taskStore.undoLastCompletion()
                        }
                    },
                    dismiss: {
                        withAnimation(feedbackAnimation) {
                            taskStore.dismissCompletionFeedback()
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .frame(width: 536, height: 548)
        .animation(feedbackAnimation, value: taskStore.parsedDraft != nil)
        .animation(feedbackAnimation, value: taskStore.lastCompletedTask?.id)
        .animation(feedbackAnimation, value: taskStore.sourceIssue)
        .onChange(of: taskStore.query) { _, query in
            if query.isEmpty {
                composerDrawer.dismiss()
            }
        }
        .onAppear {
            taskStore.refreshTasks()
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .onDisappear {
            taskStore.dismissCompletionFeedback()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search or add a todo", text: $taskStore.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchIsFocused)
                .onSubmit {
                    withAnimation(feedbackAnimation) {
                        taskStore.createTask()
                    }
                }

            if !taskStore.query.isEmpty {
                Button {
                    taskStore.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(taskStore.openCount) open")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            if taskStore.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer()

            Menu {
                Button("Refresh") {
                    taskStore.refreshTasks()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Settings…") {
                    // Under LSUIElement there is no app to come forward on its
                    // own, so the Settings window otherwise opens behind whatever
                    // the user was looking at.
                    NSApplication.shared.activate()
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                // Without this there is no way out of the app at all: LSUIElement
                // means no Dock icon and no app menu, and the panel is entirely
                // custom content.
                Button("Quit Sundries") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 30)
            .help("More")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Divider() }
    }
}

private enum ComposerPanel: Hashable {
    case date
    case destination
}

private struct QuickAddComposer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let draft: TaskDraft
    let selectedDestination: TaskDestination?
    let recentDestinations: [TaskDestination]
    let remainingDestinations: [TaskDestination]
    @Binding var drawer: DrawerState<ComposerPanel>
    let selectDueDate: (Date?) -> Void
    let selectDestination: (TaskDestination) -> Void
    let addTask: () -> Void

    private var drawerAnimation: Animation? {
        DrawerMotion.animation(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(drawerAnimation) {
                        drawer.toggle(.date, replacementMotion: .backward)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")

                        Text(dueDateLabel)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(drawer.route == .date ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(dueDateStyle)
                .help("Choose a due date")

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 15)

                Button {
                    withAnimation(drawerAnimation) {
                        drawer.toggle(.destination, replacementMotion: .forward)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selectedDestination?.symbolName ?? "tray")

                        Text(selectedDestination?.compactDisplayName ?? "Choose destination")
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(drawer.route == .destination ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedDestination == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .help("Choose where to add this task")

                Spacer(minLength: 6)

                Button(action: addTask) {
                    HStack(spacing: 5) {
                        Text("Add")
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    selectedDestination == nil
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(Color.blue)
                )
                .fontWeight(.medium)
                .disabled(selectedDestination == nil)
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)

            DrawerContentHost(
                state: drawer,
                dividerLeadingPadding: 20
            ) { panel in
                Group {
                    switch panel {
                    case .date:
                        DateChooser(
                            selectedDate: draft.dueDate,
                            selectDate: selectDueDate
                        )
                    case .destination:
                        DestinationChooser(
                            recentDestinations: recentDestinations,
                            remainingDestinations: remainingDestinations,
                            selectedDestinationID: selectedDestination?.id,
                            selectDestination: selectDestination
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var dueDateLabel: String {
        guard let dueDate = draft.dueDate else { return "No date" }

        if Calendar.current.isDateInToday(dueDate) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var dueDateStyle: AnyShapeStyle {
        guard let dueDate = draft.dueDate else { return AnyShapeStyle(.secondary) }
        return dueDate < Calendar.current.startOfDay(for: .now)
            ? AnyShapeStyle(Color.red)
            : AnyShapeStyle(.secondary)
    }
}

private struct DateChooser: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation = DrawerState<DatePage>(route: .presets)

    let selectedDate: Date?
    let selectDate: (Date?) -> Void

    private let calendar = Calendar.current

    private var drawerAnimation: Animation? {
        DrawerMotion.animation(reduceMotion: reduceMotion)
    }

    var body: some View {
        DrawerContentHost(state: navigation, dividerLeadingPadding: nil) { page in
            switch page {
            case .presets:
                presetList
            case .calendar:
                calendarPicker
            }
        }
        .background(.primary.opacity(0.035))
    }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Date".uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)
                .padding(.top, 10)
                .padding(.bottom, 2)

            DateChoiceRow(
                title: "No date",
                detail: nil,
                symbolName: "calendar.badge.minus",
                isSelected: selectedDate == nil,
                action: { selectDate(nil) }
            )
            DateChoiceRow(
                title: "Today",
                detail: shortDate(today),
                symbolName: "sun.max",
                isSelected: isSelected(today),
                action: { selectDate(today) }
            )
            DateChoiceRow(
                title: "Tomorrow",
                detail: shortDate(tomorrow),
                symbolName: "sunrise",
                isSelected: isSelected(tomorrow),
                action: { selectDate(tomorrow) }
            )
            DateChoiceRow(
                title: "Next week",
                detail: shortDate(nextWeek),
                symbolName: "calendar.badge.clock",
                isSelected: isSelected(nextWeek),
                action: { selectDate(nextWeek) }
            )
            DateChoiceRow(
                title: "Choose date…",
                detail: nil,
                symbolName: "calendar",
                isSelected: false,
                showsDisclosure: true,
                action: {
                    withAnimation(drawerAnimation) {
                        navigation.navigate(to: .calendar, motion: .forward)
                    }
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var calendarPicker: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    withAnimation(drawerAnimation) {
                        navigation.navigate(to: .presets, motion: .backward)
                    }
                } label: {
                    Label("Dates", systemImage: "chevron.left")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Choose Date")
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()

                Color.clear
                    .frame(width: 44, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            DatePicker(
                "Due date",
                selection: Binding(
                    get: { selectedDate ?? today },
                    set: { selectDate($0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var today: Date {
        calendar.startOfDay(for: .now)
    }

    private var tomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: today)!
    }

    private var nextWeek: Date {
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilMonday = (9 - weekday) % 7
        let offset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(selectedDate, inSameDayAs: date)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private enum DatePage: Hashable {
    case presets
    case calendar
}

private struct DateChoiceRow: View {
    let title: String
    let detail: String?
    let symbolName: String
    let isSelected: Bool
    var showsDisclosure = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let detail {
                    Text(detail)
                        .foregroundStyle(.tertiary)
                }

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DestinationChooser: View {
    let recentDestinations: [TaskDestination]
    let remainingDestinations: [TaskDestination]
    let selectedDestinationID: String?
    let selectDestination: (TaskDestination) -> Void

    private var hasDestinations: Bool {
        !recentDestinations.isEmpty || !remainingDestinations.isEmpty
    }

    var body: some View {
        Group {
            if hasDestinations {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !recentDestinations.isEmpty {
                            destinationSection("Recent", destinations: recentDestinations)
                        }

                        if !remainingDestinations.isEmpty {
                            destinationSection(
                                recentDestinations.isEmpty ? "Files" : "All Files",
                                destinations: remainingDestinations
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 164)
            } else {
                Label("No destinations available", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
            }
        }
        .background(.primary.opacity(0.035))
    }

    private func destinationSection(
        _ title: String,
        destinations: [TaskDestination]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(destinations, id: \.id) { destination in
                DestinationRow(
                    destination: destination,
                    isSelected: destination.id == selectedDestinationID,
                    action: { selectDestination(destination) }
                )
            }
        }
    }
}

private struct DestinationRow: View {
    let destination: TaskDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                Image(systemName: destination.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(destination.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let detail = destination.detail {
                    Text(detail)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Errors used to surface only in Settings → Sources, so a failed write looked
/// from the panel like the app quietly undoing itself.
private struct SourceIssueBar: View {
    let issue: SourceIssue
    let openSettings: () -> Void
    let dismiss: () -> Void

    /// A source that needs setup is fixed in Settings; a failed read or write is
    /// worth retrying where the user already is.
    private var isRecoverableInSettings: Bool {
        issue.kind == .needsSetup
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: issue.symbolName)
                .foregroundStyle(.orange)

            Text(issue.message)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if isRecoverableInSettings {
                Button("Settings…", action: openSettings)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .fontWeight(.medium)
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .font(.callout)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }
}

private struct UndoBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var undoIsFocused: Bool
    @State private var isHovering = false
    @State private var remainingSeconds = Self.dismissDelay
    @State private var timerStartedAt: Date?
    @State private var autoDismissTask: Task<Void, Never>?

    private static let dismissDelay: TimeInterval = 6

    let task: TaskItem
    let undo: () -> Void
    let dismiss: () -> Void

    private var isPaused: Bool {
        isHovering || undoIsFocused || voiceOverEnabled
    }

    private var dismissalAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Completed “\(task.title)”")
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .fontWeight(.medium)
                .focused($undoIsFocused)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .onHover { isHovering = $0 }
        .onAppear { resetTimer() }
        .onDisappear { cancelTimer() }
        .onChange(of: task.id) { _, _ in resetTimer() }
        .onChange(of: isHovering) { _, _ in updateTimerForPauseState() }
        .onChange(of: undoIsFocused) { _, _ in updateTimerForPauseState() }
        .onChange(of: voiceOverEnabled) { _, _ in updateTimerForPauseState() }
    }

    private func resetTimer() {
        cancelTimer()
        remainingSeconds = Self.dismissDelay

        if !isPaused {
            startTimer()
        }
    }

    private func updateTimerForPauseState() {
        if isPaused {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        guard autoDismissTask == nil, remainingSeconds > 0 else { return }

        let delay = remainingSeconds
        timerStartedAt = .now
        autoDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int64(delay * 1_000)))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            autoDismissTask = nil
            timerStartedAt = nil
            remainingSeconds = 0

            withAnimation(dismissalAnimation) {
                dismiss()
            }
        }
    }

    private func pauseTimer() {
        guard let timerStartedAt else { return }

        remainingSeconds = max(
            0,
            remainingSeconds - Date.now.timeIntervalSince(timerStartedAt)
        )
        cancelTimer()
    }

    private func cancelTimer() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        timerStartedAt = nil
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(TaskStore(tasks: TaskStore.sampleTasks()))
}
