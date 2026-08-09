import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage(MenuBarCountMode.storageKey) private var menuBarCountMode = MenuBarCountMode.dueToday.rawValue
    @State private var selectedPane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 190)
        } detail: {
            detailPane(selectedPane ?? .general)
        }
        .frame(width: 700, height: 440)
    }

    @ViewBuilder
    private func detailPane(_ pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(pane.title)
                .font(.title2.weight(.semibold))

            switch pane {
            case .general:
                preferenceGroup {
                    HStack {
                        Text("Default source")
                        Spacer()
                        Picker("Default source", selection: $taskStore.defaultSourceID) {
                            ForEach(taskStore.sources.filter { $0.availability == .prototype }) { source in
                                Text(source.displayName).tag(source.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(12)
                }

            case .sources:
                preferenceGroup {
                    VStack(spacing: 0) {
                        ForEach(taskStore.sources) { source in
                            sourceRow(source)

                            if source.id != taskStore.sources.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }

            case .menuBar:
                preferenceGroup {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neutral count")
                            Text("Choose what the neutral menu-bar number represents.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("Neutral count", selection: $menuBarCountMode) {
                            ForEach(MenuBarCountMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    .padding(12)
                }

            case .shortcuts:
                preferenceGroup {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Doist")
                            Text("Global shortcut wiring is the next infrastructure step.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Coming next")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sourceRow(_ source: TaskSourceDescriptor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: source.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(source.id == TaskSourceDescriptor.markdown.id ? Color.blue : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .fontWeight(.medium)
                Text(source.id == TaskSourceDescriptor.markdown.id
                     ? "Plain checkbox lists in files and folders"
                     : "A future connection to the system Reminders database")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(source.availability.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(source.availability == .prototype ? Color.blue : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(12)
    }

    private func preferenceGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                .quaternary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case sources
    case menuBar
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .sources: "Sources"
        case .menuBar: "Menu Bar"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .sources: "tray.full"
        case .menuBar: "menubar.rectangle"
        case .shortcuts: "command"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(TaskStore())
}
