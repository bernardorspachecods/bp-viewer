import Foundation

struct FileSystemScanner {
    func scan(root: URL, compatibleOnly: Bool, query: String) -> [FileNode] {
        makeChildren(of: root, root: root, compatibleOnly: compatibleOnly, query: query)
    }

    private func makeChildren(
        of directory: URL,
        root: URL,
        compatibleOnly: Bool,
        query: String
    ) -> [FileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isReadableKey],
            options: []
        )) ?? []

        return urls
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { makeNode(at: $0, root: root, compatibleOnly: compatibleOnly, query: query) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func makeNode(
        at url: URL,
        root: URL,
        compatibleOnly: Bool,
        query: String
    ) -> FileNode? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let relativePath = relativePath(of: url, from: root)
        let kind = DocumentKind(url: url)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchesQuery = normalizedQuery.isEmpty
            || url.lastPathComponent.lowercased().contains(normalizedQuery)
            || relativePath.lowercased().contains(normalizedQuery)

        if isDirectory {
            let children = makeChildren(
                of: url,
                root: root,
                compatibleOnly: compatibleOnly,
                query: query
            )
            let keepForSearch = normalizedQuery.isEmpty || matchesQuery || !children.isEmpty
            let keepForCompatibility = !compatibleOnly || !children.isEmpty

            guard keepForSearch && keepForCompatibility else { return nil }
            return FileNode(
                id: relativePath,
                url: url,
                relativePath: relativePath,
                isDirectory: true,
                kind: .other,
                children: children
            )
        }

        guard !compatibleOnly || kind != .other else { return nil }
        guard matchesQuery else { return nil }

        return FileNode(
            id: relativePath,
            url: url,
            relativePath: relativePath,
            isDirectory: false,
            kind: kind,
            children: []
        )
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "." }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
