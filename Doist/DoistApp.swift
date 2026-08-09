import AppKit
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    let overdueCount: Int
    let todayCount: Int

    var body: some View {
        Image(nsImage: renderedPill)
            .renderingMode(.original)
            .accessibilityLabel(
                "Doist, \(overdueCount) overdue and \(todayCount) due today"
            )
    }

    private var renderedPill: NSImage {
        let renderer = ImageRenderer(
            content: MenuBarPillArtwork(
                overdueCount: overdueCount,
                todayCount: todayCount
            )
            .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = displayScale

        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 28, height: 22))
        image.isTemplate = false
        return image
    }
}

private struct MenuBarPillArtwork: View {
    let overdueCount: Int
    let todayCount: Int

    var body: some View {
        HStack(spacing: 0) {
            if overdueCount > 0 {
                countSegment(overdueCount, isOverdue: true)
            }

            countSegment(todayCount, isOverdue: false)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .frame(height: 22)
        .background(Color.primary.opacity(0.14), in: Capsule())
        .clipShape(Capsule())
    }

    private func countSegment(_ count: Int, isOverdue: Bool) -> some View {
        Text("\(count)")
            .foregroundStyle(isOverdue ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 22, maxHeight: 22)
            .background(isOverdue ? Color.red : Color.clear)
    }
}
