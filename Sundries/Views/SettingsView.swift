import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @AppStorage(MenuBarCountMode.storageKey) private var menuBarCountMode = MenuBarCountMode.dueToday.rawValue
    @State private var selectedPane: SettingsPane? = .sources

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            detailPane(selectedPane ?? .sources)
        }
        .frame(width: 700, height: 440)
    }

    @ViewBuilder
    private func detailPane(_ pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(pane.title)
                .font(.title2.weight(.semibold))

            switch pane {
            case .sources:
                VStack(alignment: .leading, spacing: 14) {
                    preferenceGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default source")
                                Text("New tasks are added here unless another source is specified.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Picker("Default source", selection: $taskStore.defaultSourceID) {
                                ForEach(taskStore.sources) { source in
                                    Text(source.displayName)
                                        .tag(source.id)
                                        .disabled(source.availability != .prototype)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        .padding(12)
                    }

                    Text("Available Sources")
                        .font(.headline)

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

                    if let sourceError = taskStore.sourceError {
                        Label(sourceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
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
                            Text("Open Sundries")
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
                Text(sourceDescription(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if source.id == TaskSourceDescriptor.markdown.id {
                Button(taskStore.markdownFolderURL == nil ? "Choose Folder…" : "Change…") {
                    chooseMarkdownFolder()
                }
            } else {
                Text(source.availability.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(12)
    }

    private func sourceDescription(_ source: TaskSourceDescriptor) -> String {
        guard source.id == TaskSourceDescriptor.markdown.id else {
            return "A future connection to the system Reminders database"
        }

        return taskStore.markdownFolderURL?.path(percentEncoded: false)
            ?? "Plain checkbox lists in files and folders"
    }

    private func chooseMarkdownFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Markdown Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = taskStore.markdownFolderURL

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        taskStore.configureMarkdownFolder(folderURL)
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
    case sources
    case menuBar
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .sources: "Sources"
        case .menuBar: "Menu Bar"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
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
