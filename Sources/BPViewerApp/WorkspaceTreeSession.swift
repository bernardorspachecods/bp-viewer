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
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }

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

        treeRefreshGeneration += 1
        let generation = treeRefreshGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.treeRefreshGeneration == generation else { return }
            self.reload()
        }
    }
}
