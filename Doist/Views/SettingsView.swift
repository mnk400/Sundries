import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Doist Settings")
                        .font(.title2.weight(.semibold))
                    Text("Choose where todos live and how the menu bar summarizes them.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Sources") {
                    VStack(spacing: 0) {
                        ForEach(taskStore.sources) { source in
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

                            if source.id != taskStore.sources.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }

                settingsSection("Capture") {
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

                settingsSection("Keyboard") {
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
            .padding(24)
        }
        .frame(width: 520, height: 460)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content()
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(TaskStore())
}
