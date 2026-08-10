# Sundries

Sundries is a native macOS menu-bar tasks and to-do management companion. Sundries gathers tasks from various places, and has a well defined adapter interface to be extendable to various sources.

Long term sundries aims to add task management support for: Raw Markdown, Apple Reminders, Jira, Linear, <insert-your-task-management-app-here>. The "support" implies not the complete featureset but a sufficient amount

> Sundries is currently an early alpha, only markdown support is working right now. Data formats and behavior may change

![](docs/ui-screenshot.png)

## Current features

- Liquid Glass menu-bar interface for reviewing and capturing tasks
- Overdue and due-today or total-open menu-bar counts
- Destination selection when adding a Markdown task
- Inline due-date presets and calendar selection
- Completion feedback with Undo

## Requirements

- macOS 26 or later
- Xcode 26 or later
- Swift 6

## Development

Open `Sundries.xcodeproj` and run the `Sundries` scheme.

## License

Sundries is available under the [MIT License](LICENSE).
