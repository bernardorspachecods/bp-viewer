import AppKit
import BPViewerCore
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension Notification.Name {
    static let bpViewerOpenFiles = Notification.Name("bp-viewer.open-files")
}

struct LatexRootSelectionRequest: Identifiable {
    let id: String
    let tabID: String
    let openedFile: URL
    let projectRoot: URL
    let candidates: [LatexRootCandidate]
}

struct LatexExternalDependencyRequest: Identifiable {
    let id: String
    let tabID: String
    let rootURL: URL
    let projectRoot: URL
    let dependencies: [LatexExternalDependency]
}

@MainActor
final class AppModel: ObservableObject {
    @Published var theme: AppThemePreference
    @Published var rootURL: URL?
    @Published private(set) var nodes: [FileNode] = []
    @Published var tabs: [DocumentTab] = []
    @Published var activeTabID: String?
    @Published var treeQuery = ""
    @Published var compatibleOnly = true
    @Published var expandedPaths: Set<String> = []
    @Published var treeScrollOffset: Double = 0
    @Published var sidebarVisible = true
    @Published var sidebarWidth: Double = 280
    @Published var previewZoom: Double = 1.0
    @Published var latexShellEscapeMode: LatexShellEscapeMode = .disabled
    @Published var isFindBarVisible = false
    @Published var findQuery = ""
    @Published var findRequestID = 0
    @Published var findBackwards = false
    @Published private(set) var isScanningTree = false
    @Published private(set) var isFilteringTree = false
    @Published var pendingRootURL: URL?
    @Published var showingRootChangeConfirmation = false
    @Published var pendingLatexRootSelection: LatexRootSelectionRequest?
    @Published var pendingLatexExternalDependencies: LatexExternalDependencyRequest?

    private let scanner = FileSystemScanner()
    private let latexRenderCache = LatexRenderCache()
    private let stateStore = AppStateStore()
    private var appState: AppState
    private let markdownAdapter: any MarkdownAdapter = SwiftMarkdownAdapter()
    private var completeNodes: [FileNode] = []
    private var fullyIndexedNodes: [FileNode]?
    private var fullIndexTask: Task<[FileNode], Never>?
    private var treeScanGeneration = 0
    private var treeFilterGeneration = 0
    private var treeFilterTask: Task<Void, Never>?
    private var childLoadGenerations: [String: Int] = [:]
    private var previewGenerations: [String: Int] = [:]
    private var latexRenderTasks: [String: Task<Void, Never>] = [:]
    private var activeDirectoryWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var watchedDirectoryURLs: Set<URL> = []
    private var treeRefreshGeneration = 0
    private var activeFileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var watchedFileURLs: Set<URL> = []
    private var fileRefreshGeneration = 0
    private var pendingOpenURLs: [URL] = []
    private var openFilesObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?

