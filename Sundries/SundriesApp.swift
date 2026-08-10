import AppKit
import SwiftUI

enum MenuBarCountMode: String, CaseIterable, Identifiable {
    static let storageKey = "menuBarCountMode"

    case dueToday
    case totalOpen

    var id: Self { self }

    var displayName: String {
        switch self {
        case .dueToday: "Due Today"
        case .totalOpen: "Total Open Tasks"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .dueToday: "due today"
        case .totalOpen: "open in total"
        }
    }
}

@main
struct SundriesApp: App {
    @StateObject private var taskStore = TaskStore()
    @AppStorage(MenuBarCountMode.storageKey) private var menuBarCountModeRawValue = MenuBarCountMode.dueToday.rawValue

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(taskStore)
        } label: {
            MenuBarLabelView(
                overdueCount: taskStore.overdueCount,
                secondaryCount: secondaryCount,
                secondaryCountDescription: menuBarCountMode.accessibilityDescription
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(taskStore)
        }
    }

    private var menuBarCountMode: MenuBarCountMode {
        MenuBarCountMode(rawValue: menuBarCountModeRawValue) ?? .dueToday
    }

    private var secondaryCount: Int {
        switch menuBarCountMode {
        case .dueToday: taskStore.todayCount
        case .totalOpen: taskStore.openCount
        }
    }
}

private struct MenuBarLabelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let overdueCount: Int
    let secondaryCount: Int
    let secondaryCountDescription: String

    var body: some View {
        Image(nsImage: renderedPill)
            .renderingMode(.original)
            .accessibilityLabel(
                "Sundries, \(overdueCount) overdue and \(secondaryCount) \(secondaryCountDescription)"
            )
    }

    private var renderedPill: NSImage {
        let renderer = ImageRenderer(
            content: MenuBarPillArtwork(
                overdueCount: overdueCount,
                secondaryCount: secondaryCount,
                reduceTransparency: reduceTransparency
            )
            .environment(\.colorScheme, colorScheme)
        )
        // Not `\.displayScale`: in a MenuBarExtra label it can still be 1.0 before
        // there is a window to read it from, which renders a blurry pill on a
        // Retina display and never corrects itself.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 28, height: 22))
        // Not a template: the overdue segment's red is the whole point of it, and
        // a template image would flatten it to the menu bar's tint.
        image.isTemplate = false
        return image
    }
}

private struct MenuBarPillArtwork: View {
    let overdueCount: Int
    let secondaryCount: Int
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 0) {
            if overdueCount > 0 {
                countSegment(overdueCount, isOverdue: true)
            }

            // Always drawn, even at zero. The overdue segment can hide because
            // this one anchors the pill — between them there has to be something
            // left to click, and "0 due today" is worth saying out loud.
            countSegment(secondaryCount, isOverdue: false)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .frame(height: 22)
        .background(Color.primary.opacity(reduceTransparency ? 0.28 : 0.14), in: Capsule())
        .clipShape(Capsule())
    }

    private func countSegment(_ count: Int, isOverdue: Bool) -> some View {
        Text("\(count)")
            .foregroundStyle(isOverdue ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 22, maxHeight: 22)
            .background {
                Rectangle()
                    .fill(isOverdue ? Color(red: 0.78, green: 0.24, blue: 0.28) : Color.clear)
            }
    }
}
