import Foundation

enum MarkdownFolderBookmark {
    static let storageKey = "markdownFolderBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func restore() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try save(url)
        }

        return url
    }
}
