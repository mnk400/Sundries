import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchIsFocused: Bool

    private var feedbackAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            if let draft = taskStore.parsedDraft {
                Divider()
                QuickAddRow(draft: draft) {
                    withAnimation(feedbackAnimation) {
                        taskStore.createTask()
                    }
                }
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
        .onAppear {
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
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
    }

    private var footer: some View {
        HStack {
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
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct QuickAddRow: View {
    let draft: TaskDraft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Label("Markdown", systemImage: "doc.plaintext")

                        if let dueDate = draft.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(draft.title)")
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
