import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            SourcesSettingsPane()
                .tabItem { Label("Sources", systemImage: "tray.full") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettingsPane: View {
    @AppStorage(MenuBarCountMode.storageKey) private var menuBarCountMode = MenuBarCountMode.dueToday.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Menu bar count", selection: $menuBarCountMode) {
                    ForEach(MenuBarCountMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            } footer: {
                Text("Shown beside the overdue count in the menu bar.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(height: 130)
    }
}

private struct SourcesSettingsPane: View {
    @EnvironmentObject private var taskStore: TaskStore

    var body: some View {
        Form {
            Section {
                ForEach(taskStore.sources) { source in
                    sourceRow(source)
                }
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .frame(height: 230)
    }

    /// The checkmark column only earns its space once there is a choice to make.
    private var showsDefaultSelection: Bool {
        taskStore.sources.filter(isUsable).count > 1
    }

    private func isUsable(_ source: TaskSourceDescriptor) -> Bool {
        guard source.availability == .prototype else { return false }
        guard source.id == TaskSourceDescriptor.markdown.id else { return true }
        return taskStore.markdownFolderURL != nil
    }

    private func sourceRow(_ source: TaskSourceDescriptor) -> some View {
        let usable = isUsable(source)
        let isDefault = source.id == taskStore.defaultSourceID

        return HStack(spacing: 12) {
            if showsDefaultSelection {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(usable && isDefault ? 1 : 0)
                    .frame(width: 14)
            }

            Image(systemName: source.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(usable ? Color.accentColor : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)

                if let issue = issue(for: source) {
                    Label(issue.message, systemImage: issue.symbolName)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(subtitle(for: source))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            trailingControl(source)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture {
            guard showsDefaultSelection, usable else { return }
            taskStore.defaultSourceID = source.id
        }
    }

    @ViewBuilder
    private func trailingControl(_ source: TaskSourceDescriptor) -> some View {
        if source.id == TaskSourceDescriptor.markdown.id {
            Button(taskStore.markdownFolderURL == nil ? "Choose Folder…" : "Change…") {
                chooseMarkdownFolder()
            }
        } else {
            Text(source.availability.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    /// Issues are shown against the source they belong to, so the footer stays
    /// free for guidance rather than doubling as an error banner.
    private func issue(for source: TaskSourceDescriptor) -> SourceIssue? {
        guard let sourceIssue = taskStore.sourceIssue,
              sourceIssue.sourceID == source.id else { return nil }
        return sourceIssue
    }

    @ViewBuilder
    private var footer: some View {
        if showsDefaultSelection {
            Text("New tasks are added to the checked source unless you pick another destination.")
                .settingsFootnote()
        } else if taskStore.markdownFolderURL == nil, taskStore.sourceIssue == nil {
            Text("Choose a folder of Markdown files to start capturing tasks.")
                .settingsFootnote()
        }
    }

    private func subtitle(for source: TaskSourceDescriptor) -> String {
        guard source.id == TaskSourceDescriptor.markdown.id else {
            return "A future connection to the system Reminders database"
        }

        guard let folderURL = taskStore.markdownFolderURL else {
            return "Plain checkbox lists in files and folders"
        }

        return (folderURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
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
}

private extension View {
    func settingsFootnote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
        .environmentObject(TaskStore())
}
