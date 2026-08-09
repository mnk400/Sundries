import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchIsFocused: Bool
    @State private var destinationChooserIsExpanded = false

    private var feedbackAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
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
                    isChooserExpanded: $destinationChooserIsExpanded,
                    selectDestination: { destination in
                        taskStore.selectDestination(destination)
                        withAnimation(feedbackAnimation) {
                            destinationChooserIsExpanded = false
                        }
                        searchIsFocused = true
                    },
                    addTask: {
                        withAnimation(feedbackAnimation) {
                            destinationChooserIsExpanded = false
                            taskStore.createTask()
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            TaskListView()
                .environmentObject(taskStore)

            if let completedTask = taskStore.lastCompletedTask {
                UndoBar(task: completedTask) {
                    withAnimation(feedbackAnimation) {
                        taskStore.undoLastCompletion()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .frame(width: 536, height: 548)
        .animation(feedbackAnimation, value: taskStore.parsedDraft != nil)
        .animation(feedbackAnimation, value: taskStore.lastCompletedTask?.id)
        .onChange(of: taskStore.query) { _, query in
            if query.isEmpty {
                destinationChooserIsExpanded = false
            }
        }
        .onAppear {
            taskStore.refreshTasks()
            DispatchQueue.main.async {
                searchIsFocused = true
            }
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
        HStack {
            Text("\(taskStore.openCount) open")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct QuickAddComposer: View {
    let draft: TaskDraft
    let selectedDestination: TaskDestination?
    let recentDestinations: [TaskDestination]
    let remainingDestinations: [TaskDestination]
    @Binding var isChooserExpanded: Bool
    let selectDestination: (TaskDestination) -> Void
    let addTask: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(dueDateLabel, systemImage: "calendar")
                    .lineLimit(1)

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 15)

                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        isChooserExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selectedDestination?.symbolName ?? "tray")

                        Text(selectedDestination?.compactDisplayName ?? "Choose destination")
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(isChooserExpanded ? 180 : 0))
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

            if isChooserExpanded {
                Divider()
                    .padding(.leading, 20)

                DestinationChooser(
                    recentDestinations: recentDestinations,
                    remainingDestinations: remainingDestinations,
                    selectedDestinationID: selectedDestination?.id,
                    selectDestination: selectDestination
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
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

private struct UndoBar: View {
    let task: TaskItem
    let undo: () -> Void

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
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(TaskStore())
}
