import SwiftUI

@main
struct DoistApp: App {
    @StateObject private var taskStore = TaskStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(taskStore)
        } label: {
            MenuBarLabelView(
                overdueCount: taskStore.overdueCount,
                todayCount: taskStore.todayCount
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(taskStore)
        }
    }
}

private struct MenuBarLabelView: View {
    let overdueCount: Int
    let todayCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")

            if overdueCount > 0 || todayCount > 0 {
                Text("\(overdueCount)  \(todayCount)")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(
            "Doist, \(overdueCount) overdue and \(todayCount) due today"
        )
    }
}
