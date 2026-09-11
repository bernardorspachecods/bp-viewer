import Foundation

public enum DocumentKind: String, Hashable, Sendable {
    case markdown
    case latex
    case other

    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "tex", "latex": self = .latex
        default: self = .other
        }
    }

    public var label: String {
        switch self {
        case .markdown: "Markdown"
        case .latex: "LaTeX"
        case .other: "Não suportado"
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

/// Pure tab ordering and persistence behavior used by `AppModel` and the
/// foundation contract runner. Preview content remains owned by `DocumentTab`.
public struct TabSessionState: Equatable, Sendable {
    public private(set) var paths: [URL]
    public private(set) var activePath: URL?

    public init(paths: [URL] = [], activePath: URL? = nil) {
        var unique: [URL] = []
        var seen = Set<URL>()
        for path in paths.map(\.standardizedFileURL) where seen.insert(path).inserted {
            unique.append(path)
        }
        self.paths = unique

        let normalizedActive = activePath?.standardizedFileURL
        self.activePath = normalizedActive.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first
    }

    @discardableResult
    public mutating func open(_ path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        if paths.contains(normalized) {
            activePath = normalized
            return false
        }
        paths.append(normalized)
        activePath = normalized
        return true
    }

    @discardableResult
    public mutating func select(_ path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        guard paths.contains(normalized) else { return false }
        activePath = normalized
        return true
    }

    @discardableResult
    public mutating func selectNext() -> Bool {
        guard !paths.isEmpty else { return false }
        guard let activePath,
              let index = paths.firstIndex(of: activePath) else {
            self.activePath = paths[0]
            return true
        }

        self.activePath = paths[(index + 1) % paths.count]
        return true
    }

    @discardableResult
    public mutating func move(_ path: URL, before target: URL) -> Bool {
        let normalizedPath = path.standardizedFileURL
        let normalizedTarget = target.standardizedFileURL
        guard normalizedPath != normalizedTarget,
              let sourceIndex = paths.firstIndex(of: normalizedPath),
              paths.contains(normalizedTarget) else {
            return false
        }

        paths.remove(at: sourceIndex)
        guard let targetIndex = paths.firstIndex(of: normalizedTarget) else {
            paths.insert(normalizedPath, at: sourceIndex)
            return false
        }
        paths.insert(normalizedPath, at: targetIndex)
        return true
    }

    @discardableResult
    public mutating func moveToEnd(_ path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        guard let sourceIndex = paths.firstIndex(of: normalized), sourceIndex != paths.index(before: paths.endIndex) else {
            return false
        }

        paths.remove(at: sourceIndex)
        paths.append(normalized)
        return true
    }

    @discardableResult
    public mutating func reorder(_ requestedPaths: [URL]) -> Bool {
        let normalized = requestedPaths.map(\.standardizedFileURL)
        guard normalized.count == paths.count,
              Set(normalized) == Set(paths) else {
            return false
        }

        paths = normalized
        return true
    }

    @discardableResult
    public mutating func close(_ path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        guard let index = paths.firstIndex(of: normalized) else { return false }
        let wasActive = activePath == normalized
        paths.remove(at: index)
        if wasActive {
            activePath = paths.indices.contains(index) ? paths[index] : paths.last
        }
        return true
    }

    @discardableResult
    public mutating func closeOthers(keeping path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        guard paths.contains(normalized) else { return false }
        paths = [normalized]
        activePath = normalized
        return true
    }

    @discardableResult
    public mutating func closeToRight(of path: URL) -> Bool {
        let normalized = path.standardizedFileURL
        guard let index = paths.firstIndex(of: normalized) else { return false }
        paths = Array(paths.prefix(through: index))
        if let activePath, !paths.contains(activePath) {
            self.activePath = paths.last
        }
        return true
    }

    public var persistedPaths: [String] {
        paths.map(\.path)
    }

    public static func restored(
        paths: [String],
        activePath: String?,
        fileExists: (URL) -> Bool
    ) -> TabSessionState {
        let existing = paths
            .map(URL.init(fileURLWithPath:))
            .map(\.standardizedFileURL)
            .filter(fileExists)
        let active = activePath.map(URL.init(fileURLWithPath:))
        return TabSessionState(paths: existing, activePath: active)
    }
}