    init() {
        appState = stateStore.load()
        theme = AppThemePreference(rawValue: appState.global.theme) ?? .dark
        sidebarVisible = appState.global.sidebarVisible
        sidebarWidth = appState.global.sidebarWidth
        latexShellEscapeMode = LatexShellEscapeMode(rawValue: appState.global.latexShellEscapeMode) ?? .disabled

        openFilesObserver = NotificationCenter.default.addObserver(
            forName: .bpViewerOpenFiles,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urls = notification.object as? [URL] else { return }
            Task { @MainActor [weak self] in
                self?.openExternalURLs(urls)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                Task { @MainActor [weak self] in
                    self?.closeActiveTab()
                }
                return nil
            }

            if flags == [.control], event.keyCode == 48 {
                Task { @MainActor [weak self] in
                    self?.selectNextTab()
                }
                return nil
            }

            return event
        }

        if let path = appState.lastWorkspacePath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path), isDirectory(url) {
                rootURL = url
                reloadTree()
                restoreTabs()
            }
        }
    }

    var activeTab: DocumentTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    private var tabSessionState: TabSessionState {
        let activeURL = activeTabID.map { URL(fileURLWithPath: $0) }
        return TabSessionState(paths: tabs.map(\.url), activePath: activeURL)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Abrir pasta"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingOpenURLs = []
        requestRoot(url)
    }

    func requestRoot(_ url: URL) {
        guard rootURL != nil else {
            openRoot(url)
            let urlsToOpen = pendingOpenURLs
            pendingOpenURLs = []
            urlsToOpen.forEach { openDocument(url: $0) }
            return
        }

        pendingRootURL = url
        showingRootChangeConfirmation = true
    }

    func confirmRootChange() {
        guard let pendingRootURL else { return }
        let urlsToOpen = pendingOpenURLs
        pendingOpenURLs = []
        openRoot(pendingRootURL)
        self.pendingRootURL = nil
        showingRootChangeConfirmation = false
        urlsToOpen.forEach { openDocument(url: $0) }
    }

    func cancelRootChange() {
        pendingRootURL = nil
        pendingOpenURLs = []
        showingRootChangeConfirmation = false
    }

    func openRoot(_ url: URL) {
        persistState()
        latexRenderTasks.values.forEach { $0.cancel() }
        latexRenderTasks.removeAll()
        previewGenerations.removeAll()
        stopWatchingDirectories()
        stopWatchingActiveFiles()
        treeFilterTask?.cancel()
        fullIndexTask?.cancel()
        fullIndexTask = nil
        fullyIndexedNodes = nil
        let standardizedRoot = url.standardizedFileURL
        rootURL = standardizedRoot
        tabs = []
        activeTabID = nil
        treeScrollOffset = 0
        expandedPaths = []
        restoreTabs()
        startWatchingDirectories(rootURL: standardizedRoot, nodes: [])
        appState.lastWorkspacePath = workspaceKey(for: standardizedRoot)
        reloadTree()
        persistState()
    }

    func reloadTree() {
        guard let rootURL else {
            completeNodes = []
            nodes = []
            return
        }

        treeScanGeneration += 1
        let generation = treeScanGeneration
        let scanner = scanner
        childLoadGenerations.removeAll()
        isScanningTree = true

        Task { [weak self] in
            let scannedNodes = await Task.detached(priority: .userInitiated) {
                scanner.scanTopLevel(root: rootURL)
            }.value

            guard let self,
                  self.treeScanGeneration == generation,
                  self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }

            self.completeNodes = scannedNodes
            self.isScanningTree = false
            self.startWatchingDirectories(rootURL: rootURL, nodes: scannedNodes)
            self.applyTreeFilter()
            self.loadExpandedChildrenIfNeeded()
        }
    }

    func updateTreeQuery(_ query: String) {
        treeQuery = query
        applyTreeFilter()
    }

    func updateCompatibleOnly(_ value: Bool) {
        compatibleOnly = value
        persistState()
        applyTreeFilter()
    }

    func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadChildrenIfNeeded(for: path)
        }
        persistState()
    }

    func updateTreeScrollOffset(_ offset: Double) {
        let normalizedOffset = max(offset, 0)
        guard abs(treeScrollOffset - normalizedOffset) > 0.5 else { return }
        treeScrollOffset = normalizedOffset
        persistState()
    }

    func updateMarkdownReadingPosition(
        _ position: MarkdownReadingPosition,
        forTabID tabID: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].markdownReadingPosition != position else { return }
        tabs[index].markdownReadingPosition = position
        persistState()
    }

    func updatePDFReadingPosition(
        _ position: PDFReadingPosition,
        forTabID tabID: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let pageIndex = position.pageIndex
        let changed = tabs[index].pdfReadingPosition != position
            || tabs[index].previewPageIndex != pageIndex
        guard changed else { return }
        tabs[index].pdfReadingPosition = position
        tabs[index].previewPageIndex = pageIndex
        persistState()
    }

    func open(_ node: FileNode) {
        guard !node.isDirectory else {
            toggleExpanded(node.id)
            return
        }

        openDocument(url: node.url)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyPath(_ url: URL) {
        copyText(FilePathCopy.string(for: url))
    }

    func openExternalURLs(_ urls: [URL]) {
        let files = urls
            .filter(\.isFileURL)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { DocumentKind(url: $0) == .markdown || DocumentKind(url: $0) == .latex }
        guard let first = files.first else { return }

        let desiredRoot = DocumentKind(url: first) == .latex
            ? inferredLatexProjectRoot(for: first)
            : first.deletingLastPathComponent()
        let currentRoot = rootURL?.resolvingSymlinksInPath().standardizedFileURL
        let sameRoot = currentRoot?.path == desiredRoot.resolvingSymlinksInPath().standardizedFileURL.path

        if rootURL == nil {
            openRoot(desiredRoot)
            files.forEach { openDocument(url: $0) }
        } else if sameRoot {
            files.forEach { openDocument(url: $0) }
        } else {
            pendingOpenURLs = files
            requestRoot(desiredRoot)
        }
    }

    func openDroppedURLs(_ urls: [URL]) {
        let resolvedURLs = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        if let directory = resolvedURLs.first(where: { isDirectory($0) }) {
            pendingOpenURLs = []
            requestRoot(directory)
            return
        }
        openExternalURLs(resolvedURLs)
    }

    func openPreviewURL(_ url: URL) {
        if let localFileURL = MarkdownPreviewLink.fileURL(from: url) {
            openPreviewURL(localFileURL)
            return
        }

        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }

        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return
        }

        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            return
        }

        if DocumentKind(url: standardizedURL) == .other {
            NSWorkspace.shared.open(standardizedURL)
        } else {
            openDocument(url: standardizedURL)
        }
    }

    private func openDocument(url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return }

        let kind = DocumentKind(url: standardizedURL)
        guard kind != .other else {
            NSWorkspace.shared.open(standardizedURL)
            return
        }

        var documentURL = standardizedURL
        var contextURL: URL?
        if kind == .latex,
           let projectRoot = rootURL,
           let selectedRoot = storedLatexRoot(for: projectRoot)
               ?? (try? LatexRootDiscovery().resolve(
                   openedFile: standardizedURL,
                   projectRoot: projectRoot
               ))?.selectedRoot {
            documentURL = selectedRoot
            contextURL = selectedRoot == standardizedURL ? nil : standardizedURL
        }

        let id = documentURL.path
        var session = tabSessionState
        let inserted = session.open(documentURL)
        if !inserted {
            activeTabID = session.activePath?.path
            if let contextURL,
               let index = tabs.firstIndex(where: { $0.id == id }) {
                tabs[index].contextURL = contextURL
            }
            syncPreviewZoomToActiveTab()
            renderActiveTabIfNeeded()
            persistState()
            return
        }

        let documentState = appState.documentStates[documentKey(for: documentURL)] ?? DocumentState()
        let tab = DocumentTab(
            id: id,
            url: documentURL,
            kind: kind,
            contextURL: contextURL,
            status: kind == .markdown || kind == .latex ? .updating : .unavailable,
            isOutlineVisible: documentState.outlineVisible,
            previewZoom: documentState.zoom,
            previewPageIndex: documentState.pdfReadingPosition?.pageIndex ?? 0,
            markdownReadingPosition: documentState.markdownReadingPosition,
            pdfReadingPosition: documentState.pdfReadingPosition
        )
        tabs.append(tab)
        activeTabID = session.activePath?.path
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    private func inferredLatexProjectRoot(for fileURL: URL) -> URL {
        var directory = fileURL.deletingLastPathComponent().standardizedFileURL
        while directory.path != "/" {
            if let resolution = try? LatexRootDiscovery().resolve(
                openedFile: fileURL,
                projectRoot: directory
            ), !resolution.candidates.isEmpty {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return fileURL.deletingLastPathComponent().standardizedFileURL
    }

    func closeTab(_ tab: DocumentTab) {
        guard tabs.contains(tab) else { return }
        latexRenderTasks[tab.id]?.cancel()
        latexRenderTasks.removeValue(forKey: tab.id)
        previewGenerations[tab.id, default: 0] += 1
        if pendingLatexRootSelection?.tabID == tab.id {
            pendingLatexRootSelection = nil
        }
        if pendingLatexExternalDependencies?.tabID == tab.id {
            pendingLatexExternalDependencies = nil
        }
        let wasActive = activeTabID == tab.id
        var session = tabSessionState
        guard session.close(tab.url) else { return }
        tabs.removeAll { $0.id == tab.id }
        activeTabID = session.activePath?.path
        syncPreviewZoomToActiveTab()
        if wasActive {
            renderActiveTabIfNeeded()
        }
        persistState()
    }

    func closeActiveTab() {
        guard let activeTab else { return }
        closeTab(activeTab)
    }

    func moveTab(id: String, before targetID: String) {
        guard let source = tabs.first(where: { $0.id == id }),
              let target = tabs.first(where: { $0.id == targetID }) else { return }

        var session = tabSessionState
        guard session.move(source.url, before: target.url) else { return }
        reorderTabs(using: session)
    }

    func moveTabToEnd(id: String) {
        guard let source = tabs.first(where: { $0.id == id }) else { return }

        var session = tabSessionState
        guard session.moveToEnd(source.url) else { return }
        reorderTabs(using: session)
    }

    func reorderTabs(ids: [String]) {
        let urlsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.url) })
        let requestedPaths = ids.compactMap { urlsByID[$0] }
        guard requestedPaths.count == tabs.count else { return }

        var session = tabSessionState
        guard session.reorder(requestedPaths) else { return }
        reorderTabs(using: session)
    }

    private func reorderTabs(using session: TabSessionState) {
        let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        tabs = session.paths.compactMap { tabsByID[$0.path] }
        persistState()
    }

    func closeOtherTabs(keeping tab: DocumentTab) {
        var session = tabSessionState
        guard session.closeOthers(keeping: tab.url) else { return }
        cancelLatexRenders(for: tabs.filter { $0.id != tab.id })
        tabs = [tab]
        activeTabID = session.activePath?.path
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func closeTabsToRight(of tab: DocumentTab) {
        var session = tabSessionState
        guard session.closeToRight(of: tab.url) else { return }
        let allowed = Set(session.paths.map(\.path))
        cancelLatexRenders(for: tabs.filter { !allowed.contains($0.id) })
        tabs = tabs.filter { allowed.contains($0.id) }
        if let activeTabID, !allowed.contains(activeTabID) {
            self.activeTabID = session.activePath?.path
            syncPreviewZoomToActiveTab()
            renderActiveTabIfNeeded()
        }
        persistState()
    }

    func refreshActiveTab() {
        reloadTree()
        guard let activeTabID else { return }
        if tabs.first(where: { $0.id == activeTabID })?.kind == .markdown {
            renderMarkdown(tabID: activeTabID)
        } else if tabs.first(where: { $0.id == activeTabID })?.kind == .latex {
            renderLatex(tabID: activeTabID, force: true)
        } else if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].status = .unavailable
            tabs[index].errorMessage = nil
        }
        persistState()
    }

    func showFindBar() {
        guard activeTab?.kind == .markdown || activeTab?.kind == .latex else { return }
        isFindBarVisible = true
    }

    func setOutlineVisible(_ visible: Bool, forTabID tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].isOutlineVisible != visible else { return }
        tabs[index].isOutlineVisible = visible
        persistState()
    }

    func cancelLatexRootSelection() {
        pendingLatexRootSelection = nil
    }

    func cancelLatexExternalDependencies() {
        pendingLatexExternalDependencies = nil
    }

    func chooseLatexRootFile() {
        guard let request = pendingLatexRootSelection else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = request.projectRoot
        if let texType = UTType(filenameExtension: "tex") {
            panel.allowedContentTypes = [texType]
        }
        panel.prompt = "Escolher root"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chooseLatexRoot(url)
    }

    func approveLatexExternalDependencies() {
        guard let request = pendingLatexExternalDependencies else { return }
        let grantKey = latexExternalGrantKey(projectRoot: request.projectRoot, rootURL: request.rootURL)
        let workspaceID = workspaceKey(for: request.projectRoot)
        var workspace = appState.workspaceStates[workspaceID] ?? WorkspaceState()
        var paths = workspace.latexExternalGrants[grantKey] ?? []
        paths.append(contentsOf: request.dependencies.map(\.url.path))
        workspace.latexExternalGrants[grantKey] = Array(Set(paths)).sorted()
        appState.workspaceStates[workspaceID] = workspace
        saveState()
        pendingLatexExternalDependencies = nil
        renderLatex(tabID: request.tabID, rootURL: request.rootURL)
    }

    func changeLatexRoot() {
        guard let tab = activeTab,
              tab.kind == .latex,
              let projectRoot = rootURL else {
            return
        }

        let openedFile = tab.contextURL ?? tab.url
        guard let resolution = try? LatexRootDiscovery().resolve(
            openedFile: openedFile,
            projectRoot: projectRoot
        ) else {
            return
        }

        pendingLatexRootSelection = LatexRootSelectionRequest(
            id: tab.id,
            tabID: tab.id,
            openedFile: openedFile,
            projectRoot: projectRoot,
            candidates: resolution.candidates
        )
    }

    func chooseLatexRoot(_ rootURL: URL) {
        guard let request = pendingLatexRootSelection,
              (request.candidates.isEmpty
                || request.candidates.contains(where: { $0.url.standardizedFileURL == rootURL.standardizedFileURL })),
              rootURL.pathExtension.lowercased() == "tex",
              isRegularFile(rootURL),
              isInside(rootURL, project: request.projectRoot) else {
            return
        }

        pendingLatexRootSelection = nil
        storeLatexRoot(rootURL, for: request.projectRoot)

        guard let oldIndex = tabs.firstIndex(where: { $0.id == request.tabID }) else { return }
        let contextURL = request.openedFile.standardizedFileURL == rootURL.standardizedFileURL
            ? nil
            : request.openedFile.standardizedFileURL

        if let existingIndex = tabs.firstIndex(where: {
            $0.id == rootURL.path && $0.id != request.tabID
        }) {
            tabs[existingIndex].contextURL = contextURL
            tabs.remove(at: oldIndex)
            activeTabID = rootURL.path
            syncPreviewZoomToActiveTab()
        } else {
            tabs[oldIndex] = DocumentTab(
                id: rootURL.path,
                url: rootURL.standardizedFileURL,
                kind: .latex,
                contextURL: contextURL,
                status: .updating
            )
            activeTabID = rootURL.path
            let documentState = appState.documentStates[documentKey(for: rootURL)] ?? DocumentState()
            tabs[oldIndex].isOutlineVisible = documentState.outlineVisible
            tabs[oldIndex].previewZoom = documentState.zoom
            tabs[oldIndex].previewPageIndex = documentState.pdfReadingPosition?.pageIndex ?? 0
            tabs[oldIndex].markdownReadingPosition = documentState.markdownReadingPosition
            tabs[oldIndex].pdfReadingPosition = documentState.pdfReadingPosition
            syncPreviewZoomToActiveTab()
        }

        renderLatex(tabID: rootURL.path, rootURL: rootURL, force: true)
        persistState()
    }

    func hideFindBar() {
        isFindBarVisible = false
        findQuery = ""
        findRequestID += 1
    }

    func findNext() {
        findBackwards = false
        findRequestID += 1
    }

    func findPrevious() {
        findBackwards = true
        findRequestID += 1
    }

    func zoomIn() {
        setPreviewZoom(previewZoom + 0.1)
    }

    func zoomOut() {
        setPreviewZoom(previewZoom - 0.1)
    }

    func resetPreviewZoom() {
        setPreviewZoom(1.0)
    }

    func setLatexShellEscapeMode(_ mode: LatexShellEscapeMode) {
        guard latexShellEscapeMode != mode else { return }
        latexShellEscapeMode = mode
        appState.global.latexShellEscapeMode = mode.rawValue
        saveState()
        if let activeTabID, activeTab?.kind == .latex {
            renderLatex(tabID: activeTabID, force: true)
        }
    }

    func updateReadingPage(tabID: String, pageIndex: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              pageIndex >= 0 else { return }
        guard tabs[index].previewPageIndex != pageIndex else { return }
        tabs[index].previewPageIndex = pageIndex
        persistState()
    }

    private func setPreviewZoom(_ value: Double) {
        let normalizedValue = min(max(value, 0.7), 2.0)
        previewZoom = normalizedValue
        guard let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }
        tabs[index].previewZoom = normalizedValue
        persistState()
    }

    private func applyTreeFilter() {
        treeFilterGeneration += 1
        let generation = treeFilterGeneration
        let scanner = scanner
        let completeNodes = completeNodes
        let compatibleOnly = compatibleOnly
        let query = treeQuery
        let rootURL = rootURL

        treeFilterTask?.cancel()
        isFilteringTree = true
        treeFilterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }

            var sourceNodes = completeNodes
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let rootURL {
                let fullIndexTask = self?.fullIndexTaskForSearch(rootURL: rootURL, scanner: scanner)
                sourceNodes = await fullIndexTask?.value ?? completeNodes
            }

            let filteredNodes = await Task.detached(priority: .userInitiated) {
                scanner.filter(
                    sourceNodes,
                    compatibleOnly: compatibleOnly,
                    query: query
                )
            }.value

            guard let self,
                  self.treeFilterGeneration == generation,
                  self.rootURL != nil else { return }

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.fullyIndexedNodes = sourceNodes
                self.completeNodes = sourceNodes
            }
            self.nodes = filteredNodes
            self.isFilteringTree = false
        }
    }

    private func fullIndexTaskForSearch(
        rootURL: URL,
        scanner: FileSystemScanner
    ) -> Task<[FileNode], Never> {
        if let fullyIndexedNodes {
            return Task { fullyIndexedNodes }
        }
        if let fullIndexTask {
            return fullIndexTask
        }

        let task = Task.detached(priority: .userInitiated) {
            scanner.scan(root: rootURL)
        }
        fullIndexTask = task
        return task
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

    func cycleTheme() {
        switch theme {
        case .light: theme = .dark
        case .dark: theme = .light
        }
        appState.global.theme = theme.rawValue
        saveState()
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        appState.global.sidebarVisible = visible
        saveState()
    }

    func setSidebarWidth(_ width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
        appState.global.sidebarWidth = sidebarWidth
        saveState()
    }

    func resizeSidebar(to width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
    }

    func selectTab(number: Int) {
        guard tabs.indices.contains(number) else { return }
        selectTab(id: tabs[number].id)
    }

    func selectNextTab() {
        var session = tabSessionState
        guard session.selectNext() else { return }
        activeTabID = session.activePath?.path
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func selectTab(id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        var session = tabSessionState
        guard session.select(tab.url) else { return }
        activeTabID = session.activePath?.path
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func persistState() {
        guard let rootURL else {
            saveState()
            return
        }

        let session = tabSessionState
        let rootKey = workspaceKey(for: rootURL)
        var workspace = appState.workspaceStates[rootKey] ?? WorkspaceState()
        workspace.tabPaths = session.persistedPaths
        workspace.activeTabPath = session.activePath?.path
        workspace.expandedPaths = expandedPaths.sorted()
        workspace.treeScrollOffset = treeScrollOffset
        workspace.compatibleOnly = compatibleOnly
        workspace.tabContexts = tabs.reduce(into: [String: String]()) { result, tab in
            guard tab.kind == .latex, let contextURL = tab.contextURL else { return }
            LatexTabContextPersistence.store(contextURL: contextURL, forTabID: tab.id, in: &result)
        }
        appState.workspaceStates[rootKey] = workspace

        for tab in tabs {
            let key = documentKey(for: tab.url)
            appState.documentStates[key] = DocumentState(
                zoom: tab.previewZoom,
                outlineVisible: tab.isOutlineVisible,
                markdownReadingPosition: tab.markdownReadingPosition,
                pdfReadingPosition: tab.pdfReadingPosition
            )
        }

        appState.lastWorkspacePath = rootKey
        appState.global.theme = theme.rawValue
        appState.global.sidebarVisible = sidebarVisible
        appState.global.sidebarWidth = sidebarWidth
        appState.global.latexShellEscapeMode = latexShellEscapeMode.rawValue
        saveState()
    }

    private func restoreTabs() {
        guard let rootURL else {
            tabs = []
            activeTabID = nil
            expandedPaths = []
            treeScrollOffset = 0
            return
        }

        let rootKey = workspaceKey(for: rootURL)
        let savedWorkspace = appState.workspaceStates[rootKey] ?? WorkspaceState()
        compatibleOnly = savedWorkspace.compatibleOnly
        treeScrollOffset = savedWorkspace.treeScrollOffset
        let session = TabSessionState.restored(
            paths: savedWorkspace.tabPaths,
            activePath: savedWorkspace.activeTabPath,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        let available = session.paths.compactMap { url -> DocumentTab? in
            let kind = DocumentKind(url: url)
            let documentState = appState.documentStates[documentKey(for: url)] ?? DocumentState()
            let contextURL = LatexTabContextPersistence.restore(
                forTabID: url.path,
                tabURL: url,
                kind: kind,
                from: savedWorkspace.tabContexts,
                projectRoot: rootURL
            )
            return DocumentTab(
                id: url.path,
                url: url,
                kind: kind,
                contextURL: contextURL,
                status: kind == .markdown || kind == .latex ? .idle : .unavailable,
                isOutlineVisible: documentState.outlineVisible,
                previewZoom: documentState.zoom,
                previewPageIndex: documentState.pdfReadingPosition?.pageIndex ?? 0,
                markdownReadingPosition: documentState.markdownReadingPosition,
                pdfReadingPosition: documentState.pdfReadingPosition
            )
        }
        tabs = available
        activeTabID = session.activePath?.path
        expandedPaths = Set(savedWorkspace.expandedPaths)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        loadExpandedChildrenIfNeeded()
    }

    private func saveState() {
        stateStore.save(appState)
    }

    private func workspaceKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func documentKey(for url: URL) -> String {
        workspaceKey(for: url)
    }

    private func syncPreviewZoomToActiveTab() {
        previewZoom = tabs.first(where: { $0.id == activeTabID })?.previewZoom ?? 1.0
    }

    private func loadExpandedChildrenIfNeeded() {
        for path in expandedPaths.sorted(by: { $0.count < $1.count }) {
            loadChildrenIfNeeded(for: path)
        }
    }

    private func renderActiveTabIfNeeded() {
        guard let activeTabID,
              let tab = tabs.first(where: { $0.id == activeTabID }),
              tab.kind == .markdown || tab.kind == .latex else {
            stopWatchingActiveFiles()
            return
        }

        startWatchingActiveFiles(
            [tab.url] + tab.previewDependencies + tab.previewExternalDependencies
        )
        let hasPreview = tab.kind == .markdown
            ? tab.previewHTML != nil
            : tab.previewPDFData != nil
        if !hasPreview || tab.status != .ready {
            if tab.kind == .markdown {
                renderMarkdown(tabID: activeTabID)
            } else {
                renderLatex(tabID: activeTabID)
            }
        }
    }

    private func startWatchingActiveFiles(_ urls: [URL]) {
        let standardizedURLs = Set(urls.map(\.standardizedFileURL))
        guard watchedFileURLs != standardizedURLs else { return }

        stopWatchingActiveFiles()
        for url in standardizedURLs {
            let descriptor = Darwin.open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.scheduleActiveFileRefresh(for: url)
            }
            source.setCancelHandler {
                Darwin.close(descriptor)
            }
            activeFileWatchers[url] = source
            watchedFileURLs.insert(url)
            source.resume()
        }
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
            // A top-level scan only discovers directory names. Do not open
            // protected folders merely to watch them; wait until the user
            // expands that directory and its children have been loaded.
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
            self.reloadTree()
        }
    }

    private func stopWatchingActiveFiles() {
        activeFileWatchers.values.forEach { $0.cancel() }
        activeFileWatchers.removeAll()
        watchedFileURLs.removeAll()
        fileRefreshGeneration += 1
    }

    private func restartWatchingActiveFiles(_ urls: [URL]) {
        stopWatchingActiveFiles()
        startWatchingActiveFiles(urls)
    }

    private func scheduleActiveFileRefresh(for url: URL) {
        guard watchedFileURLs.contains(url),
              let activeTabID,
              tabs.contains(where: { tab in
                  tab.id == activeTabID
                    && ([tab.url] + tab.previewDependencies + tab.previewExternalDependencies)
                        .map(\.standardizedFileURL).contains(url)
              }) else { return }

        fileRefreshGeneration += 1
        let generation = fileRefreshGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.fileRefreshGeneration == generation else { return }
            if self.tabs.first(where: { $0.id == activeTabID })?.kind == .latex {
                self.renderLatex(tabID: activeTabID)
            } else {
                self.renderMarkdown(tabID: activeTabID)
            }
        }
    }

    private func renderLatex(
        tabID: String,
        rootURL explicitRootURL: URL? = nil,
        force: Bool = false
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .latex,
              let projectRoot = self.rootURL else { return }

        let tabURL = tabs[index].url
        let storedRootURL = explicitRootURL ?? storedLatexRoot(for: projectRoot)
        let approvedExternalPaths = approvedLatexExternalPaths
        let cache = latexRenderCache
        let shellEscapeMode = latexShellEscapeMode
        latexRenderTasks[tabID]?.cancel()
        let generation = (previewGenerations[tabID] ?? 0) + 1
        previewGenerations[tabID] = generation
        tabs[index].status = .updating
        tabs[index].errorMessage = nil

        let adapter = LocalLatexAdapter(shellEscapeMode: latexShellEscapeMode)
        let task = Task { [weak self] in
            do {
                let renderOperation = Task.detached(priority: .userInitiated) {
                    let resolvedRootURL: URL
                    if let storedRootURL {
                        resolvedRootURL = storedRootURL
                    } else {
                        let resolution = try LatexRootDiscovery().resolve(
                            openedFile: tabURL,
                            projectRoot: projectRoot
                        )
                        guard let selectedRoot = resolution.selectedRoot else {
                            throw LatexRenderError.rootSelectionRequired(resolution.candidates)
                        }
                        resolvedRootURL = selectedRoot
                    }
                    let externalDependencies = adapter.externalDependencies(
                        rootURL: resolvedRootURL,
                        projectRoot: projectRoot
                    )
                    let grantKey = "\(projectRoot.standardizedFileURL.path)\n\(resolvedRootURL.standardizedFileURL.path)"
                    let unapprovedDependencies = externalDependencies.filter {
                        !approvedExternalPaths[grantKey, default: []].contains($0.url.path)
                    }
                    if !unapprovedDependencies.isEmpty {
                        throw LatexRenderError.externalDependenciesRequireConfirmation(
                            resolvedRootURL,
                            unapprovedDependencies
                        )
                    }
                    let cacheKey = LatexCacheKey(
                        projectRoot: projectRoot,
                        rootURL: resolvedRootURL,
                        compilerIdentity: try adapter.compilerIdentity(
                            rootURL: resolvedRootURL,
                            projectRoot: projectRoot
                        ),
                        shellEscapeMode: shellEscapeMode
                    )
                    if !force, let cached = cache.load(key: cacheKey) {
                        return LatexRenderResult(
                            pdfData: cached.pdfData,
                            rootURL: cached.rootURL,
                            dependencies: cached.dependencies,
                            externalDependencies: cached.externalDependencies,
                            processResult: ProcessResult(
                                status: .success,
                                exitCode: 0,
                                standardOutput: "cache hit",
                                standardError: ""
                            ),
                            wasCached: true
                        )
                    }
                    let result = try adapter.render(rootURL: resolvedRootURL, projectRoot: projectRoot)
                    try? cache.store(key: cacheKey, result: result)
                    return result
                }
                let result = try await withTaskCancellationHandler(operation: {
                    try await renderOperation.value
                }, onCancel: {
                    renderOperation.cancel()
                })

                guard let self,
                      self.previewGenerations[tabID] == generation,
                      let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

                self.latexRenderTasks.removeValue(forKey: tabID)
                self.tabs[index].previewPDFData = result.pdfData
                self.tabs[index].previewUpdatedAt = Date()
                self.tabs[index].previewHTML = nil
                self.tabs[index].previewBaseURL = nil
                self.tabs[index].previewDependencies = result.dependencies
                self.tabs[index].previewExternalDependencies = result.externalDependencies
                self.tabs[index].status = .ready
                self.tabs[index].isStale = false
                self.tabs[index].errorMessage = nil
                if self.activeTabID == tabID {
                    self.restartWatchingActiveFiles(
                        [tabURL] + result.dependencies + result.externalDependencies
                    )
                }
            } catch {
                if Task.isCancelled { return }
                guard let self,
                      self.previewGenerations[tabID] == generation,
                      let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

                self.latexRenderTasks.removeValue(forKey: tabID)
                self.tabs[index].status = self.previewStatus(for: error)
                self.tabs[index].isStale = self.tabs[index].previewPDFData != nil
                self.tabs[index].errorMessage = error.localizedDescription
                if let latexError = error as? LatexRenderError,
                   case let .rootSelectionRequired(candidates) = latexError {
                    self.pendingLatexRootSelection = LatexRootSelectionRequest(
                        id: tabID,
                        tabID: tabID,
                        openedFile: tabURL,
                        projectRoot: projectRoot,
                        candidates: candidates
                    )
                }
                if let latexError = error as? LatexRenderError,
                   case let .externalDependenciesRequireConfirmation(rootURL, dependencies) = latexError {
                    self.pendingLatexExternalDependencies = LatexExternalDependencyRequest(
                        id: tabID,
                        tabID: tabID,
                        rootURL: rootURL,
                        projectRoot: projectRoot,
                        dependencies: dependencies
                    )
                }
                if self.activeTabID == tabID {
                    self.restartWatchingActiveFiles(
                        [tabURL]
                            + self.tabs[index].previewDependencies
                            + self.tabs[index].previewExternalDependencies
                    )
                }
            }
        }
        latexRenderTasks[tabID] = task
    }

    private func cancelLatexRenders(for tabs: [DocumentTab]) {
        let removedIDs = Set(tabs.map(\.id))
        guard !removedIDs.isEmpty else { return }

        for tabID in removedIDs {
            latexRenderTasks[tabID]?.cancel()
            latexRenderTasks.removeValue(forKey: tabID)
            previewGenerations[tabID, default: 0] += 1
        }

        if let pendingLatexRootSelection,
           removedIDs.contains(pendingLatexRootSelection.tabID) {
            self.pendingLatexRootSelection = nil
        }
        if let pendingLatexExternalDependencies,
           removedIDs.contains(pendingLatexExternalDependencies.tabID) {
            self.pendingLatexExternalDependencies = nil
        }
    }

    private func storedLatexRoot(for projectRoot: URL) -> URL? {
        let key = workspaceKey(for: projectRoot)
        guard let path = appState.workspaceStates[key]?.latexRootSelections[projectRoot.standardizedFileURL.path] else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: path).standardizedFileURL
        guard isRegularFile(rootURL),
              isInside(rootURL, project: projectRoot.standardizedFileURL) else {
            return nil
        }
        return rootURL
    }

    private func storeLatexRoot(_ rootURL: URL, for projectRoot: URL) {
        let key = workspaceKey(for: projectRoot)
        var workspace = appState.workspaceStates[key] ?? WorkspaceState()
        workspace.latexRootSelections[projectRoot.standardizedFileURL.path] = rootURL.standardizedFileURL.path
        appState.workspaceStates[key] = workspace
        saveState()
    }

    private var approvedLatexExternalPaths: [String: Set<String>] {
        guard let rootURL else { return [:] }
        let grants = appState.workspaceStates[workspaceKey(for: rootURL)]?.latexExternalGrants ?? [:]
        return grants.mapValues(Set.init)
    }

    private func latexExternalGrantKey(projectRoot: URL, rootURL: URL) -> String {
        "\(projectRoot.standardizedFileURL.path)\n\(rootURL.standardizedFileURL.path)"
    }

    private func renderMarkdown(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), tabs[index].kind == .markdown else { return }

        let tabURL = tabs[index].url
        let generation = (previewGenerations[tabID] ?? 0) + 1
        previewGenerations[tabID] = generation
        tabs[index].status = .updating
        tabs[index].errorMessage = nil

        let adapter = markdownAdapter
        Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let source = try String(contentsOf: tabURL, encoding: .utf8)
                    return try adapter.render(
                        source: source,
                        baseURL: tabURL.deletingLastPathComponent()
                    )
                }.value

                guard let self,
                      self.previewGenerations[tabID] == generation,
                      let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

                self.tabs[index].previewHTML = result.html
                self.tabs[index].previewUpdatedAt = Date()
                self.tabs[index].previewBaseURL = result.baseURL
                self.tabs[index].previewDependencies = result.dependencies
                self.tabs[index].markdownOutline = result.outline
                self.tabs[index].status = .ready
                self.tabs[index].isStale = false
                self.tabs[index].errorMessage = nil
                if self.activeTabID == tabID {
                    self.restartWatchingActiveFiles([tabURL] + result.dependencies)
                }
            } catch {
                guard let self,
                      self.previewGenerations[tabID] == generation,
                      let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

                self.tabs[index].status = .failed
                self.tabs[index].isStale = self.tabs[index].previewHTML != nil
                self.tabs[index].errorMessage = error.localizedDescription
                if self.activeTabID == tabID {
                    self.restartWatchingActiveFiles([tabURL] + self.tabs[index].previewDependencies)
                }
            }
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        return values?.isRegularFile == true && values?.isDirectory != true
    }

    private func previewStatus(for error: Error) -> PreviewStatus {
        guard let latexError = error as? LatexRenderError else { return .failed }
        switch latexError {
        case .toolUnavailable:
            return .unavailable
        case let .compilationFailed(result), let .outputPDFMissing(_, result):
            switch result.status {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .launchFailed: return .unavailable
            case .failed, .success: return .failed
            }
        default:
            return .failed
        }
    }

    private func isInside(_ url: URL, project: URL) -> Bool {
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let projectPath = project.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == projectPath || candidatePath.hasPrefix(projectPath + "/")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

}
