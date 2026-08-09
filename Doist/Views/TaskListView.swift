import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var taskStore: TaskStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if taskStore.visibleSections.isEmpty {
                    ContentUnavailableView(
                        "No matching todos",
                        systemImage: "checkmark.circle",
                        description: Text("Press Return to add this as a new todo.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 74)
                } else {
                    ForEach(taskStore.visibleSections) { group in
                        taskSection(group)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
    }

    private func taskSection(_ group: TaskSectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.section.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 6)

            ForEach(group.tasks) { task in
                TaskRowView(task: task, section: group.section)
                    .environmentObject(taskStore)
            }
        }
    }
}
