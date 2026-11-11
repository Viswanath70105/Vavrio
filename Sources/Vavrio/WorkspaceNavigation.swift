import Foundation

struct WorkspaceFile: Sendable {
    let url: URL
    let relativePath: String
}
struct WorkspaceFileScan: Sendable {
    var files: [WorkspaceFile] = []
    var truncated = false
    var unreadableDirectories = 0
}

/// On-demand, bounded filename discovery. Never reads document contents.
enum WorkspaceNavigation {
    static func scan(_ root: URL, maximumEntries: Int = 10_000, maximumFiles: Int = 2_000,
                     timeBudget: Duration = .seconds(2)) -> WorkspaceFileScan {
        var result = WorkspaceFileScan()
        let end = ContinuousClock.now + timeBudget
        let base = root.standardizedFileURL.path + "/"
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in
                result.unreadableDirectories += 1; return true
            }) else { result.unreadableDirectories = 1; return result }
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled || visited >= maximumEntries || result.files.count >= maximumFiles || ContinuousClock.now >= end {
                result.truncated = true; break
            }
            visited += 1
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                // DirectoryEnumerator does not descend through symlinks. Calling
                // skipDescendants on a non-directory can skip a later directory.
                if values.isSymbolicLink == true { continue }
                guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base) else { continue }
                result.files.append(WorkspaceFile(url: url, relativePath: String(path.dropFirst(base.count))))
            } catch { result.unreadableDirectories += 1; enumerator.skipDescendants() }
        }
        result.files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return result
    }
}

struct NavigationItem: Sendable {
    let id: String
    let title: String
    let detail: String
    var shortcut = ""
    var enabled = true
    var isOpenDocument = false
}

enum NavigationSearch {
    /// Exact and prefix filename matches lead, followed by words/path and subsequences.
    static func ranked(_ items: [NavigationItem], query: String, limit: Int = 100) -> [NavigationItem] {
        let query = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return items.compactMap { item -> (NavigationItem, Int)? in
            let title = normalized(item.title), detail = normalized(item.detail)
            let score: Int
            if query.isEmpty { score = 0 }
            else if title == query { score = 1_000 }
            else if title.hasPrefix(query) { score = 800 - min(title.count, 100) }
            else if title.contains(query) { score = 600 }
            else if detail.contains(query) { score = 400 }
            else {
                let words = query.split(whereSeparator: { $0.isWhitespace })
                if words.count > 1 && words.allSatisfy({ (title + " " + detail).contains($0) }) { score = 300 }
                else if isSubsequence(query, of: title) { score = 200 }
                else if isSubsequence(query, of: detail) { score = 100 }
                else { return nil }
            }
            return (item, score + (item.isOpenDocument ? 20 : 0))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let order = $0.0.title.localizedStandardCompare($1.0.title)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.0.detail.localizedStandardCompare($1.0.detail) == .orderedAscending
        }.prefix(max(0, limit)).map(\.0)
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func isSubsequence(_ query: String, of value: String) -> Bool {
        var iterator = value.makeIterator()
        for character in query {
            var found = false
            while let next = iterator.next() { if next == character { found = true; break } }
            if !found { return false }
        }
        return true
    }
}
