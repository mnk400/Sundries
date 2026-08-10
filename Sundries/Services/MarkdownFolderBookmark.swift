import Foundation

enum MarkdownFolderBookmark {
    static let storageKey = "markdownFolderBookmark"

    /// What the stored bookmark resolved to.
    ///
    /// "Never chosen" and "chosen but no longer reachable" look the same to the
    /// rest of the app — both leave it without a folder — but only the second is
    /// something to tell the user about.
    enum StoredFolder: Equatable {
        case notConfigured
        case folder(URL)
        case unresolvable
    }

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Resolves without throwing. App-scoped bookmarks are tied to the app's code
    /// signature, so an ad-hoc rebuild can invalidate a perfectly good folder
    /// choice — a state the user recovers from by picking the folder again, not
    /// an error worth a Cocoa message.
    static func restore() -> StoredFolder {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .notConfigured
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return .unresolvable
        }

        if isStale {
            try? save(url)
        }

        return .folder(url)
    }
}
