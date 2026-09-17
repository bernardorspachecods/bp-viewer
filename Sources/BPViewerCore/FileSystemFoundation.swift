import Foundation

public enum FilePathCopy {
    public static func string(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

public enum DocumentKind: String, Hashable, Sendable {
    case markdown
    case latex
    case json
    case csv
    case docx
    case pdf
    case image
    case other

    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "tex", "latex", "bib": self = .latex
        case "json": self = .json
        case "csv": self = .csv
        case "docx": self = .docx
        case "pdf": self = .pdf
        case "png", "jpg", "jpeg", "webp", "heic", "heif": self = .image
        default: self = .other
        }
    }

    public var label: String {
        switch self {
        case .markdown: "Markdown"
        case .latex: "LaTeX"
        case .json: "JSON"
        case .csv: "CSV"
        case .docx: "Word"
        case .pdf: "PDF"
        case .image: "Image"
        case .other: "Unsupported"
        }
    }
}

public struct FileNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let relativePath: String
    public let isDirectory: Bool
    public let kind: DocumentKind
    public var children: [FileNode]
    public var childrenLoaded: Bool

    public init(
        id: String,
        url: URL,
        relativePath: String,
        isDirectory: Bool,
        kind: DocumentKind,
        children: [FileNode],
        childrenLoaded: Bool
    ) {
        self.id = id
        self.url = url
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.kind = kind
        self.children = children
        self.childrenLoaded = childrenLoaded
    }

    public var title: String { url.lastPathComponent }
}

public struct FileSystemScanner: Sendable {
    public init() {}

    public func scan(root: URL) -> [FileNode] {
        makeChildren(of: root, root: root, recursive: true)
    }

    public func scanTopLevel(root: URL) -> [FileNode] {
        makeChildren(of: root, root: root, recursive: false)
    }

    public func scanChildren(of directory: URL, root: URL) -> [FileNode] {
        makeChildren(of: directory, root: root, recursive: false)
    }

    public func filter(_ nodes: [FileNode], compatibleOnly: Bool, query: String) -> [FileNode] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return nodes.compactMap {
            filterNode($0, compatibleOnly: compatibleOnly, normalizedQuery: normalizedQuery)
        }
    }

    /// Filters only the entries directly inside the scanned root. It never
    /// inspects or returns descendants, even when a directory was expanded.
    public func filterTopLevel(
        _ nodes: [FileNode],
        compatibleOnly: Bool,
        query: String
    ) -> [FileNode] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return nodes.compactMap { node in
            let matchesQuery = normalizedQuery.isEmpty
                || node.title.lowercased().contains(normalizedQuery)
                || node.relativePath.lowercased().contains(normalizedQuery)
            guard matchesQuery else { return nil }
            guard node.isDirectory || !compatibleOnly || node.kind != .other else { return nil }

            guard node.isDirectory else { return node }
            return FileNode(
                id: node.id,
                url: node.url,
                relativePath: node.relativePath,
                isDirectory: true,
                kind: .other,
                children: [],
                childrenLoaded: true
            )
        }
    }

    private func makeChildren(
        of directory: URL,
        root: URL,
        recursive: Bool
    ) -> [FileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isReadableKey],
            options: []
        )) ?? []

        return urls
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { makeNode(at: $0, root: root, recursive: recursive) }
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
        recursive: Bool
    ) -> FileNode? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let relativePath = relativePath(of: url, from: root)
        let kind = DocumentKind(url: url)

        if isDirectory {
            let children = recursive ? makeChildren(of: url, root: root, recursive: true) : []
            return FileNode(
                id: relativePath,
                url: url,
                relativePath: relativePath,
                isDirectory: true,
                kind: .other,
                children: children,
                childrenLoaded: recursive
            )
        }

        return FileNode(
            id: relativePath,
            url: url,
            relativePath: relativePath,
            isDirectory: false,
            kind: kind,
            children: [],
            childrenLoaded: true
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
            let hasUnknownChildren = !node.childrenLoaded
            let keepForSearch = normalizedQuery.isEmpty || matchesQuery || !children.isEmpty || hasUnknownChildren
            let keepForCompatibility = !compatibleOnly || hasUnknownChildren || !children.isEmpty

            guard keepForSearch && keepForCompatibility else { return nil }
            return FileNode(
                id: node.id,
                url: node.url,
                relativePath: node.relativePath,
                isDirectory: true,
                kind: .other,
                children: children,
                childrenLoaded: node.childrenLoaded
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
