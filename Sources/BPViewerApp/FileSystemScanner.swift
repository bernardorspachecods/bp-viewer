import Foundation

struct FileSystemScanner: Sendable {
    func scan(root: URL) -> [FileNode] {
        makeChildren(of: root, root: root)
    }

    func filter(_ nodes: [FileNode], compatibleOnly: Bool, query: String) -> [FileNode] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return nodes.compactMap {
            filterNode($0, compatibleOnly: compatibleOnly, normalizedQuery: normalizedQuery)
        }
    }

    private func makeChildren(
        of directory: URL,
        root: URL
    ) -> [FileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isReadableKey],
            options: []
        )) ?? []

        return urls
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { makeNode(at: $0, root: root) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func makeNode(
        at url: URL,
        root: URL
    ) -> FileNode? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let relativePath = relativePath(of: url, from: root)
        let kind = DocumentKind(url: url)

        if isDirectory {
            let children = makeChildren(of: url, root: root)
            return FileNode(
                id: relativePath,
                url: url,
                relativePath: relativePath,
                isDirectory: true,
                kind: .other,
                children: children
            )
        }

        return FileNode(
            id: relativePath,
            url: url,
            relativePath: relativePath,
            isDirectory: false,
            kind: kind,
            children: []
        )
    }

    private func filterNode(
        _ node: FileNode,
        compatibleOnly: Bool,
        normalizedQuery: String
    ) -> FileNode? {
        let matchesQuery = normalizedQuery.isEmpty
            || node.title.lowercased().contains(normalizedQuery)
            || node.relativePath.lowercased().contains(normalizedQuery)

        if node.isDirectory {
            let children = node.children.compactMap {
                filterNode($0, compatibleOnly: compatibleOnly, normalizedQuery: normalizedQuery)
            }
            let keepForSearch = normalizedQuery.isEmpty || matchesQuery || !children.isEmpty
            let keepForCompatibility = !compatibleOnly || !children.isEmpty

            guard keepForSearch && keepForCompatibility else { return nil }
            return FileNode(
                id: node.id,
                url: node.url,
                relativePath: node.relativePath,
                isDirectory: true,
                kind: .other,
                children: children
            )
        }

        guard !compatibleOnly || node.kind != .other else { return nil }
        guard matchesQuery else { return nil }
        return node
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "." }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
