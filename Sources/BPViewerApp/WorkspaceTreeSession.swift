import BPViewerCore
import Darwin
import Foundation

/// Owns the asynchronous workspace tree lifecycle independently of the UI
/// session. The app observes snapshots and decides when workspace state is
/// persisted.
@MainActor
final class WorkspaceTreeSession {
    struct State: Equatable {
        var nodes: [FileNode] = []
        var expandedPaths: Set<String> = []
        var treeScrollOffset = 0.0
        var compatibleOnly = true
        var isScanning = false
        var isFiltering = false
    }

    private let scanner: FileSystemScanner
    private let onStateChange: (State) -> Void
    private let onPersistenceRequested: () -> Void
    private var state = State()
    private var rootURL: URL?
    private var completeNodes: [FileNode] = []
    private var treeScanGeneration = 0
    private var treeFilterGeneration = 0
    private var treeFilterTask: Task<Void, Never>?
    private var treeScrollPersistenceTask: Task<Void, Never>?
    private var automaticSingleChildExpansionPending = false
    private var automaticSingleChildExpansionBasePath: String?
    private var childLoadGenerations: [String: Int] = [:]
    private var activeDirectoryWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var watchedDirectoryURLs: Set<URL> = []
    private var treeRefreshGeneration = 0
    private var watcherRefreshSuppressedUntil: Date?

    init(
        scanner: FileSystemScanner = FileSystemScanner(),
        onStateChange: @escaping (State) -> Void,
        onPersistenceRequested: @escaping () -> Void
    ) {
        self.scanner = scanner
        self.onStateChange = onStateChange
        self.onPersistenceRequested = onPersistenceRequested
    }

    var snapshot: State { state }

    func reset(rootURL: URL?) {
        stop()
        self.rootURL = rootURL?.standardizedFileURL
        completeNodes = []
        childLoadGenerations.removeAll()
        automaticSingleChildExpansionPending = false
        automaticSingleChildExpansionBasePath = nil
        state.nodes = []
        state.expandedPaths = []
        state.treeScrollOffset = 0
        state.isScanning = false
        state.isFiltering = false
        emitState()

        if let rootURL = self.rootURL {
            startWatchingDirectories(rootURL: rootURL, nodes: [])
        }
    }

    func restore(
        expandedPaths: Set<String>,
        treeScrollOffset: Double,
        compatibleOnly: Bool,
        automaticSingleChildExpansion: Bool
    ) {
        state.expandedPaths = expandedPaths
        state.treeScrollOffset = max(treeScrollOffset, 0)
        state.compatibleOnly = compatibleOnly
        automaticSingleChildExpansionPending = automaticSingleChildExpansion
        automaticSingleChildExpansionBasePath = nil
        emitState()
    }

