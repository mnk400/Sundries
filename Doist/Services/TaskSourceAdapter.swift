import Foundation

/// A storage integration translates its native task format into Doist's shared model.
/// Markdown is the first implementation; Apple Reminders can conform without changing the UI.
protocol TaskSourceAdapter: Sendable {
    var descriptor: TaskSourceDescriptor { get }

    func fetchTasks() async throws -> [TaskItem]
    func fetchDestinations() async throws -> [TaskDestination]
    func createTask(_ draft: TaskDraft, in destination: TaskDestination) async throws -> TaskItem
    func setCompleted(_ task: TaskItem, isCompleted: Bool) async throws
}
