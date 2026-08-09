import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let task: TaskItem
    let section: TaskSection

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.25, extraBounce: 0)) {
                    taskStore.complete(task)
                }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let note = task.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    if let dueDate = task.dueDate {
                        Text(dueLabel(for: dueDate, includesTime: task.dueDateIncludesTime))
                            .foregroundStyle(section == .overdue ? Color.red : Color.secondary)
                    }

                    if task.dueDate != nil, task.context != nil {
                        Text("·")
                    }

                    if let context = task.context {
                        Label(context, systemImage: taskStore.source(for: task.sourceID).symbolName)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(isHovering ? 0.055 : 0))
                .padding(.horizontal, 7)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private func dueLabel(for date: Date, includesTime: Bool) -> String {
        if !includesTime {
            switch section {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .overdue, .upcoming:
                return date.formatted(date: .abbreviated, time: .omitted)
            case .unscheduled:
                return ""
            }
        }

        return switch section {
        case .overdue, .upcoming:
            date.formatted(date: .abbreviated, time: .shortened)
        case .today:
            "Today, \(date.formatted(date: .omitted, time: .shortened))"
        case .tomorrow:
            "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        case .unscheduled:
            ""
        }
    }
}