    func reload() {
        guard let rootURL else {
            completeNodes = []
            state.nodes = []
            state.isScanning = false
            emitState()
            return
        }

        // A file operation can already have triggered a watcher refresh. The
        // explicit reload is authoritative, so invalidate that pending work
        // instead of scanning the tree a second time shortly afterwards.
        treeRefreshGeneration += 1
        treeScanGeneration += 1
        let generation = treeScanGeneration
        let scanner = scanner
        childLoadGenerations.removeAll()
        state.isScanning = true
        emitState()

        Task { [weak self] in
            let scannedNodes = await Task.detached(priority: .userInitiated) {
                scanner.scanTopLevel(root: rootURL)
            }.value

            guard let self,
                  self.treeScanGeneration == generation,
                  self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }

            self.completeNodes = scannedNodes
            self.state.isScanning = false
            self.startWatchingDirectories(rootURL: rootURL, nodes: scannedNodes)
            self.applyTreeFilter()
            self.expandAutomaticSingleChildChainIfNeeded()
            self.loadExpandedChildrenIfNeeded()
        }
    }

    func refreshAfterFileOperation(in directories: [URL]) {
        guard let rootURL else { return }

        // File-system notifications for a local operation can arrive after
        // the explicit refresh. Ignore that short burst so one action cannot
        // enqueue a second update while SwiftUI is laying out rows.
        watcherRefreshSuppressedUntil = Date().addingTimeInterval(0.75)
        let directories = Set(directories.map { $0.standardizedFileURL })
        guard !directories.isEmpty else { return }

        treeRefreshGeneration += 1
        treeScanGeneration += 1
        let generation = treeScanGeneration
        let scanner = scanner
        treeFilterGeneration += 1
        treeFilterTask?.cancel()
        treeFilterTask = nil
        state.isFiltering = false
        state.isScanning = false

        for directory in directories {
            let path = relativePath(of: directory, from: rootURL)
            childLoadGenerations[path] = (childLoadGenerations[path] ?? 0) + 1
        }

        Task { [weak self] in
            let scannedDirectories = await Task.detached(priority: .userInitiated) {
                directories.reduce(into: [URL: [FileNode]]()) { result, directory in
                    result[directory] = scanner.scanChildren(of: directory, root: rootURL)
                }
            }.value

            guard let self,
                  self.treeScanGeneration == generation,
                  self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }

            for directory in directories {
                guard let scannedChildren = scannedDirectories[directory] else { continue }
                let existingChildren: [FileNode]
                if directory == rootURL.standardizedFileURL {
                    existingChildren = self.completeNodes
                } else {
                    existingChildren = self.findNode(
                        in: self.completeNodes,
                        id: self.relativePath(of: directory, from: rootURL)
                    )?.children ?? []
                }
                let mergedChildren = self.mergeScannedChildren(
                    scannedChildren,
                    preserving: existingChildren
                )

                if directory == rootURL.standardizedFileURL {
                    self.completeNodes = mergedChildren
                } else {
                    self.updateNode(
                        in: &self.completeNodes,
                        id: self.relativePath(of: directory, from: rootURL)
                    ) { node in
                        node.children = mergedChildren
                        node.childrenLoaded = true
                    }
                }
            }

            let affectedPaths = Set(directories.map {
                self.relativePath(of: $0, from: rootURL)
            })
            self.state.nodes = self.updateVisibleNodes(
                from: self.completeNodes,
                keeping: self.state.nodes,
                affectedPaths: affectedPaths
            )
            self.startWatchingDirectories(rootURL: rootURL, nodes: self.completeNodes)
            self.loadExpandedChildrenIfNeeded()
            self.emitState()
        }
    }

    func setCompatibleOnly(_ value: Bool) {
        state.compatibleOnly = value
        emitState()
        applyTreeFilter()
    }

    func toggleExpanded(_ path: String) {
        automaticSingleChildExpansionPending = false
        automaticSingleChildExpansionBasePath = nil
        if state.expandedPaths.contains(path) {
            state.expandedPaths.remove(path)
        } else {
            state.expandedPaths.insert(path)
            automaticSingleChildExpansionPending = true
            automaticSingleChildExpansionBasePath = path
            if findNode(in: completeNodes, id: path)?.childrenLoaded == true {
                expandAutomaticSingleChildChainIfNeeded()
            } else {
                loadChildrenIfNeeded(for: path)
            }
        }
        emitState()
    }

    func reveal(url: URL) {
        guard let rootURL else { return }

        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return }

        let relativePath = relativePath(of: url, from: rootURL)
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }

        automaticSingleChildExpansionPending = false
        automaticSingleChildExpansionBasePath = nil

        var ancestorPath = ""
        for component in components.dropLast() {
            ancestorPath = ancestorPath.isEmpty
                ? component
                : ancestorPath + "/" + component
            state.expandedPaths.insert(ancestorPath)
        }

        emitState()
        loadExpandedChildrenIfNeeded()
    }

    func collapseAllFolders() {
        state.expandedPaths.removeAll()
        automaticSingleChildExpansionPending = false
        automaticSingleChildExpansionBasePath = nil
        childLoadGenerations.removeAll()
        emitState()
    }

    func collapseFolder(_ path: String) {
        let prefix = path + "/"
        state.expandedPaths = state.expandedPaths.filter {
            $0 != path && !$0.hasPrefix(prefix)
        }
        if automaticSingleChildExpansionBasePath == path
            || automaticSingleChildExpansionBasePath?.hasPrefix(prefix) == true {
            automaticSingleChildExpansionPending = false
            automaticSingleChildExpansionBasePath = nil
        }
        childLoadGenerations = childLoadGenerations.filter { key, _ in
            key != path && !key.hasPrefix(prefix)
        }
        emitState()
    }

    func relocateExpandedPaths(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        state.expandedPaths = Set(state.expandedPaths.map { path in
            guard path == oldPath || path.hasPrefix(oldPath + "/") else { return path }
            return newPath + String(path.dropFirst(oldPath.count))
        })
        emitState()
    }

    func updateScrollOffset(_ offset: Double) {
        let normalizedOffset = max(offset, 0)
        guard abs(state.treeScrollOffset - normalizedOffset) > 0.5 else { return }
        state.treeScrollOffset = normalizedOffset
        emitState()
        treeScrollPersistenceTask?.cancel()
        treeScrollPersistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.onPersistenceRequested()
        }
    }

    func stop() {
        treeFilterTask?.cancel()
        treeFilterTask = nil
        treeScrollPersistenceTask?.cancel()
        treeScrollPersistenceTask = nil
        stopWatchingDirectories()
        watcherRefreshSuppressedUntil = nil
        treeScanGeneration += 1
        childLoadGenerations.removeAll()
    }

    private func emitState() {
        onStateChange(state)
    }

    private func applyTreeFilter() {
        treeFilterGeneration += 1
        let generation = treeFilterGeneration
        let scanner = scanner
        let completeNodes = completeNodes
        let compatibleOnly = state.compatibleOnly

        treeFilterTask?.cancel()
        state.isFiltering = true
        emitState()
        treeFilterTask = Task { [weak self] in
            let filteredNodes = await Task.detached(priority: .userInitiated) {
                scanner.filter(completeNodes, compatibleOnly: compatibleOnly, query: "")
            }.value

            guard let self,
                  self.treeFilterGeneration == generation,
                  self.rootURL != nil else { return }

            self.state.nodes = filteredNodes
            self.state.isFiltering = false
            self.emitState()
        }
    }

    private func loadChildrenIfNeeded(for path: String) {
        guard let directory = findNode(in: completeNodes, id: path),
              directory.isDirectory,
              !directory.childrenLoaded,
              let rootURL else { return }

        let generation = (childLoadGenerations[path] ?? 0) + 1
        childLoadGenerations[path] = generation
        let scanner = scanner
        let directoryURL = directory.url

        Task { [weak self] in
            let children = await Task.detached(priority: .userInitiated) {
                scanner.scanChildren(of: directoryURL, root: rootURL)
            }.value

            guard let self,
                  self.childLoadGenerations[path] == generation,
                  self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }

            self.updateNode(in: &self.completeNodes, id: path) { node in
                node.children = children
                node.childrenLoaded = true
            }
            self.startWatchingDirectories(rootURL: rootURL, nodes: self.completeNodes)
            self.applyTreeFilter()
            self.expandAutomaticSingleChildChainIfNeeded()
            self.loadExpandedChildrenIfNeeded()
        }
    }

    private func findNode(in nodes: [FileNode], id: String) -> FileNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = findNode(in: node.children, id: id) { return match }
        }
        return nil
    }

    @discardableResult
    private func updateNode(
        in nodes: inout [FileNode],
        id: String,
        update: (inout FileNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                update(&nodes[index])
                return true
            }
            if updateNode(in: &nodes[index].children, id: id, update: update) {
                return true
            }
        }
        return false
    }

    private func mergeScannedChildren(
        _ scannedChildren: [FileNode],
        preserving existingChildren: [FileNode]
    ) -> [FileNode] {
        scannedChildren.map { scannedNode in
            guard scannedNode.isDirectory,
                  let existingNode = existingChildren.first(where: { $0.id == scannedNode.id }),
                  existingNode.childrenLoaded else {
                return scannedNode
            }

            var mergedNode = scannedNode
            mergedNode.children = existingNode.children
            mergedNode.childrenLoaded = true
            return mergedNode
        }
    }

    private func updateVisibleNodes(
        from nodes: [FileNode],
        keeping visibleNodes: [FileNode],
        affectedPaths: Set<String>
    ) -> [FileNode] {
        nodes.compactMap { node in
            let oldNode = visibleNodes.first(where: { $0.id == node.id })

            if !node.isDirectory {
                guard !state.compatibleOnly || node.kind != .other else { return nil }
                return node
            }

            let isDirectlyAffected = affectedPaths.contains(node.relativePath)
            let hasAffectedDescendant = affectedPaths.contains { path in
                path.hasPrefix(node.relativePath + "/")
            }

            if isDirectlyAffected {
                let filteredChildren = scanner.filter(
                    node.children,
                    compatibleOnly: state.compatibleOnly,
                    query: ""
                )
                var updatedNode = node
                updatedNode.children = filteredChildren
                return updatedNode
            }

            guard hasAffectedDescendant else {
                return oldNode ?? scanner.filter(
                    [node],
                    compatibleOnly: state.compatibleOnly,
                    query: ""
                ).first
            }

            var updatedNode = oldNode ?? node
            updatedNode.children = updateVisibleNodes(
                from: node.children,
                keeping: oldNode?.children ?? [],
                affectedPaths: affectedPaths
            )
            return updatedNode
        }
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath ? "." : String(path.dropFirst(rootPath.count + 1))
    }

    private func loadExpandedChildrenIfNeeded() {
        for path in state.expandedPaths.sorted(by: { $0.count < $1.count }) {
            loadChildrenIfNeeded(for: path)
        }
    }

    private func expandAutomaticSingleChildChainIfNeeded() {
        guard automaticSingleChildExpansionPending else { return }

        let candidatesForExpansion: [FileNode]
        if let basePath = automaticSingleChildExpansionBasePath {
            guard let baseNode = findNode(in: completeNodes, id: basePath) else {
                automaticSingleChildExpansionPending = false
                automaticSingleChildExpansionBasePath = nil
                return
            }
            guard baseNode.childrenLoaded else {
                loadChildrenIfNeeded(for: basePath)
                return
            }
            candidatesForExpansion = baseNode.children
        } else {
            candidatesForExpansion = completeNodes
        }

        var candidates = candidatesForExpansion
        while let directory = onlyDirectory(in: candidates) {
            if !state.expandedPaths.contains(directory.id) {
                state.expandedPaths.insert(directory.id)
                emitState()
                loadChildrenIfNeeded(for: directory.id)
                return
            }

            guard directory.childrenLoaded else {
                loadChildrenIfNeeded(for: directory.id)
                return
            }
            candidates = directory.children
        }

        automaticSingleChildExpansionPending = false
        automaticSingleChildExpansionBasePath = nil
        onPersistenceRequested()
    }

    private func onlyDirectory(in nodes: [FileNode]) -> FileNode? {
        let directories = nodes.filter(\.isDirectory)
        return directories.count == 1 ? directories[0] : nil
    }

    private func startWatchingDirectories(rootURL: URL, nodes: [FileNode]) {
        var directories = Set([rootURL.standardizedFileURL])
        collectDirectories(from: nodes, into: &directories)
        guard directories != watchedDirectoryURLs else { return }

        stopWatchingDirectories()
        for url in directories {
            let descriptor = Darwin.open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .link],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.scheduleTreeRefresh(for: url)
            }
            source.setCancelHandler {
                Darwin.close(descriptor)
            }
            activeDirectoryWatchers[url] = source
            watchedDirectoryURLs.insert(url)
            source.resume()
        }
    }

    private func collectDirectories(from nodes: [FileNode], into directories: inout Set<URL>) {
        for node in nodes where node.isDirectory {
            guard node.childrenLoaded else { continue }
            directories.insert(node.url.standardizedFileURL)
            collectDirectories(from: node.children, into: &directories)
        }
    }

    private func stopWatchingDirectories() {
        activeDirectoryWatchers.values.forEach { $0.cancel() }
        activeDirectoryWatchers.removeAll()
        watchedDirectoryURLs.removeAll()
        treeRefreshGeneration += 1
    }

    private func scheduleTreeRefresh(for directoryURL: URL) {
        guard watchedDirectoryURLs.contains(directoryURL.standardizedFileURL) else { return }
        if let suppressedUntil = watcherRefreshSuppressedUntil {
            guard Date() >= suppressedUntil else { return }
            watcherRefreshSuppressedUntil = nil
        }

        treeRefreshGeneration += 1
        let generation = treeRefreshGeneration
        let rootURL = rootURL
        let knownStructure = childStructureSignature(in: directoryURL, rootURL: rootURL)
        let scanner = scanner
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self,
                  self.treeRefreshGeneration == generation,
                  let rootURL else { return }

            let currentStructure = await Task.detached(priority: .userInitiated) {
                Set(
                    scanner.scanChildren(of: directoryURL, root: rootURL)
                        .map { "\($0.id)|\($0.isDirectory ? "directory" : "file")" }
                )
            }.value

            guard self.treeRefreshGeneration == generation,
                  currentStructure != knownStructure else { return }

            let refreshDirectory = FileManager.default.fileExists(atPath: directoryURL.path)
                ? directoryURL
                : directoryURL.deletingLastPathComponent()
            self.refreshAfterFileOperation(in: [refreshDirectory])
        }
    }

    private func childStructureSignature(in directoryURL: URL, rootURL: URL?) -> Set<String> {
        guard let rootURL else { return [] }
        let children: [FileNode]
        if directoryURL.standardizedFileURL == rootURL.standardizedFileURL {
            children = completeNodes
        } else {
            children = findNode(
                in: completeNodes,
                id: relativePath(of: directoryURL, from: rootURL)
            )?.children ?? []
        }
        return Set(children.map { "\($0.id)|\($0.isDirectory ? "directory" : "file")" })
    }
}
