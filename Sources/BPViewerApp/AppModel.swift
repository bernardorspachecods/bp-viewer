import AppKit
import BPViewerCore
import Combine
import Foundation
@preconcurrency import PDFKit
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
    @Published var defaultMarkdownZoom: Double = 1.0
    @Published var defaultLatexZoom: Double = 1.0
    @Published var latexShellEscapeMode: LatexShellEscapeMode = .disabled
    @Published var isFindBarVisible = false
    @Published var findQuery = ""
    @Published var findRequestID = 0
    @Published var findBackwards = false
    @Published var findTarget: FindTarget = .preview
    @Published var findMatchCount: Int?
    @Published private(set) var isScanningTree = false
    @Published private(set) var isFilteringTree = false
    @Published var pendingRootURL: URL?
    @Published var showingRootChangeConfirmation = false
    @Published private(set) var isPendingRootChange = false
    @Published var pendingCloseRequest: PendingCloseRequest?
    @Published var showingPendingCloseConfirmation = false
    @Published private(set) var isPendingWindowClose = false
    @Published var pendingInvalidJSONTabID: String?
    @Published var showingInvalidJSONConfirmation = false
    @Published var pendingLatexRootSelection: LatexRootSelectionRequest?
    @Published var pendingLatexExternalDependencies: LatexExternalDependencyRequest?
    @Published var isSnapshotCaptureActive = false

    private let workspaceSession = WorkspaceSessionCoordinator()
    private let documentOpenCoordinator = DocumentOpenCoordinator()
    private let snapshotArtifactStore = SnapshotArtifactStore()
    private lazy var snapshotWindowManager = SnapshotWindowManager { [weak self] id in
        self?.removeSnapshot(id: id)
    }
    private lazy var workspaceTreeSession = WorkspaceTreeSession(
        onStateChange: { [weak self] state in
            self?.applyWorkspaceTreeState(state)
        },
        onPersistenceRequested: { [weak self] in
            self?.persistState()
        }
    )
    private lazy var documentRenderCoordinator = DocumentRenderCoordinator { [weak self] event in
        self?.handleDocumentRenderEvent(event)
    }
    private lazy var documentEditCoordinator = DocumentEditCoordinator()
    private lazy var documentDiffCoordinator = DocumentDiffCoordinator()
    private lazy var activeDocumentWatcher = ActiveDocumentWatcher { [weak self] change in
        self?.handleActiveDocumentChange(change)
    }
    private var pendingOpenURLs: [URL] = []
    private var openFilesObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private weak var pendingWindow: NSWindow?
    private var pendingBatchCloseIDs: Set<String> = []

    init() {
        let configuration = workspaceSession.configuration
        theme = AppThemePreference(rawValue: configuration.theme) ?? .dark
        sidebarVisible = configuration.sidebarVisible
        sidebarWidth = configuration.sidebarWidth
        latexShellEscapeMode = LatexShellEscapeMode(rawValue: configuration.latexShellEscapeMode) ?? .disabled
        defaultMarkdownZoom = min(max(configuration.defaultMarkdownZoom, 0.7), 2.0)
        defaultLatexZoom = min(max(configuration.defaultLatexZoom, 0.7), 2.0)

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
                if let snapshotWindow = NSApp.keyWindow as? SnapshotPanel {
                    snapshotWindow.performClose(nil)
                    return nil
                }
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

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "s",
               let tabID = self?.activeTabID,
               let session = self?.activeTab?.markdownEditSession,
               session.currentSource != session.baseSource {
                Task { @MainActor [weak self] in
                    await self?.saveMarkdownEdit(tabID: tabID)
                }
                return nil
            }

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "s",
               let tabID = self?.activeTabID,
               let session = self?.activeTab?.jsonEditSession,
               session.currentSource != session.baseSource {
                Task { @MainActor [weak self] in
                    await self?.saveJSONEdit(tabID: tabID)
                }
                return nil
            }

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "s",
               let tabID = self?.activeTabID,
               let session = self?.activeTab?.csvEditSession,
               session.currentSource != session.baseSource {
                Task { @MainActor [weak self] in
                    _ = await self?.saveCSVEdit(tabID: tabID)
                }
                return nil
            }

            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               let session = self?.activeTab?.markdownEditSession,
               (flags.contains(.shift) ? !session.redoSources.isEmpty : !session.undoSources.isEmpty) {
                let redo = flags.contains(.shift)
                Task { @MainActor [weak self] in
                    if redo {
                        self?.redoMarkdownEdit()
                    } else {
                        self?.undoMarkdownEdit()
                    }
                }
                return nil
            }

            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               let session = self?.activeTab?.jsonEditSession,
               (flags.contains(.shift) ? !session.redoSources.isEmpty : !session.undoSources.isEmpty) {
                let redo = flags.contains(.shift)
                Task { @MainActor [weak self] in
                    if redo {
                        self?.redoJSONEdit()
                    } else {
                        self?.undoJSONEdit()
                    }
                }
                return nil
            }

            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               let session = self?.activeTab?.csvEditSession,
               (flags.contains(.shift) ? !session.redoSources.isEmpty : !session.undoSources.isEmpty) {
                let redo = flags.contains(.shift)
                Task { @MainActor [weak self] in
                    if redo {
                        self?.redoCSVEdit()
                    } else {
                        self?.undoCSVEdit()
                    }
                }
                return nil
            }

            return event
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.snapshotWindowManager.prepareForTermination()
                self.persistState()
            }
        }

        if let path = workspaceSession.lastWorkspacePath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path), isDirectory(url) {
                rootURL = url
                workspaceTreeSession.reset(rootURL: url)
                reloadTree()
                restoreTabs()
            }
        }
    }

    var activeTab: DocumentTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    private var documentTabSession: DocumentTabSession {
        DocumentTabSession(tabs: tabs, activeTabID: activeTabID)
    }

    private func applyDocumentTabSession(_ session: DocumentTabSession) {
        tabs = session.tabs
        activeTabID = session.activeTabID
    }

    private func applyWorkspaceTreeState(_ state: WorkspaceTreeSession.State) {
        nodes = state.nodes
        expandedPaths = state.expandedPaths
        treeScrollOffset = state.treeScrollOffset
        compatibleOnly = state.compatibleOnly
        isScanningTree = state.isScanning
        isFilteringTree = state.isFiltering
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"

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
        if let tab = tabs.first(where: hasUnsavedChanges(in:)) {
            isPendingRootChange = true
            showingRootChangeConfirmation = false
            presentPendingClose(for: tab, closesTab: false)
            return
        }
        completeRootChange(to: pendingRootURL)
    }

    private func completeRootChange(to rootURL: URL) {
        let urlsToOpen = pendingOpenURLs
        pendingOpenURLs = []
        openRoot(rootURL)
        self.pendingRootURL = nil
        showingRootChangeConfirmation = false
        isPendingRootChange = false
        urlsToOpen.forEach { openDocument(url: $0) }
    }

    func cancelRootChange() {
        pendingRootURL = nil
        pendingOpenURLs = []
        showingRootChangeConfirmation = false
        isPendingRootChange = false
    }

    func openRoot(_ url: URL) {
        snapshotWindowManager.closeAllPreservingRecords()
        persistState()
        documentRenderCoordinator.cancelAll()
        workspaceTreeSession.reset(rootURL: nil)
        stopWatchingActiveFiles()
        let standardizedRoot = url.standardizedFileURL
        rootURL = standardizedRoot
        workspaceTreeSession.reset(rootURL: standardizedRoot)
        tabs = []
        activeTabID = nil
        restoreTabs()
        reloadTree()
        persistState()
    }

    func reloadTree() {
        workspaceTreeSession.reload()
    }

    func updateTreeQuery(_ query: String) {
        treeQuery = query
    }

    func updateCompatibleOnly(_ value: Bool) {
        workspaceTreeSession.setCompatibleOnly(value)
        persistState()
    }

    func toggleExpanded(_ path: String) {
        workspaceTreeSession.toggleExpanded(path)
        persistState()
    }

    func updateTreeScrollOffset(_ offset: Double) {
        workspaceTreeSession.updateScrollOffset(offset)
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

    var canCaptureActivePreview: Bool {
        guard let activeTab else { return false }
        return activeTab.previewHTML != nil
            || activeTab.previewJSON != nil
            || activeTab.previewCSV != nil
            || activeTab.previewPDFData != nil
    }

    func startSnapshotCapture() {
        guard canCaptureActivePreview else { return }
        isSnapshotCaptureActive = true
    }

    func cancelSnapshotCapture() {
        isSnapshotCaptureActive = false
    }

    func finishSnapshotCapture(_ image: NSImage, forTabID tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let rootURL,
              image.size.width > 1,
              image.size.height > 1 else {
            cancelSnapshotCapture()
            return
        }

        let recordID = UUID().uuidString
        do {
            let artifactURL = try snapshotArtifactStore.save(image, id: recordID)
            let record = SnapshotRecord(
                id: recordID,
                documentPath: workspaceSession.documentKey(for: tab.url),
                title: tab.title,
                artifactPath: artifactURL.path,
                createdAt: Date()
            )
            workspaceSession.addSnapshot(record, for: rootURL)
            persistState()
            snapshotWindowManager.open(
                record: record,
                image: image,
                above: NSApp.keyWindow ?? NSApp.windows.first
            )
        } catch {
            // A failed snapshot must not leave capture mode active.
        }
        cancelSnapshotCapture()
    }

    private func removeSnapshot(id: String) {
        let artifactPath = workspaceSession.removeSnapshot(id: id)
        if let artifactPath {
            snapshotArtifactStore.remove(at: URL(fileURLWithPath: artifactPath))
        }
        persistState()
    }

    private func restoreSnapshots(for rootURL: URL) {
        let records = workspaceSession.snapshots(for: rootURL)
        guard !records.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }
            for record in records {
                guard let image = self.snapshotArtifactStore.load(
                    from: URL(fileURLWithPath: record.artifactPath)
                ) else { continue }
                self.snapshotWindowManager.open(
                    record: record,
                    image: image,
                    above: NSApp.keyWindow ?? NSApp.windows.first
                )
            }
        }
    }

    func openExternalURLs(_ urls: [URL]) {
        let files = urls
            .filter(\.isFileURL)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter {
                documentOpenCoordinator.isPreviewable(DocumentKind(url: $0))
            }
        guard let first = files.first else { return }

        let desiredRoot = DocumentKind(url: first) == .latex
            ? documentOpenCoordinator.inferredLatexProjectRoot(for: first)
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

        guard let result = documentOpenCoordinator.resolve(
            standardizedURL,
            workspaceRoot: rootURL,
            storedLatexRoot: rootURL.flatMap { workspaceSession.storedLatexRoot(for: $0) }
        ) else { return }
        switch result {
        case let .external(externalURL):
            NSWorkspace.shared.open(externalURL)
        case .preview:
            openDocument(url: standardizedURL)
        }
    }

    private func openDocument(url: URL) {
        guard let result = documentOpenCoordinator.resolve(
            url,
            workspaceRoot: rootURL,
            storedLatexRoot: rootURL.flatMap { workspaceSession.storedLatexRoot(for: $0) }
        ) else { return }
        guard case let .preview(documentURL, kind, contextURL) = result else {
            if case let .external(externalURL) = result {
                NSWorkspace.shared.open(externalURL)
            }
            return
        }

        let id = documentURL.path
        var session = documentTabSession
        if let existingTab = session.tabs.first(where: { $0.id == id }) {
            _ = session.select(id: existingTab.id)
            if let contextURL {
                _ = session.update(id: id) { $0.contextURL = contextURL }
            }
            applyDocumentTabSession(session)
            syncPreviewZoomToActiveTab()
            renderActiveTabIfNeeded()
            persistState()
            return
        }

        let documentState = workspaceSession.documentState(for: documentURL)
        let tab = DocumentTab(
            id: id,
            url: documentURL,
            kind: kind,
            contextURL: contextURL,
            status: kind == .docx ? .ready : .updating,
            isOutlineVisible: documentState.outlineVisible,
            previewZoom: documentState.zoom ?? defaultZoom(for: kind),
            isPreviewZoomCustomized: documentState.zoom != nil,
            previewPageIndex: documentState.pdfReadingPosition?.pageIndex ?? 0,
            markdownReadingPosition: documentState.markdownReadingPosition,
            pdfReadingPosition: documentState.pdfReadingPosition
        )

        _ = session.open(tab)
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func closeTab(_ tab: DocumentTab) {
        guard tabs.contains(tab) else { return }
        guard !hasUnsavedChanges(in: tab) else {
            presentPendingClose(for: tab, closesTab: true)
            return
        }
        closeTabImmediately(tab)
    }

    func shouldCloseWindow(_ window: NSWindow) -> Bool {
        if isPendingWindowClose || showingPendingCloseConfirmation || showingInvalidJSONConfirmation {
            return false
        }
        guard let tab = tabs.first(where: hasUnsavedChanges(in:)) else {
            return true
        }
        pendingWindow = window
        isPendingWindowClose = true
        presentPendingClose(for: tab, closesTab: false)
        return false
    }

    private func presentPendingClose(for tab: DocumentTab, closesTab: Bool) {
        pendingCloseRequest = PendingCloseRequest(
            id: "\(closesTab ? "tab" : "window")-\(tab.id)",
            tabID: tab.id,
            title: tab.title,
            closesTab: closesTab
        )
        showingPendingCloseConfirmation = true
    }

    func cancelPendingClose() {
        if let request = pendingCloseRequest,
           let index = tabs.firstIndex(where: { $0.id == request.tabID }) {
            tabs[index].markdownEditSession?.isEditing = true
            tabs[index].jsonEditSession?.isEditing = true
        }
        pendingCloseRequest = nil
        showingPendingCloseConfirmation = false
        pendingBatchCloseIDs.removeAll()
        if isPendingWindowClose {
            isPendingWindowClose = false
            pendingWindow = nil
        }
        if isPendingRootChange {
            isPendingRootChange = false
            pendingRootURL = nil
            pendingOpenURLs = []
        }
    }

    var pendingCloseCanSave: Bool {
        guard let request = pendingCloseRequest,
              let tab = tabs.first(where: { $0.id == request.tabID }) else {
            return false
        }
        guard tab.kind == .json else { return true }
        return tab.jsonEditSession?.saveState != .failed && tab.errorMessage == nil
    }

    func discardPendingClose() {
        guard let request = pendingCloseRequest,
              let tab = tabs.first(where: { $0.id == request.tabID }) else {
            pendingCloseRequest = nil
            showingPendingCloseConfirmation = false
            pendingBatchCloseIDs.removeAll()
            return
        }
        let closesTab = request.closesTab
        pendingCloseRequest = nil
        showingPendingCloseConfirmation = false
        if closesTab {
            closeTabImmediately(tab)
        } else {
            discardChanges(in: tab)
            continuePendingExit()
        }
    }

    func savePendingClose() {
        guard pendingCloseCanSave else { return }
        guard let request = pendingCloseRequest,
              let tab = tabs.first(where: { $0.id == request.tabID }) else {
            pendingCloseRequest = nil
            showingPendingCloseConfirmation = false
            return
        }
        let closesTab = request.closesTab
        pendingCloseRequest = nil
        showingPendingCloseConfirmation = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            let saved: Bool
            switch tab.kind {
            case .markdown:
                saved = await saveMarkdownEdit(tabID: tab.id)
            case .json:
                saved = await saveJSONEdit(tabID: tab.id, finishEditing: !closesTab)
            case .csv:
                saved = await saveCSVEdit(tabID: tab.id)
            default:
                saved = true
            }
            guard saved else { return }
            if closesTab {
                guard let currentTab = tabs.first(where: { $0.id == tab.id }) else { return }
                closeTabImmediately(currentTab)
            } else {
                continuePendingExit()
            }
        }
    }

    private func continuePendingExit() {
        guard isPendingWindowClose || isPendingRootChange else { return }
        if let nextTab = tabs.first(where: hasUnsavedChanges(in:)) {
            presentPendingClose(for: nextTab, closesTab: false)
            return
        }
        if isPendingRootChange, let rootURL = pendingRootURL {
            completeRootChange(to: rootURL)
            return
        }
        let window = pendingWindow
        pendingWindow = nil
        isPendingWindowClose = false
        window?.close()
    }

    private func discardChanges(in tab: DocumentTab, keepEditing: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let session = tabs[index].markdownEditSession {
            tabs[index].markdownSource = session.baseSource
            tabs[index].markdownBlocks = MarkdownBlockDocument(source: session.baseSource).blocks
            tabs[index].markdownEditSession?.currentSource = session.baseSource
            tabs[index].markdownEditSession?.undoSources.removeAll()
            tabs[index].markdownEditSession?.redoSources.removeAll()
            tabs[index].markdownEditSession?.saveState = .saved
            tabs[index].markdownEditSession?.conflict = nil
            tabs[index].markdownEditSession?.isEditing = keepEditing
            tabs[index].errorMessage = nil
            renderMarkdown(tabID: tab.id)
        } else if let session = tabs[index].jsonEditSession {
            tabs[index].jsonSource = session.baseSource
            tabs[index].jsonEditSession?.currentSource = session.baseSource
            tabs[index].jsonEditSession?.undoSources.removeAll()
            tabs[index].jsonEditSession?.redoSources.removeAll()
            tabs[index].jsonEditSession?.saveState = .saved
            tabs[index].jsonEditSession?.conflict = nil
            tabs[index].jsonEditSession?.isEditing = keepEditing
            tabs[index].errorMessage = nil
            renderJSON(tabID: tab.id)
        } else if let session = tabs[index].csvEditSession {
            if let document = try? CSVPreviewAdapter().parse(source: session.baseSource) {
                tabs[index].previewCSV = document
            }
            tabs[index].csvEditSession = keepEditing
                ? CSVEditSession(
                    isEditing: true,
                    baseSource: session.baseSource,
                    currentSource: session.baseSource,
                    saveState: .saved
                )
                : nil
            tabs[index].errorMessage = nil
            renderCSV(tabID: tab.id)
        }
    }

    func discardEditing(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        discardChanges(in: tab, keepEditing: true)
    }

    private func closeTabImmediately(_ tab: DocumentTab) {
        guard tabs.contains(tab) else { return }
        documentRenderCoordinator.cancel(tabIDs: [tab.id])
        if pendingLatexRootSelection?.tabID == tab.id {
            pendingLatexRootSelection = nil
        }
        if pendingLatexExternalDependencies?.tabID == tab.id {
            pendingLatexExternalDependencies = nil
        }
        let wasActive = activeTabID == tab.id
        var session = documentTabSession
        guard session.close(id: tab.id) else { return }
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        if wasActive {
            renderActiveTabIfNeeded()
        }
        persistState()
        if pendingBatchCloseIDs.remove(tab.id) != nil {
            continuePendingBatchClose()
        }
    }

    private func hasUnsavedChanges(in tab: DocumentTab) -> Bool {
        if let session = tab.markdownEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        if let session = tab.jsonEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        if let session = tab.csvEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        return false
    }

    func closeActiveTab() {
        guard let activeTab else { return }
        closeTab(activeTab)
    }

    func moveTab(id: String, before targetID: String) {
        var session = documentTabSession
        guard session.move(id, before: targetID) else { return }
        reorderTabs(using: session)
    }

    func moveTabToEnd(id: String) {
        var session = documentTabSession
        guard session.moveToEnd(id) else { return }
        reorderTabs(using: session)
    }

    func reorderTabs(ids: [String]) {
        var session = documentTabSession
        guard session.reorder(ids: ids) else { return }
        reorderTabs(using: session)
    }

    private func reorderTabs(using session: DocumentTabSession) {
        applyDocumentTabSession(session)
        persistState()
    }

    func closeOtherTabs(keeping tab: DocumentTab) {
        requestBatchClose(tabs.filter { $0.id != tab.id })
    }

    func closeTabsToRight(of tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        requestBatchClose(Array(tabs.dropFirst(index + 1)))
    }

    private func requestBatchClose(_ tabsToClose: [DocumentTab]) {
        guard !tabsToClose.isEmpty else { return }
        let ids = Set(tabsToClose.map(\.id))
        if let unsavedTab = tabsToClose.first(where: hasUnsavedChanges(in:)) {
            pendingBatchCloseIDs = ids
            presentPendingClose(for: unsavedTab, closesTab: true)
            return
        }
        closeTabsImmediately(ids)
    }

    private func continuePendingBatchClose() {
        guard !pendingBatchCloseIDs.isEmpty else { return }
        let batchTabs = tabs.filter { pendingBatchCloseIDs.contains($0.id) }
        if let unsavedTab = batchTabs.first(where: hasUnsavedChanges(in:)) {
            presentPendingClose(for: unsavedTab, closesTab: true)
        } else {
            let ids = pendingBatchCloseIDs
            pendingBatchCloseIDs.removeAll()
            closeTabsImmediately(ids)
        }
    }

    private func closeTabsImmediately(_ ids: Set<String>) {
        let closingTabs = tabs.filter { ids.contains($0.id) }
        guard !closingTabs.isEmpty else { return }
        let wasActive = activeTabID.map(ids.contains) == true
        documentRenderCoordinator.cancel(tabIDs: closingTabs.map(\.id))
        var session = documentTabSession
        for tab in closingTabs {
            _ = session.close(id: tab.id)
        }
        applyDocumentTabSession(session)
        if wasActive {
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
        } else if tabs.first(where: { $0.id == activeTabID })?.kind == .json {
            renderJSON(tabID: activeTabID)
        } else if tabs.first(where: { $0.id == activeTabID })?.kind == .csv {
            renderCSV(tabID: activeTabID)
        } else if tabs.first(where: { $0.id == activeTabID })?.kind == .pdf {
            renderPDF(tabID: activeTabID)
        } else if tabs.first(where: { $0.id == activeTabID })?.kind == .docx {
            refreshDocx(tabID: activeTabID)
        } else if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].status = .unavailable
            tabs[index].errorMessage = nil
        }
        persistState()
    }

    func beginMarkdownEditing(
        tabID: String,
        mode: MarkdownEditingMode = .markdown
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .markdown else { return }

        let source = tabs[index].markdownSource
            ?? (try? String(contentsOf: tabs[index].url, encoding: .utf8))
            ?? ""
        tabs[index].diffSession = nil
        applyMarkdownTransition(
            documentEditCoordinator.beginMarkdown(source: source, mode: mode),
            at: index
        )
    }

    func toggleDocumentDiff(mode: DocumentDiffMode, tabID: String) {
        guard let initialIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[initialIndex].diffSession?.mode == mode {
            tabs[initialIndex].diffSession = nil
            return
        }

        switch tabs[initialIndex].kind {
        case .markdown:
            if tabs[initialIndex].markdownEditSession?.isEditing != true {
                beginMarkdownEditing(tabID: tabID)
            }
        case .json:
            if tabs[initialIndex].jsonEditSession?.isEditing != true {
                beginJSONEditing(tabID: tabID)
            }
        default:
            return
        }

        openDocumentDiff(tabID: tabID, mode: mode)
    }

    private func openDocumentDiff(tabID: String, mode: DocumentDiffMode) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .markdown || tabs[index].kind == .json else { return }

        switch documentDiffCoordinator.baseline(for: mode, url: tabs[index].url) {
        case let .available(baseline):
            tabs[index].diffSession = DocumentDiffSession(
                mode: mode,
                baseline: baseline
            )
        case let .unavailable(message):
            tabs[index].diffSession = DocumentDiffSession(
                mode: mode,
                unavailableMessage: message
            )
        }
    }

    func updateMarkdownEditing(
        tabID: String,
        text: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let transition = documentEditCoordinator.updateMarkdown(
                  session: session,
                  source: text
              ) else { return }

        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            renderMarkdown(tabID: tabID, sourceOverride: text)
        }
    }

    func endMarkdownEditing(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession else { return }
        if session.currentSource == session.baseSource {
            tabs[index].markdownEditSession?.isEditing = false
            tabs[index].diffSession = nil
            renderMarkdown(tabID: tabID)
        } else {
            tabs[index].markdownEditSession?.saveState = .saving
            Task { @MainActor [weak self] in
                _ = await self?.saveMarkdownEdit(tabID: tabID, finishEditing: true)
            }
        }
    }

    func updateCSVEditing(tabID: String, row: Int, column: Int, value: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .csv,
              let document = tabs[index].previewCSV,
              let updatedDocument = document.replacingCell(atRow: row, column: column, with: value) else {
            return
        }

        let adapter = CSVPreviewAdapter()
        let currentSource = adapter.serialize(document: updatedDocument)
        if tabs[index].csvEditSession == nil {
            let baseSource = (try? String(contentsOf: tabs[index].url, encoding: .utf8))
                ?? adapter.serialize(document: document)
            tabs[index].csvEditSession = CSVEditSession(
                baseSource: baseSource,
                currentSource: currentSource,
                saveState: .unsaved,
                undoSources: [baseSource]
            )
        } else {
            guard let session = tabs[index].csvEditSession,
                  session.currentSource != currentSource else { return }
            tabs[index].csvEditSession?.undoSources.append(session.currentSource)
            tabs[index].csvEditSession?.redoSources.removeAll()
            tabs[index].csvEditSession?.isEditing = true
            tabs[index].csvEditSession?.currentSource = currentSource
            tabs[index].csvEditSession?.saveState = .unsaved
            tabs[index].csvEditSession?.conflict = nil
        }
        tabs[index].previewCSV = updatedDocument
        tabs[index].previewUpdatedAt = Date()
        tabs[index].errorMessage = nil
    }

    func keepLocalCSVEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession else { return }
        applyCSVSaveOutcome(
            documentEditCoordinator.commitCSV(url: tabs[index].url, source: session.currentSource),
            tabID: tabID
        )
    }

    @discardableResult
    func saveCSVEditing(tabID: String) async -> Bool {
        await saveCSVEdit(tabID: tabID)
    }

    @discardableResult
    func undoCSVEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession,
              let previous = session.undoSources.last,
              let document = try? CSVPreviewAdapter().parse(source: previous) else { return false }

        var updated = session
        updated.undoSources.removeLast()
        updated.redoSources.append(updated.currentSource)
        updated.currentSource = previous
        updated.saveState = previous == updated.baseSource ? .saved : .unsaved
        updated.conflict = nil
        updated.isEditing = true
        tabs[index].csvEditSession = updated
        tabs[index].previewCSV = document
        tabs[index].previewUpdatedAt = Date()
        tabs[index].errorMessage = nil
        return true
    }

    @discardableResult
    func redoCSVEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession,
              let next = session.redoSources.last,
              let document = try? CSVPreviewAdapter().parse(source: next) else { return false }

        var updated = session
        updated.redoSources.removeLast()
        updated.undoSources.append(updated.currentSource)
        updated.currentSource = next
        updated.saveState = next == updated.baseSource ? .saved : .unsaved
        updated.conflict = nil
        updated.isEditing = true
        tabs[index].csvEditSession = updated
        tabs[index].previewCSV = document
        tabs[index].previewUpdatedAt = Date()
        tabs[index].errorMessage = nil
        return true
    }

    func useExternalCSVEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession,
              let conflict = session.conflict,
              let document = try? CSVPreviewAdapter().parse(source: conflict.externalSource) else {
            return
        }
        tabs[index].previewCSV = document
        tabs[index].csvEditSession = CSVEditSession(
            isEditing: false,
            baseSource: conflict.externalSource,
            currentSource: conflict.externalSource,
            saveState: .saved
        )
        tabs[index].previewUpdatedAt = Date()
        tabs[index].errorMessage = nil
    }

    @discardableResult
    private func saveCSVEdit(tabID: String) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession else {
            return false
        }
        guard session.currentSource != session.baseSource else { return true }

        tabs[index].csvEditSession?.saveState = .saving
        let localSource = session.currentSource
        let outcome = await documentEditCoordinator.saveCSV(
            url: tabs[index].url,
            baseSource: session.baseSource,
            localSource: localSource
        )
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[currentIndex].csvEditSession?.currentSource == localSource else {
            return false
        }
        return applyCSVSaveOutcome(outcome, tabID: tabID)
    }

    @discardableResult
    private func applyCSVSaveOutcome(
        _ outcome: DocumentEditSaveOutcome,
        tabID: String
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              var session = tabs[index].csvEditSession else {
            return false
        }
        switch outcome {
        case let .saved(source):
            guard let document = try? CSVPreviewAdapter().parse(source: source) else {
                session.saveState = .failed
                tabs[index].csvEditSession = session
                return false
            }
            session.baseSource = source
            session.currentSource = source
            session.saveState = .saved
            session.conflict = nil
            tabs[index].csvEditSession = session
            tabs[index].previewCSV = document
            tabs[index].previewUpdatedAt = Date()
            tabs[index].errorMessage = nil
            return true
        case let .conflict(conflict):
            session.saveState = .conflict
            session.conflict = conflict
            tabs[index].csvEditSession = session
            return false
        case let .failed(message):
            session.saveState = .failed
            session.conflict = nil
            tabs[index].csvEditSession = session
            tabs[index].errorMessage = message
            return false
        }
    }

    func beginJSONEditing(tabID: String, previewUTF8Offset: Int = 0) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .json else { return }

        let source = tabs[index].jsonSource
            ?? (try? String(contentsOf: tabs[index].url, encoding: .utf8))
            ?? ""
        tabs[index].diffSession = nil
        let transition = documentEditCoordinator.beginJSON(
            source: source,
            previewUTF8Offset: previewUTF8Offset
        )
        tabs[index].jsonSource = source
        tabs[index].errorMessage = nil
        tabs[index].jsonCursorUTF8Offset = transition.jsonCursorUTF8Offset
        tabs[index].jsonEditSession = transition.session
    }

    func updateJSONEditing(tabID: String, text: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .json,
              let session = tabs[index].jsonEditSession,
              let transition = documentEditCoordinator.updateJSON(
                  session: session,
                  source: text
              ) else { return }

        applyJSONTransition(transition, at: index)
    }

    func endJSONEditing(tabID: String, source: String? = nil) {
        if let source,
           tabs.first(where: { $0.id == tabID })?.jsonEditSession?.currentSource != source {
            updateJSONEditing(tabID: tabID, text: source)
        }

        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .json,
              let session = tabs[index].jsonEditSession else { return }

        if session.saveState == .failed {
            pendingInvalidJSONTabID = tabID
            showingInvalidJSONConfirmation = true
            return
        }

        if session.currentSource == session.baseSource {
            tabs[index].jsonEditSession?.isEditing = false
            tabs[index].diffSession = nil
            renderJSON(tabID: tabID)
        } else {
            tabs[index].jsonEditSession?.saveState = .saving
            Task { @MainActor [weak self] in
                _ = await self?.saveJSONEdit(tabID: tabID, finishEditing: true)
            }
        }
    }

    func cancelInvalidJSONEditing() {
        pendingInvalidJSONTabID = nil
        showingInvalidJSONConfirmation = false
    }

    func discardInvalidJSONEditing() {
        guard let tabID = pendingInvalidJSONTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession else {
            cancelInvalidJSONEditing()
            return
        }

        tabs[index].jsonSource = session.baseSource
        tabs[index].jsonEditSession?.currentSource = session.baseSource
        tabs[index].jsonEditSession?.undoSources.removeAll()
        tabs[index].jsonEditSession?.redoSources.removeAll()
        tabs[index].jsonEditSession?.saveState = .saved
        tabs[index].jsonEditSession?.conflict = nil
        tabs[index].jsonEditSession?.isEditing = false
        tabs[index].diffSession = nil
        tabs[index].errorMessage = nil
        cancelInvalidJSONEditing()
        renderJSON(tabID: tabID)
    }

    @discardableResult
    func undoJSONEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession,
              let transition = documentEditCoordinator.undoJSON(session: session) else { return false }
        applyJSONTransition(transition, at: index)
        return true
    }

    @discardableResult
    func redoJSONEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession,
              let transition = documentEditCoordinator.redoJSON(session: session) else { return false }
        applyJSONTransition(transition, at: index)
        return true
    }

    func keepLocalJSONEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession else { return }
        applyJSONSaveOutcome(
            documentEditCoordinator.commitJSON(url: tabs[index].url, source: session.currentSource),
            tabID: tabID,
            finishEditing: true
        )
    }

    func useExternalJSONEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession,
              let conflict = session.conflict else { return }
        applyJSONTransition(
            documentEditCoordinator.useExternal(
                session: session,
                externalSource: conflict.externalSource
            ),
            at: index
        )
        tabs[index].diffSession = nil
        renderJSON(tabID: tabID)
    }

    @discardableResult
    private func saveJSONEdit(tabID: String, finishEditing: Bool = false) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession else {
            return false
        }

        guard session.currentSource != session.baseSource else {
            if finishEditing {
                tabs[index].jsonEditSession?.isEditing = false
                tabs[index].diffSession = nil
                renderJSON(tabID: tabID)
            }
            return true
        }

        tabs[index].jsonEditSession?.saveState = .saving
        let localSource = session.currentSource
        let outcome = await documentEditCoordinator.saveJSON(
            url: tabs[index].url,
            baseSource: session.baseSource,
            localSource: localSource
        )
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[currentIndex].jsonEditSession?.currentSource == localSource else {
            return false
        }
        return applyJSONSaveOutcome(outcome, tabID: tabID, finishEditing: finishEditing)
    }

    func toggleMarkdownSplitView(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard var session = tabs[index].markdownEditSession,
              session.isEditing else {
            beginMarkdownEditing(tabID: tabID, mode: .split)
            return
        }
        session.mode = session.mode == .markdown ? .split : .markdown
        tabs[index].markdownEditSession = session
        if session.mode == .split {
            renderMarkdown(tabID: tabID, sourceOverride: session.currentSource)
        }
    }

    @discardableResult
    func undoMarkdownEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let transition = documentEditCoordinator.undoMarkdown(session: session) else { return false }

        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            renderMarkdown(tabID: tabID, sourceOverride: transition.source)
        }
        return true
    }

    @discardableResult
    func redoMarkdownEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let transition = documentEditCoordinator.redoMarkdown(session: session) else { return false }

        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            renderMarkdown(tabID: tabID, sourceOverride: transition.source)
        }
        return true
    }

    func keepLocalMarkdownEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession else { return }
        applyMarkdownSaveOutcome(
            documentEditCoordinator.commitMarkdown(url: tabs[index].url, source: session.currentSource),
            tabID: tabID,
            renderWhenNotEditing: true
        )
    }

    func useExternalMarkdownEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let conflict = session.conflict else { return }
        applyMarkdownTransition(
            documentEditCoordinator.useExternal(
                session: session,
                externalSource: conflict.externalSource
            ),
            at: index
        )
        tabs[index].diffSession = nil
        renderMarkdown(tabID: tabID)
    }

    @discardableResult
    private func saveMarkdownEdit(tabID: String, finishEditing: Bool = false) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession else { return false }

        guard session.currentSource != session.baseSource else {
            if finishEditing {
                tabs[index].markdownEditSession?.isEditing = false
                tabs[index].diffSession = nil
                renderMarkdown(tabID: tabID)
            }
            return true
        }

        let localSource = session.currentSource
        tabs[index].markdownEditSession?.saveState = .saving
        let outcome = await documentEditCoordinator.saveMarkdown(
            url: tabs[index].url,
            baseSource: session.baseSource,
            localSource: localSource
        )
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[currentIndex].markdownEditSession?.currentSource == localSource else {
            return false
        }
        return applyMarkdownSaveOutcome(
            outcome,
            tabID: tabID,
            renderWhenNotEditing: true,
            finishEditing: finishEditing
        )
    }

    private func applyMarkdownTransition(
        _ transition: DocumentEditTransition,
        at index: Int
    ) {
        tabs[index].markdownSource = transition.source
        tabs[index].markdownBlocks = transition.markdownBlocks
        tabs[index].markdownEditSession = transition.session
    }

    private func applyJSONTransition(
        _ transition: DocumentEditTransition,
        at index: Int
    ) {
        tabs[index].jsonSource = transition.source
        tabs[index].jsonEditSession = transition.session
        if let cursorOffset = transition.jsonCursorUTF8Offset {
            tabs[index].jsonCursorUTF8Offset = cursorOffset
        }
        tabs[index].errorMessage = transition.jsonErrorMessage
    }

    @discardableResult
    private func applyMarkdownSaveOutcome(
        _ outcome: DocumentEditSaveOutcome,
        tabID: String,
        renderWhenNotEditing: Bool,
        finishEditing: Bool = false
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        switch outcome {
        case let .saved(source):
            tabs[index].markdownSource = source
            tabs[index].markdownBlocks = MarkdownBlockDocument(source: source).blocks
            tabs[index].markdownEditSession?.baseSource = source
            tabs[index].markdownEditSession?.currentSource = source
            tabs[index].markdownEditSession?.saveState = .saved
            tabs[index].markdownEditSession?.conflict = nil
            if tabs[index].diffSession?.mode == .savedOnDisk {
                tabs[index].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: source
                )
            }
            tabs[index].errorMessage = nil
            if finishEditing {
                tabs[index].markdownEditSession?.isEditing = false
                tabs[index].diffSession = nil
            }
            if renderWhenNotEditing && tabs[index].markdownEditSession?.isEditing != true {
                renderMarkdown(tabID: tabID)
            }
            return true
        case let .conflict(conflict):
            tabs[index].markdownEditSession?.saveState = .conflict
            tabs[index].markdownEditSession?.conflict = conflict
            return false
        case let .failed(message):
            tabs[index].markdownEditSession?.saveState = .failed
            tabs[index].errorMessage = message
            return false
        }
    }

    @discardableResult
    private func applyJSONSaveOutcome(
        _ outcome: DocumentEditSaveOutcome,
        tabID: String,
        finishEditing: Bool
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        switch outcome {
        case let .saved(source):
            tabs[index].jsonSource = source
            tabs[index].jsonEditSession?.baseSource = source
            tabs[index].jsonEditSession?.currentSource = source
            tabs[index].jsonEditSession?.saveState = .saved
            tabs[index].jsonEditSession?.conflict = nil
            if tabs[index].diffSession?.mode == .savedOnDisk {
                tabs[index].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: source
                )
            }
            tabs[index].errorMessage = nil
            if finishEditing {
                tabs[index].jsonEditSession?.isEditing = false
                tabs[index].diffSession = nil
                renderJSON(tabID: tabID)
            }
            return true
        case let .conflict(conflict):
            tabs[index].jsonEditSession?.saveState = .conflict
            tabs[index].jsonEditSession?.isEditing = true
            tabs[index].jsonEditSession?.conflict = conflict
            return false
        case let .failed(message):
            tabs[index].jsonEditSession?.saveState = .failed
            tabs[index].jsonEditSession?.isEditing = true
            tabs[index].errorMessage = message
            return false
        }
    }

    func showFindBar() {
        guard let kind = activeTab?.kind,
              [.markdown, .latex, .pdf, .json, .csv, .docx].contains(kind) else { return }
        isFindBarVisible = true
    }

    func setFindTarget(_ target: FindTarget) {
        guard findTarget != target else { return }
        findTarget = target
        findMatchCount = nil
    }

    func setFindMatchCount(_ count: Int) {
        findMatchCount = count
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
        panel.prompt = "Choose Root"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chooseLatexRoot(url)
    }

    func approveLatexExternalDependencies() {
        guard let request = pendingLatexExternalDependencies else { return }
        workspaceSession.approveLatexExternalDependencies(
            request.dependencies,
            rootURL: request.rootURL,
            projectRoot: request.projectRoot
        )
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
            let documentState = workspaceSession.documentState(for: rootURL)
            tabs[oldIndex].isOutlineVisible = documentState.outlineVisible
            tabs[oldIndex].previewZoom = documentState.zoom ?? defaultZoom(for: .latex)
            tabs[oldIndex].isPreviewZoomCustomized = documentState.zoom != nil
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
        findTarget = .preview
        findMatchCount = nil
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

    func setPreviewZoomFromGesture(_ value: Double) {
        setPreviewZoom(value)
    }

    func resetPreviewZoom() {
        guard let activeTab else { return }
        setPreviewZoom(defaultZoom(for: activeTab.kind), customized: false)
    }

    func setDefaultMarkdownZoom(_ value: Double) {
        let normalizedValue = normalizedZoom(value)
        guard defaultMarkdownZoom != normalizedValue else { return }
        defaultMarkdownZoom = normalizedValue
        applyDefaultZoom(normalizedValue, to: .markdown)
        persistState()
    }

    func setDefaultLatexZoom(_ value: Double) {
        let normalizedValue = normalizedZoom(value)
        guard defaultLatexZoom != normalizedValue else { return }
        defaultLatexZoom = normalizedValue
        applyDefaultZoom(normalizedValue, to: .latex)
        persistState()
    }

    func setLatexShellEscapeMode(_ mode: LatexShellEscapeMode) {
        guard latexShellEscapeMode != mode else { return }
        latexShellEscapeMode = mode
        persistState()
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

    private func setPreviewZoom(_ value: Double, customized: Bool = true) {
        let normalizedValue = normalizedZoom(value)
        previewZoom = normalizedValue
        guard let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }
        tabs[index].previewZoom = normalizedValue
        tabs[index].isPreviewZoomCustomized = customized
        persistState()
    }

    private func defaultZoom(for kind: DocumentKind) -> Double {
        switch kind {
        case .markdown:
            return defaultMarkdownZoom
        case .latex, .pdf:
            return defaultLatexZoom
        case .json, .docx, .other:
            return 1.0
        case .csv:
            return 1.0
        }
    }

    private func applyDefaultZoom(_ value: Double, to kind: DocumentKind) {
        for index in tabs.indices where
            (tabs[index].kind == kind || (kind == .latex && tabs[index].kind == .pdf))
                && !tabs[index].isPreviewZoomCustomized {
            tabs[index].previewZoom = value
        }
        syncPreviewZoomToActiveTab()
    }

    private func normalizedZoom(_ value: Double) -> Double {
        min(max(value, 0.7), 2.0)
    }

    func cycleTheme() {
        setTheme(theme == .light ? .dark : .light)
    }

    func setTheme(_ preference: AppThemePreference) {
        guard theme != preference else { return }
        theme = preference
        persistState()
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        persistState()
    }

    func setSidebarWidth(_ width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
        persistState()
    }

    func resizeSidebar(to width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
    }

    func selectTab(number: Int) {
        guard tabs.indices.contains(number) else { return }
        selectTab(id: tabs[number].id)
    }

    func selectNextTab() {
        var session = documentTabSession
        guard session.selectNext() else { return }
        hideFindBar()
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func selectTab(id: String) {
        var session = documentTabSession
        guard session.select(id: id) else { return }
        hideFindBar()
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func persistState() {
        workspaceSession.persist(
            rootURL: rootURL,
            tabs: tabs,
            activeTabID: activeTabID,
            expandedPaths: expandedPaths,
            treeScrollOffset: treeScrollOffset,
            compatibleOnly: compatibleOnly,
            configuration: WorkspaceSessionConfiguration(
                theme: theme.rawValue,
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                latexShellEscapeMode: latexShellEscapeMode.rawValue,
                defaultMarkdownZoom: defaultMarkdownZoom,
                defaultLatexZoom: defaultLatexZoom
            )
        )
    }

    private func restoreTabs() {
        guard let rootURL else {
            tabs = []
            activeTabID = nil
            workspaceTreeSession.reset(rootURL: nil)
            return
        }

        let savedWorkspace = workspaceSession.workspaceState(for: rootURL)
        workspaceTreeSession.restore(
            expandedPaths: Set(savedWorkspace.expandedPaths),
            treeScrollOffset: savedWorkspace.treeScrollOffset,
            compatibleOnly: savedWorkspace.compatibleOnly,
            automaticSingleChildExpansion: !workspaceSession.hasWorkspaceState(for: rootURL)
        )
        let available = savedWorkspace.tabPaths
            .map(URL.init(fileURLWithPath:))
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap { url -> DocumentTab? in
            let kind = DocumentKind(url: url)
            let documentState = workspaceSession.documentState(for: url)
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
                status: kind == .docx ? .ready : (documentOpenCoordinator.isPreviewable(kind) ? .idle : .unavailable),
                isOutlineVisible: documentState.outlineVisible,
                previewZoom: documentState.zoom ?? defaultZoom(for: kind),
                isPreviewZoomCustomized: documentState.zoom != nil,
                previewPageIndex: documentState.pdfReadingPosition?.pageIndex ?? 0,
                markdownReadingPosition: documentState.markdownReadingPosition,
                pdfReadingPosition: documentState.pdfReadingPosition
            )
        }
        let session = DocumentTabSession(
            tabs: available,
            activeTabID: savedWorkspace.activeTabPath
        )
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        restoreSnapshots(for: rootURL)
    }

    private func syncPreviewZoomToActiveTab() {
        previewZoom = tabs.first(where: { $0.id == activeTabID })?.previewZoom ?? 1.0
    }

    private func renderActiveTabIfNeeded() {
        guard let activeTabID,
              let tab = tabs.first(where: { $0.id == activeTabID }),
              tab.kind == .markdown || tab.kind == .latex || tab.kind == .json || tab.kind == .csv || tab.kind == .pdf || tab.kind == .docx else {
            stopWatchingActiveFiles()
            return
        }

        startWatchingActiveFiles(
            [tab.url] + tab.previewDependencies + tab.previewExternalDependencies
        )
        let hasPreview: Bool
        switch tab.kind {
        case .markdown:
            hasPreview = tab.previewHTML != nil
        case .latex:
            hasPreview = tab.previewPDFData != nil
        case .pdf:
            hasPreview = tab.previewPDFData != nil
        case .json:
            hasPreview = tab.previewJSON != nil
        case .csv:
            hasPreview = tab.previewCSV != nil
        case .docx:
            return
        case .other:
            hasPreview = false
        }
        if !hasPreview || tab.status != .ready {
            if tab.kind == .markdown {
                renderMarkdown(tabID: activeTabID)
            } else if tab.kind == .latex {
                renderLatex(tabID: activeTabID)
            } else if tab.kind == .json {
                renderJSON(tabID: activeTabID)
            } else if tab.kind == .csv {
                renderCSV(tabID: activeTabID)
            } else if tab.kind == .pdf {
                renderPDF(tabID: activeTabID)
            }
        }
    }

    private func startWatchingActiveFiles(_ urls: [URL]) {
        guard let activeTabID else { return }
        activeDocumentWatcher.start(tabID: activeTabID, urls: urls)
    }

    private func stopWatchingActiveFiles() {
        activeDocumentWatcher.stop()
    }

    private func restartWatchingActiveFiles(_ urls: [URL]) {
        startWatchingActiveFiles(urls)
    }

    private func handleActiveDocumentChange(_ change: ActiveDocumentChange) {
        guard activeTabID == change.tabID,
              let tab = tabs.first(where: { $0.id == change.tabID }) else { return }

        if let session = tab.markdownEditSession,
           session.isEditing,
           session.currentSource == session.baseSource {
            // The active source editor owns the cursor while its latest
            // version is already on disk. Reconcile the next external event
            // after the user leaves the editor.
            if tab.diffSession?.mode == .savedOnDisk {
                Task { @MainActor [weak self] in
                    await self?.refreshDiskDiffBaseline(tabID: change.tabID)
                }
            }
            return
        }
        if let session = tab.jsonEditSession,
           session.isEditing,
           session.currentSource == session.baseSource {
            if tab.diffSession?.mode == .savedOnDisk {
                Task { @MainActor [weak self] in
                    await self?.refreshDiskDiffBaseline(tabID: change.tabID)
                }
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self,
                  self.activeTabID == change.tabID,
                  let currentTab = self.tabs.first(where: { $0.id == change.tabID }) else { return }

            switch currentTab.kind {
            case .latex:
                self.renderLatex(tabID: change.tabID)
            case .json:
                if let session = currentTab.jsonEditSession,
                   session.currentSource != session.baseSource {
                    await self.handleExternalJSONChange(tabID: change.tabID)
                } else {
                    self.renderJSON(tabID: change.tabID)
                }
            case .csv:
                if let session = currentTab.csvEditSession,
                   session.currentSource != session.baseSource {
                    await self.handleExternalCSVChange(tabID: change.tabID)
                } else {
                    self.renderCSV(tabID: change.tabID)
                }
            case .pdf:
                self.renderPDF(tabID: change.tabID)
            case .docx:
                self.refreshDocx(tabID: change.tabID)
            case .markdown:
                if let session = currentTab.markdownEditSession,
                   session.currentSource != session.baseSource {
                    await self.handleExternalMarkdownChange(tabID: change.tabID)
                } else {
                    self.renderMarkdown(tabID: change.tabID)
                }
            case .other:
                break
            }
        }
    }

    private func handleExternalMarkdownChange(tabID: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              session.currentSource != session.baseSource else {
            renderMarkdown(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].url)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].markdownEditSession?.currentSource == session.currentSource else { return }
            if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: externalSource
                )
            }
            guard externalSource != session.baseSource else { return }

            tabs[currentIndex].markdownEditSession?.saveState = .conflict
            tabs[currentIndex].markdownEditSession?.isEditing = true
            tabs[currentIndex].markdownEditSession?.conflict = MarkdownConflict(
                localSource: session.currentSource,
                externalSource: externalSource,
                blockIDs: []
            )
        } catch {
            tabs[index].markdownEditSession?.saveState = .failed
            tabs[index].markdownEditSession?.isEditing = true
            tabs[index].errorMessage = error.localizedDescription
        }
    }

    private func handleExternalJSONChange(tabID: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].jsonEditSession,
              session.currentSource != session.baseSource else {
            renderJSON(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].url)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].jsonEditSession?.currentSource == session.currentSource else { return }
            if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: externalSource
                )
            }

            if externalSource == session.baseSource {
                tabs[currentIndex].jsonEditSession?.saveState = .unsaved
            } else {
                tabs[currentIndex].jsonEditSession?.saveState = .conflict
                tabs[currentIndex].jsonEditSession?.isEditing = true
                tabs[currentIndex].jsonEditSession?.conflict = MarkdownConflict(
                    localSource: session.currentSource,
                    externalSource: externalSource,
                    blockIDs: []
                )
            }
        } catch {
            tabs[index].jsonEditSession?.saveState = .failed
            tabs[index].jsonEditSession?.isEditing = true
            tabs[index].errorMessage = error.localizedDescription
        }
    }

    private func handleExternalCSVChange(tabID: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].csvEditSession,
              session.currentSource != session.baseSource else {
            renderCSV(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].url)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].csvEditSession?.currentSource == session.currentSource else { return }
            if externalSource == session.baseSource {
                tabs[currentIndex].csvEditSession?.saveState = .unsaved
            } else {
                tabs[currentIndex].csvEditSession?.saveState = .conflict
                tabs[currentIndex].csvEditSession?.conflict = MarkdownConflict(
                    localSource: session.currentSource,
                    externalSource: externalSource,
                    blockIDs: []
                )
            }
        } catch {
            tabs[index].csvEditSession?.saveState = .failed
            tabs[index].errorMessage = error.localizedDescription
        }
    }

    private func refreshDiskDiffBaseline(tabID: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].diffSession?.mode == .savedOnDisk else { return }
        guard let source = try? await documentEditCoordinator.readSource(at: tabs[index].url),
              let currentIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
            label: "Saved on Disk",
            source: source
        )
    }

    private func renderLatex(
        tabID: String,
        rootURL explicitRootURL: URL? = nil,
        force: Bool = false
    ) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let projectRoot = rootURL else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .latex,
            projectRoot: projectRoot,
            markdownSourceOverride: nil,
            latexRootURL: explicitRootURL ?? storedLatexRoot(for: projectRoot),
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: approvedLatexExternalPaths,
            force: force
        ))
    }

    private func storedLatexRoot(for projectRoot: URL) -> URL? {
        guard let rootURL = workspaceSession.storedLatexRoot(for: projectRoot)?.standardizedFileURL else {
            return nil
        }
        guard isRegularFile(rootURL),
              isInside(rootURL, project: projectRoot.standardizedFileURL) else {
            return nil
        }
        return rootURL
    }

    private func storeLatexRoot(_ rootURL: URL, for projectRoot: URL) {
        workspaceSession.storeLatexRoot(rootURL, for: projectRoot)
    }

    private var approvedLatexExternalPaths: [String: Set<String>] {
        guard let rootURL else { return [:] }
        return workspaceSession.approvedLatexExternalPaths(for: rootURL)
    }

    private func renderMarkdown(tabID: String, sourceOverride: String? = nil) {
        guard let tab = tabs.first(where: { $0.id == tabID }), tab.kind == .markdown else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .markdown,
            projectRoot: rootURL,
            markdownSourceOverride: sourceOverride,
            latexRootURL: nil,
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: [:],
            force: false
        ))
    }

    private func refreshDocx(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .docx else { return }

        tabs[index].status = .ready
        tabs[index].isStale = false
        tabs[index].errorMessage = nil
        tabs[index].previewUpdatedAt = Date()
    }

    private func renderJSON(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }), tab.kind == .json else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .json,
            projectRoot: rootURL,
            markdownSourceOverride: nil,
            latexRootURL: nil,
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: [:],
            force: false
        ))
    }

    private func renderCSV(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }), tab.kind == .csv else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .csv,
            projectRoot: rootURL,
            markdownSourceOverride: nil,
            latexRootURL: nil,
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: [:],
            force: false
        ))
    }

    private func renderPDF(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }), tab.kind == .pdf else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .pdf,
            projectRoot: rootURL,
            markdownSourceOverride: nil,
            latexRootURL: nil,
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: [:],
            force: false
        ))
    }

    private func handleDocumentRenderEvent(_ event: DocumentRenderEvent) {
        switch event {
        case let .started(tabID):
            guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
            tabs[index].status = .updating
            tabs[index].errorMessage = nil

        case let .ready(tabID, output):
            guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
            switch output.kind {
            case .markdown:
                tabs[index].previewHTML = output.html
                tabs[index].previewBaseURL = output.baseURL
                tabs[index].markdownOutline = output.outline
                tabs[index].markdownSource = output.source
                tabs[index].markdownBlocks = output.blocks
            case .json:
                tabs[index].previewJSON = output.json
                tabs[index].jsonSource = output.source
            case .csv:
                tabs[index].previewCSV = output.csv
            case .latex, .pdf:
                tabs[index].previewPDFData = output.pdfData
                tabs[index].previewHTML = nil
                tabs[index].previewJSON = nil
                tabs[index].previewBaseURL = nil
            case .docx, .other:
                return
            }
            tabs[index].previewUpdatedAt = Date()
            tabs[index].previewDependencies = output.dependencies
            tabs[index].previewExternalDependencies = output.externalDependencies
            tabs[index].status = .ready
            tabs[index].isStale = false
            tabs[index].errorMessage = nil
            if activeTabID == tabID {
                restartWatchingActiveFiles(
                    [tabs[index].url] + output.dependencies + output.externalDependencies
                )
            }

        case let .failed(tabID, failure):
            guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
            tabs[index].status = failure.status
            tabs[index].isStale = tabs[index].previewHTML != nil
                || tabs[index].previewJSON != nil
                || tabs[index].previewCSV != nil
                || tabs[index].previewPDFData != nil
            tabs[index].errorMessage = failure.message
            if let candidates = failure.latexRootSelectionCandidates,
               let projectRoot = failure.projectRoot {
                pendingLatexRootSelection = LatexRootSelectionRequest(
                    id: tabID,
                    tabID: tabID,
                    openedFile: tabs[index].url,
                    projectRoot: projectRoot,
                    candidates: candidates
                )
            }
            if let rootURL = failure.latexRootURL,
               let dependencies = failure.latexExternalDependencies,
               let projectRoot = failure.projectRoot {
                pendingLatexExternalDependencies = LatexExternalDependencyRequest(
                    id: tabID,
                    tabID: tabID,
                    rootURL: rootURL,
                    projectRoot: projectRoot,
                    dependencies: dependencies
                )
            }
            if activeTabID == tabID {
                restartWatchingActiveFiles(
                    [tabs[index].url]
                        + tabs[index].previewDependencies
                        + tabs[index].previewExternalDependencies
                )
            }
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        return values?.isRegularFile == true && values?.isDirectory != true
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
