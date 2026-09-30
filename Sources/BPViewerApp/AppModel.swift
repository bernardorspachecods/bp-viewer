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
    @Published private(set) var treeRevealTargetID: String?
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
    @Published var pendingFileMoveRequest: PendingFileMoveRequest?
    @Published var showingFileMoveConfirmation = false
    @Published var pendingInvalidJSONTabID: String?
    @Published var showingInvalidJSONConfirmation = false
    @Published private(set) var pendingGitDiscardTabID: String?
    @Published var showingGitDiscardConfirmation = false
    @Published var pendingLatexRootSelection: LatexRootSelectionRequest?
    @Published var pendingLatexExternalDependencies: LatexExternalDependencyRequest?
    @Published var isSnapshotCaptureActive = false
    @Published private(set) var isPerformingFileOperation = false

    private let workspaceSession: WorkspaceSessionCoordinator
    private let persistsSharedConfiguration: Bool
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
    private let documentDiffCoordinator: DocumentDiffCoordinator
    private lazy var activeDocumentWatcher = ActiveDocumentWatcher { [weak self] change in
        self?.handleActiveDocumentChange(change)
    }
    private var pendingOpenURLs: [URL] = []
    private var openFilesObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private weak var pendingWindow: NSWindow?
    private var pendingBatchCloseIDs: Set<String> = []
    private var readingPositionPersistenceTask: Task<Void, Never>?
    private var fileOperationTask: Task<Void, Never>?
    private var gitDiscardTask: Task<Void, Never>?
    private var latexRenderDebounceTasks: [String: Task<Void, Never>] = [:]
    private var markdownRenderDebounceTasks: [String: Task<Void, Never>] = [:]
    private var markdownUndoGroupTimes: [String: TimeInterval] = [:]
    private var activeSecurityScopedRootURL: URL?
    private weak var attachedWindow: NSWindow?

    init(
        documentDiffCoordinator: DocumentDiffCoordinator = DocumentDiffCoordinator(),
        workspaceSession: WorkspaceSessionCoordinator = WorkspaceSessionCoordinator(),
        initialRootURL: URL? = nil,
        restoresLastWorkspace: Bool = true,
        persistsSharedConfiguration: Bool = true
    ) {
        self.documentDiffCoordinator = documentDiffCoordinator
        self.workspaceSession = workspaceSession
        self.persistsSharedConfiguration = persistsSharedConfiguration
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
                guard let self, self.shouldHandleWindowEvents else { return }
                self.openExternalURLs(urls)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard self?.shouldHandleWindowEvents == true else { return event }

            if flags == [.control], event.keyCode == 48 {
                Task { @MainActor [weak self] in
                    self?.selectNextTab()
                }
                return nil
            }

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "s",
               let tabID = self?.activeTabID,
               let tab = self?.activeTab,
               let session = tab.markdownEditSession,
               tab.isUntitled
                    || session.currentSource != session.baseSource
                    || session.isEditing {
                Task { @MainActor [weak self] in
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       textView.isEditable {
                        self?.updateMarkdownEditing(
                            tabID: tabID,
                            text: textView.string,
                            rebuildBlocks: false
                        )
                    }
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

            if flags == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "s",
               let tabID = self?.activeTabID,
               let session = self?.activeTab?.latexEditSession,
               session.currentSource != session.baseSource {
                Task { @MainActor [weak self] in
                    await self?.saveLatexEdit(tabID: tabID)
                }
                return nil
            }

            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               let tabID = self?.activeTabID,
               let session = self?.activeTab?.markdownEditSession,
               (flags.contains(.shift) ? !session.redoSources.isEmpty : !session.undoSources.isEmpty) {
                let redo = flags.contains(.shift)
                Task { @MainActor [weak self] in
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       textView.isEditable {
                        self?.updateMarkdownEditing(
                            tabID: tabID,
                            text: textView.string,
                            rebuildBlocks: false
                        )
                    }
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

            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               let session = self?.activeTab?.latexEditSession,
               (flags.contains(.shift) ? !session.redoSources.isEmpty : !session.undoSources.isEmpty) {
                let redo = flags.contains(.shift)
                Task { @MainActor [weak self] in
                    if redo {
                        self?.redoLatexEdit()
                    } else {
                        self?.undoLatexEdit()
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
                self.stopSecurityScopedAccess()
            }
        }

        if let initialRootURL, isDirectory(initialRootURL) {
            openRoot(initialRootURL)
        } else if restoresLastWorkspace,
                  let path = workspaceSession.activeWorkspacePath {
            let pathURL = URL(fileURLWithPath: path)
            let url = (try? workspaceSession.resolveSecurityScopedBookmark(for: pathURL))?.url ?? pathURL
            if FileManager.default.fileExists(atPath: url.path), isDirectory(url) {
                beginSecurityScopedAccess(to: url)
                rootURL = url
                workspaceTreeSession.reset(rootURL: url)
                reloadTree()
                restoreTabs()
            }
        }
    }

    var shouldHandleWindowEvents: Bool {
        guard let attachedWindow else { return true }
        return attachedWindow.isKeyWindow || attachedWindow.isMainWindow
    }

    var nativeWindow: NSWindow? {
        attachedWindow
    }

    func attach(to window: NSWindow) {
        attachedWindow = window
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
        WorkspaceWindowManager.shared.openWorkspace(url, from: self)
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
        _ = workspaceSession.storeSecurityScopedBookmark(for: url)
        let accessibleRoot = (try? workspaceSession.resolveSecurityScopedBookmark(for: url))?.url ?? url
        stopSecurityScopedAccess()
        beginSecurityScopedAccess(to: accessibleRoot)
        let standardizedRoot = accessibleRoot.standardizedFileURL
        rootURL = standardizedRoot
        workspaceTreeSession.reset(rootURL: standardizedRoot)
        tabs = []
        activeTabID = nil
        restoreTabs()
        reloadTree()
        persistState()
    }

    private func beginSecurityScopedAccess(to url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        activeSecurityScopedRootURL = url
    }

    private func stopSecurityScopedAccess() {
        guard let activeSecurityScopedRootURL else { return }
        activeSecurityScopedRootURL.stopAccessingSecurityScopedResource()
        self.activeSecurityScopedRootURL = nil
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

    func collapseAllFolders() {
        workspaceTreeSession.collapseAllFolders()
        persistState()
    }

    func collapseFolder(_ node: FileNode) {
        guard node.isDirectory else { return }
        workspaceTreeSession.collapseFolder(node.id)
        persistState()
    }

    func revealInSidebar(_ url: URL) {
        guard let rootURL, isURL(url, inside: rootURL) else { return }
        treeQuery = ""
        treeRevealTargetID = relativePath(of: url, from: rootURL)
        workspaceTreeSession.reveal(url: url)
        persistState()
    }

    func clearTreeRevealTarget() {
        treeRevealTargetID = nil
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
        readingPositionPersistenceTask?.cancel()
        readingPositionPersistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persistState()
        }
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

    func createNewMarkdownDocument(source: String = "") {
        var tab = DocumentTab.untitledMarkdown()
        let transition = documentEditCoordinator.beginMarkdown(source: source)
        var editSession = transition.session
        editSession.saveState = .unsaved
        tab.markdownSource = source
        tab.markdownBlocks = transition.markdownBlocks
        tab.markdownEditSession = editSession

        var session = documentTabSession
        _ = session.open(tab)
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
    }

    func createSavedMarkdownDocument(source: String, at destinationURL: URL) async -> Bool {
        createNewMarkdownDocument(source: source)
        guard let tabID = activeTabID,
              let session = tabs.first(where: { $0.id == tabID })?.markdownEditSession else {
            return false
        }
        return commitUntitledMarkdown(
            tabID: tabID,
            session: session,
            selectedURL: destinationURL,
            finishEditing: true
        )
    }

    func reload(_ node: FileNode) {
        guard !node.isDirectory else { return }
        let tabIDsBeforeOpening = Set(tabs.map(\.id))
        guard let tabID = openDocument(url: node.url) else { return }
        guard tabIDsBeforeOpening.contains(tabID) else { return }
        refreshTab(tabID: tabID)
    }

    func reload(_ tab: DocumentTab) {
        guard let node = workspaceFileNode(for: tab) else { return }
        reload(node)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyPath(_ url: URL) {
        copyText(FilePathCopy.string(for: url))
    }

    func rename(_ node: FileNode) {
        guard let rootURL else { return }

        let alert = NSAlert()
        alert.messageText = "Rename " + node.title
        alert.informativeText = "Enter a new name for this "
            + (node.isDirectory ? "folder" : "file")
            + "."
        let nameField = NSTextField(string: node.title)
        nameField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = nameField
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let newURL = try WorkspaceFileOperations.rename(
                itemAt: node.url,
                to: nameField.stringValue,
                in: rootURL
            )
            relocateOpenTabs(from: node.url, to: newURL)
            if node.isDirectory {
                workspaceTreeSession.relocateExpandedPaths(
                    from: node.relativePath,
                    to: relativePath(of: newURL, from: rootURL)
                )
            }
            refreshTreeAfterFileOperation(in: [node.url.deletingLastPathComponent()])
            persistState()
        } catch {
            showFileOperationError(error)
        }
    }

    func rename(_ tab: DocumentTab) {
        guard let node = workspaceFileNode(for: tab) else { return }
        rename(node)
    }

    @discardableResult
    func moveFiles(at sourceURLs: [URL], to destinationDirectory: URL) -> Bool {
        guard rootURL != nil,
              !sourceURLs.isEmpty,
              !showingFileMoveConfirmation else { return false }

        pendingFileMoveRequest = PendingFileMoveRequest(
            id: UUID().uuidString,
            sourceURLs: sourceURLs.map { $0.standardizedFileURL },
            destinationDirectory: destinationDirectory.standardizedFileURL
        )
        showingFileMoveConfirmation = true
        return true
    }

    @discardableResult
    func moveFile(at sourceURL: URL, to destinationDirectory: URL) -> Bool {
        moveFiles(at: [sourceURL], to: destinationDirectory)
    }

    var pendingFileMoveTitle: String {
        guard let request = pendingFileMoveRequest else { return "Move Item?" }
        if request.sourceURLs.count == 1,
           let title = request.itemTitles.first {
            return "Move \(title)?"
        }
        return "Move \(request.sourceURLs.count) items?"
    }

    var pendingFileMoveMessage: String {
        guard let request = pendingFileMoveRequest else { return "" }
        let destination = request.destinationDirectory.lastPathComponent
        if request.sourceURLs.count == 1,
           let title = request.itemTitles.first {
            return "\(title) will be moved to \(destination)."
        }
        let titles = request.itemTitles.joined(separator: ", ")
        return "\(titles) will be moved to \(destination)."
    }

    func cancelFileMove() {
        pendingFileMoveRequest = nil
        showingFileMoveConfirmation = false
    }

    func confirmFileMove() {
        guard let request = pendingFileMoveRequest,
              let rootURL else {
            cancelFileMove()
            return
        }

        pendingFileMoveRequest = nil
        showingFileMoveConfirmation = false

        var affectedDirectories = Set<URL>()
        var movedAny = false
        for sourceURL in request.sourceURLs {
            let sourceIsDirectory = isDirectory(sourceURL)
            do {
                let newURL = try WorkspaceFileOperations.move(
                    itemAt: sourceURL,
                    to: request.destinationDirectory,
                    in: rootURL
                )
                relocateOpenTabs(from: sourceURL, to: newURL)
                if sourceIsDirectory {
                    workspaceTreeSession.relocateExpandedPaths(
                        from: relativePath(of: sourceURL, from: rootURL),
                        to: relativePath(of: newURL, from: rootURL)
                    )
                }
                affectedDirectories.insert(sourceURL.deletingLastPathComponent())
                affectedDirectories.insert(request.destinationDirectory)
                movedAny = true
            } catch {
                showFileOperationError(error)
            }
        }

        guard movedAny else { return }
        refreshTreeAfterFileOperation(in: Array(affectedDirectories))
        persistState()
    }

    func duplicate(_ node: FileNode) {
        guard !node.isDirectory,
              let rootURL,
              !isPerformingFileOperation else { return }

        let sourceURL = node.url
        isPerformingFileOperation = true
        fileOperationTask = Task { @MainActor [weak self] in
            defer {
                self?.isPerformingFileOperation = false
                self?.fileOperationTask = nil
            }

            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try WorkspaceFileOperations.duplicate(
                        itemAt: sourceURL,
                        in: rootURL
                    )
                }.value

                guard let self,
                      self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }
                await Task.yield()
                self.refreshTreeAfterFileOperation(in: [sourceURL.deletingLastPathComponent()])
                self.persistState()
            } catch is CancellationError {
                return
            } catch {
                self?.showFileOperationError(error)
            }
        }
    }

    func duplicate(_ tab: DocumentTab) {
        guard let node = workspaceFileNode(for: tab) else { return }
        duplicate(node)
    }

    private func refreshTreeAfterFileOperation(in directories: [URL]) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.workspaceTreeSession.refreshAfterFileOperation(in: directories)
            self.persistState()
        }
    }

    func delete(_ node: FileNode) {
        guard let rootURL else { return }
        let affectedTabs = tabs.filter { isURL($0.url, inside: node.url) }
        guard !affectedTabs.contains(where: hasUnsavedChanges(in:)) else {
            showFileOperationError(
                NSError(
                    domain: "BPViewer.FileOperations",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Close or save this item before moving it to the Trash."]
                )
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = "Move " + node.title + " to the Trash?"
        alert.informativeText = "This " + (node.isDirectory ? "folder" : "file") + " and its contents will be moved to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try WorkspaceFileOperations.remove(itemAt: node.url, in: rootURL)
            closeTabsImmediately(Set(affectedTabs.map(\.id)))
            refreshTreeAfterFileOperation(in: [node.url.deletingLastPathComponent()])
            persistState()
        } catch {
            showFileOperationError(error)
        }
    }

    func delete(_ tab: DocumentTab) {
        guard let node = workspaceFileNode(for: tab) else { return }
        delete(node)
    }

    private func workspaceFileNode(for tab: DocumentTab) -> FileNode? {
        guard !tab.isUntitled,
              let rootURL,
              isURL(tab.url, inside: rootURL) else { return nil }
        return FileNode(
            id: tab.url.path,
            url: tab.url,
            relativePath: relativePath(of: tab.url, from: rootURL),
            isDirectory: false,
            kind: tab.kind,
            children: [],
            childrenLoaded: true
        )
    }

    private func relocateOpenTabs(from oldURL: URL, to newURL: URL) {
        let affectedTabs = tabs.filter { isURL($0.url, inside: oldURL) }
        guard !affectedTabs.isEmpty else { return }

        documentRenderCoordinator.cancel(tabIDs: affectedTabs.map(\.id))
        var relocatedIDs: [String: String] = [:]
        for index in tabs.indices {
            let oldID = tabs[index].id
            guard isURL(tabs[index].url, inside: oldURL) else { continue }
            tabs[index].relocate(from: oldURL, to: newURL)
            tabs[index].status = .idle
            tabs[index].isStale = false
            tabs[index].errorMessage = nil
            relocatedIDs[oldID] = tabs[index].id
        }
        if let activeTabID, let relocatedActiveID = relocatedIDs[activeTabID] {
            self.activeTabID = relocatedActiveID
        }
        restartWatchingActiveFilesIfNeeded()
    }

    private func restartWatchingActiveFilesIfNeeded() {
        guard let activeTabID,
              let tab = tabs.first(where: { $0.id == activeTabID }) else {
            stopWatchingActiveFiles()
            return
        }
        startWatchingActiveFiles(
            [tab.url, tab.editableSourceURL] + tab.previewDependencies + tab.previewExternalDependencies
        )
        renderActiveTabIfNeeded()
    }

    private func isURL(_ url: URL, inside parent: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath ? "." : String(path.dropFirst(rootPath.count + 1))
    }

    private func showFileOperationError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    var canCaptureActivePreview: Bool {
        guard let activeTab else { return false }
        return activeTab.previewHTML != nil
            || activeTab.previewJSON != nil
            || activeTab.previewCSV != nil
            || activeTab.previewPDFData != nil
            || activeTab.previewImageData != nil
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
            WorkspaceWindowManager.shared.openWorkspace(desiredRoot, opening: files, from: self)
        }
    }

    func openDroppedURLs(_ urls: [URL]) {
        let resolvedURLs = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        if let directory = resolvedURLs.first(where: { isDirectory($0) }) {
            WorkspaceWindowManager.shared.openWorkspace(directory, from: self)
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

    @discardableResult
    func openDocument(url: URL) -> String? {
        guard let result = documentOpenCoordinator.resolve(
            url,
            workspaceRoot: rootURL,
            storedLatexRoot: rootURL.flatMap { workspaceSession.storedLatexRoot(for: $0) }
        ) else { return nil }
        guard case let .preview(documentURL, kind, contextURL) = result else {
            if case let .external(externalURL) = result {
                NSWorkspace.shared.open(externalURL)
            }
            return nil
        }

        let id = documentURL.path
        var session = documentTabSession
        if let existingTab = session.tabs.first(where: { $0.id == id }) {
            _ = session.select(id: existingTab.id)
            let sourceURL = contextURL ?? documentURL
            let isBibliography = sourceURL.pathExtension.lowercased() == "bib"
            let isNewSource = sourceURL.standardizedFileURL
                != existingTab.editableSourceURL.standardizedFileURL
            if existingTab.kind == .latex,
               isNewSource || (isBibliography && existingTab.latexEditSession?.isEditing != true) {
                if !hasUnsavedChanges(in: existingTab),
                   let source = try? String(contentsOf: sourceURL, encoding: .utf8) {
                    _ = session.update(id: id) { tab in
                        let previousMode = tab.latexEditSession?.mode
                        tab.contextURL = contextURL
                        if previousMode != nil || isBibliography {
                            var editSession = documentEditCoordinator.beginLatex(source: source).session
                            editSession.mode = previousMode ?? .markdown
                            tab.latexEditSession = editSession
                            tab.latexCursorUTF8Offset = nil
                            tab.diffSession = nil
                        }
                    }
                }
            }
            applyDocumentTabSession(session)
            syncPreviewZoomToActiveTab()
            renderActiveTabIfNeeded()
            persistState()
            return id
        }

        let documentState = workspaceSession.documentState(for: documentURL)
        var tab = DocumentTab(
            id: id,
            url: documentURL,
            kind: kind,
            contextURL: contextURL,
            status: kind == .docx ? .ready : .updating,
            isOutlineVisible: documentState.outlineVisible,
            outlineWidth: documentState.outlineWidth,
            previewZoom: documentState.zoom ?? defaultZoom(for: kind),
            isPreviewZoomCustomized: documentState.zoom != nil,
            previewPageIndex: documentState.pdfReadingPosition?.pageIndex ?? 0,
            markdownReadingPosition: documentState.markdownReadingPosition,
            pdfReadingPosition: documentState.pdfReadingPosition
        )
        if kind == .latex,
           let contextURL,
           contextURL.pathExtension.lowercased() == "bib",
           let source = try? String(contentsOf: contextURL, encoding: .utf8) {
            tab.latexEditSession = documentEditCoordinator.beginLatex(source: source).session
        }

        _ = session.open(tab)
        applyDocumentTabSession(session)
        syncPreviewZoomToActiveTab()
        renderActiveTabIfNeeded()
        persistState()
        return id
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
        if isPendingWindowClose
            || showingPendingCloseConfirmation
            || showingFileMoveConfirmation
            || showingInvalidJSONConfirmation
            || showingGitDiscardConfirmation {
            return false
        }
        guard let tab = tabs.first(where: hasUnsavedChanges(in:)) else {
            return true
        }
        let unsavedTabs = tabs.filter(hasUnsavedChanges(in:))
        pendingWindow = window
        isPendingWindowClose = true
        pendingBatchCloseIDs = Set(unsavedTabs.map(\.id))
        presentPendingClose(for: tab, closesTab: false, unsavedCount: unsavedTabs.count)
        return false
    }

    private func presentPendingClose(
        for tab: DocumentTab,
        closesTab: Bool,
        unsavedCount: Int = 1
    ) {
        pendingCloseRequest = PendingCloseRequest(
            id: "\(closesTab ? "tab" : "window")-\(tab.id)",
            tabID: tab.id,
            title: tab.title,
            closesTab: closesTab,
            unsavedCount: unsavedCount
        )
        showingPendingCloseConfirmation = true
    }

    func cancelPendingClose() {
        let IDsToKeepEditing: Set<String> = pendingBatchCloseIDs.isEmpty
            ? Set(pendingCloseRequest.map { [$0.tabID] } ?? [])
            : pendingBatchCloseIDs
        for index in tabs.indices where IDsToKeepEditing.contains(tabs[index].id) {
            tabs[index].markdownEditSession?.isEditing = true
            tabs[index].jsonEditSession?.isEditing = true
            tabs[index].latexEditSession?.isEditing = true
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
        guard let request = pendingCloseRequest else {
            return false
        }
        let IDs = request.closesTab || pendingBatchCloseIDs.isEmpty
            ? [request.tabID]
            : Array(pendingBatchCloseIDs)
        return IDs.allSatisfy { tabID in
            guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
            guard tab.kind == .json else { return true }
            return tab.jsonEditSession?.saveState != .failed && tab.errorMessage == nil
        }
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
        } else if isPendingWindowClose && !isPendingRootChange {
            let IDs = pendingBatchCloseIDs
            for candidate in tabs where IDs.contains(candidate.id) {
                discardChanges(in: candidate)
            }
            pendingBatchCloseIDs.removeAll()
            let window = pendingWindow
            pendingWindow = nil
            isPendingWindowClose = false
            window?.close()
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

        if !closesTab && isPendingWindowClose && !isPendingRootChange {
            let IDs = Array(pendingBatchCloseIDs)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for tabID in IDs {
                    guard let tab = self.tabs.first(where: { $0.id == tabID }) else { continue }
                    let saved: Bool
                    switch tab.kind {
                    case .markdown:
                        saved = await self.saveMarkdownEdit(tabID: tab.id)
                    case .json:
                        saved = await self.saveJSONEdit(tabID: tab.id)
                    case .csv:
                        saved = await self.saveCSVEdit(tabID: tab.id)
                    case .latex:
                        saved = await self.saveLatexEdit(tabID: tab.id)
                    default:
                        saved = true
                    }
                    guard saved else { return }
                }
                self.pendingBatchCloseIDs.removeAll()
                let window = self.pendingWindow
                self.pendingWindow = nil
                self.isPendingWindowClose = false
                window?.close()
            }
            return
        }

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
            case .latex:
                saved = await saveLatexEdit(tabID: tab.id, finishEditing: !closesTab)
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
        } else if let session = tabs[index].latexEditSession {
            tabs[index].latexEditSession?.currentSource = session.baseSource
            tabs[index].latexEditSession?.undoSources.removeAll()
            tabs[index].latexEditSession?.redoSources.removeAll()
            tabs[index].latexEditSession?.saveState = .saved
            tabs[index].latexEditSession?.conflict = nil
            tabs[index].latexEditSession?.isEditing = keepEditing
            tabs[index].errorMessage = nil
            tabs[index].diffSession = nil
            renderLatex(tabID: tab.id)
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

    func requestDiscardGitChanges(tabID: String) {
        guard !showingGitDiscardConfirmation,
              gitDiscardTask == nil,
              let tab = tabs.first(where: { $0.id == tabID }),
              (tab.kind == .markdown || tab.kind == .json || tab.kind == .latex),
              tab.presentationMode == .diff(.gitHead),
              tab.diffSession?.baseline != nil else { return }
        pendingGitDiscardTabID = tabID
        showingGitDiscardConfirmation = true
    }

    func cancelDiscardGitChanges() {
        pendingGitDiscardTabID = nil
        showingGitDiscardConfirmation = false
    }

    func confirmDiscardGitChanges() {
        guard let tabID = pendingGitDiscardTabID,
              let tab = tabs.first(where: { $0.id == tabID }) else {
            cancelDiscardGitChanges()
            return
        }

        pendingGitDiscardTabID = nil
        showingGitDiscardConfirmation = false
        gitDiscardTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.documentDiffCoordinator.restoreGitChanges(for: tab.editableSourceURL)
            self.applyGitDiscardOutcome(outcome, tabID: tabID)
            self.gitDiscardTask = nil
        }
    }

    var pendingGitDiscardTitle: String {
        guard let pendingGitDiscardTabID,
              let tab = tabs.first(where: { $0.id == pendingGitDiscardTabID }) else {
            return "This file"
        }
        return tab.title
    }

    private func applyGitDiscardOutcome(
        _ outcome: GitDocumentRestoreResolution,
        tabID: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        switch outcome {
        case let .restored(source):
            tabs[index].diffSession = nil
            tabs[index].errorMessage = nil
            if let session = tabs[index].markdownEditSession {
                tabs[index].markdownSource = source
                tabs[index].markdownBlocks = MarkdownBlockDocument(source: source).blocks
                tabs[index].markdownEditSession = MarkdownEditSession(
                    mode: session.mode,
                    isEditing: true,
                    baseSource: source,
                    currentSource: source
                )
                renderMarkdown(tabID: tabID)
            } else if let session = tabs[index].jsonEditSession {
                tabs[index].jsonSource = source
                tabs[index].jsonEditSession = MarkdownEditSession(
                    mode: session.mode,
                    isEditing: true,
                    baseSource: source,
                    currentSource: source
                )
                renderJSON(tabID: tabID)
            } else if let session = tabs[index].latexEditSession {
                tabs[index].latexEditSession = SourceEditSession(
                    mode: session.mode,
                    isEditing: true,
                    baseSource: source,
                    currentSource: source
                )
                renderLatex(tabID: tabID)
            }
            persistState()
        case let .unavailable(message), let .failed(message):
            tabs[index].errorMessage = message
            tabs[index].markdownEditSession?.saveState = .failed
            tabs[index].jsonEditSession?.saveState = .failed
            tabs[index].latexEditSession?.saveState = .failed
        }
    }

    private func closeTabImmediately(_ tab: DocumentTab) {
        guard tabs.contains(tab) else { return }
        latexRenderDebounceTasks[tab.id]?.cancel()
        latexRenderDebounceTasks[tab.id] = nil
        markdownRenderDebounceTasks[tab.id]?.cancel()
        markdownRenderDebounceTasks[tab.id] = nil
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
        if tab.isUntitled,
           let session = tab.markdownEditSession,
           session.currentSource.isEmpty {
            return false
        }
        if let session = tab.markdownEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        if let session = tab.jsonEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        if let session = tab.csvEditSession {
            return session.currentSource != session.baseSource || session.saveState != .saved
        }
        if let session = tab.latexEditSession {
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
        guard let activeTabID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshEditingSource(tabID: activeTabID)
            self.refreshTab(tabID: activeTabID)
            self.persistState()
        }
    }

    private func refreshEditingSource(tabID: String) async {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        switch tab.kind {
        case .markdown where tab.markdownEditSession?.isEditing == true:
            await handleExternalMarkdownChange(tabID: tabID)
        case .json where tab.jsonEditSession?.isEditing == true:
            await handleExternalJSONChange(tabID: tabID)
        case .latex where tab.latexEditSession?.isEditing == true:
            await handleExternalLatexChange(tabID: tabID)
        default:
            break
        }
    }

    private func refreshTab(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        if tab.kind == .markdown {
            renderMarkdown(tabID: tabID)
        } else if tab.kind == .latex {
            renderLatex(tabID: tabID, force: true)
        } else if tab.kind == .json {
            renderJSON(tabID: tabID)
        } else if tab.kind == .csv {
            renderCSV(tabID: tabID)
        } else if tab.kind == .pdf {
            renderPDF(tabID: tabID)
        } else if tab.kind == .image {
            renderImage(tabID: tabID)
        } else if tab.kind == .docx {
            refreshDocx(tabID: tabID)
        } else if let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].status = .unavailable
            tabs[index].errorMessage = nil
        }
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
        markdownUndoGroupTimes[tabID] = nil
        tabs[index].diffSession = nil
        applyMarkdownTransition(
            documentEditCoordinator.beginMarkdown(source: source, mode: mode),
            at: index
        )
    }

    func toggleDocumentDiff(mode: DocumentDiffMode, tabID: String) {
        guard let initialIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[initialIndex].presentationMode == .diff(mode) {
            tabs[initialIndex].restorePreviousPresentationMode()
            return
        }

        let returnMode = tabs[initialIndex].diffSession?.returnMode
            ?? tabs[initialIndex].presentationMode

        switch tabs[initialIndex].kind {
        case .markdown:
            if tabs[initialIndex].markdownEditSession?.isEditing != true {
                beginMarkdownEditing(tabID: tabID)
            }
        case .json:
            if tabs[initialIndex].jsonEditSession?.isEditing != true {
                beginJSONEditing(tabID: tabID)
            }
        case .latex:
            if tabs[initialIndex].latexEditSession?.isEditing != true {
                beginLatexEditing(tabID: tabID)
            }
        default:
            return
        }

        openDocumentDiff(tabID: tabID, mode: mode, returningTo: returnMode)
    }

    private func openDocumentDiff(
        tabID: String,
        mode: DocumentDiffMode,
        returningTo returnMode: DocumentPresentationMode
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .markdown
                || tabs[index].kind == .json
                || tabs[index].kind == .latex else { return }

        switch documentDiffCoordinator.baseline(for: mode, url: tabs[index].editableSourceURL) {
        case let .available(baseline):
            tabs[index].activateDiff(DocumentDiffSession(
                mode: mode,
                baseline: baseline,
                returnMode: returnMode
            ))
        case let .unavailable(message):
            tabs[index].activateDiff(DocumentDiffSession(
                mode: mode,
                unavailableMessage: message,
                returnMode: returnMode
            ))
        }
    }

    func updateMarkdownEditing(
        tabID: String,
        text: String,
        rebuildBlocks: Bool = true
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRecordUndo = markdownUndoGroupTimes[tabID].map {
            now - $0 >= 0.5
        } ?? true
        markdownUndoGroupTimes[tabID] = now
        guard
              let transition = documentEditCoordinator.updateMarkdown(
                  session: session,
                  source: text,
                  recordUndo: shouldRecordUndo,
                  markdownBlocks: rebuildBlocks ? nil : tabs[index].markdownBlocks
              ) else { return }

        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            scheduleMarkdownRender(tabID: tabID)
        }
    }

    func endMarkdownEditing(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession else { return }
        if tabs[index].isUntitled,
           session.currentSource != session.baseSource || session.saveState != .saved {
            tabs[index].markdownEditSession?.saveState = .saving
            Task { @MainActor [weak self] in
                _ = await self?.saveMarkdownEdit(tabID: tabID, finishEditing: true)
            }
            return
        }
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

    @discardableResult
    func saveMarkdownEditing(tabID: String) async -> Bool {
        await saveMarkdownEdit(tabID: tabID)
    }

    func beginLatexEditing(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .latex else { return }

        let sourceURL = tabs[index].editableSourceURL
        let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        tabs[index].diffSession = nil
        tabs[index].latexCursorUTF8Offset = nil
        tabs[index].latexEditSession = documentEditCoordinator.beginLatex(source: source).session
        tabs[index].errorMessage = nil
    }

    func openLatexCitation(tabID: String, sourceOffset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .latex,
              let session = tabs[index].latexEditSession,
              let projectRoot = rootURL,
              let key = LatexCitationLookup.citationKey(
                  atUTF8Offset: sourceOffset,
                  in: session.currentSource
              ),
              let bibliography = latexBibliographyEntry(
                  for: key,
                  tab: tabs[index],
                  projectRoot: projectRoot
              ) else { return }

        tabs[index].contextURL = bibliography.url == tabs[index].url ? nil : bibliography.url
        tabs[index].latexEditSession = documentEditCoordinator.beginLatex(
            source: bibliography.source
        ).session
        tabs[index].latexCursorUTF8Offset = bibliography.offset
        tabs[index].diffSession = nil
        tabs[index].errorMessage = nil
        if activeTabID == tabID {
            startWatchingActiveFiles(
                [tabs[index].url, tabs[index].editableSourceURL]
                    + tabs[index].previewDependencies
                    + tabs[index].previewExternalDependencies
            )
        }
    }

    func beginLatexEditing(tabID: String, pageIndex: Int, pointFromTopLeft: CGPoint) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let syncTeXData = tabs[index].latexSyncTeXData,
              let pdfData = tabs[index].previewPDFData,
              let projectRoot = rootURL else {
            beginLatexEditing(tabID: tabID)
            return
        }

        Task { @MainActor [weak self] in
            let location = await Task.detached {
                LatexSyncTeXLookup.location(
                    syncTeXData: syncTeXData,
                    pdfData: pdfData,
                    pageIndex: pageIndex,
                    pointFromTopLeft: pointFromTopLeft,
                    projectRoot: projectRoot
                )
            }.value
            guard let self,
                  let currentIndex = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

            // Wait for SyncTeX before exposing the editor. This keeps the
            // source view from briefly appearing at line one and then
            // jumping to the clicked location.
            if self.tabs[currentIndex].latexEditSession?.isEditing != true {
                self.beginLatexEditing(tabID: tabID)
            }
            if let location {
                self.applyLatexSourceLocation(
                    location,
                    tabID: tabID,
                    projectRoot: projectRoot
                )
            }
        }
    }

    func applyLatexSourceLocation(
        _ location: LatexSourceLocation,
        tabID: String,
        projectRoot: URL
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].latexEditSession?.isEditing == true else { return }

        let target: (url: URL, source: String, offset: Int)
        if location.url.pathExtension.lowercased() == "bbl",
           location.url.deletingPathExtension().lastPathComponent
               == tabs[index].url.deletingPathExtension().lastPathComponent {
            let key = tabs[index].latexGeneratedBibliographySource.flatMap {
                LatexCitationLookup.keyInGeneratedBibliography(
                    atLine: location.line,
                    in: $0
                )
            }
            guard let bibliography = key.flatMap({
                latexBibliographyEntry(
                    for: $0,
                    tab: tabs[index],
                    projectRoot: projectRoot
                )
            }) ?? latexFirstBibliography(tab: tabs[index], projectRoot: projectRoot) else { return }
            target = bibliography
        } else {
            guard let sourceURL = latexSourceURL(
                for: location.url,
                tab: tabs[index],
                projectRoot: projectRoot
            ), let source = try? String(contentsOf: sourceURL, encoding: .utf8) else { return }

            let offset = latexUTF8Offset(
                in: source,
                line: location.line,
                column: location.column
            )
            if sourceURL.pathExtension.lowercased() == "tex",
               let key = LatexCitationLookup.citationKey(
                   atUTF8Offset: offset,
                   in: source
               ),
               let bibliography = latexBibliographyEntry(
                   for: key,
                   tab: tabs[index],
                   projectRoot: projectRoot
               ) {
                target = bibliography
            } else {
                target = (sourceURL, source, offset)
            }
        }

        let currentURL = tabs[index].editableSourceURL.standardizedFileURL
        if target.url != currentURL {
            tabs[index].contextURL = target.url == tabs[index].url ? nil : target.url
            tabs[index].latexEditSession = documentEditCoordinator.beginLatex(
                source: target.source
            ).session
            tabs[index].diffSession = nil
            tabs[index].errorMessage = nil
            if activeTabID == tabID {
                startWatchingActiveFiles(
                    [tabs[index].url, tabs[index].editableSourceURL]
                        + tabs[index].previewDependencies
                        + tabs[index].previewExternalDependencies
                )
            }
        }
        tabs[index].latexCursorUTF8Offset = target.offset
    }

    private func latexSourceURL(
        for locationURL: URL,
        tab: DocumentTab,
        projectRoot: URL
    ) -> URL? {
        let candidate = locationURL.resolvingSymlinksInPath().standardizedFileURL
        if isInside(candidate, project: projectRoot),
           FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let dependencies = Set(
            tab.previewDependencies.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        )
        if let dependency = dependencies.first(where: { dependency in
            dependency.lastPathComponent == candidate.lastPathComponent
                && dependency.pathExtension.lowercased() == candidate.pathExtension.lowercased()
        }) {
            return dependency
        }

        guard !locationURL.path.hasPrefix("/") else { return nil }
        let relativeCandidate = projectRoot
            .appendingPathComponent(locationURL.path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return isInside(relativeCandidate, project: projectRoot)
            && FileManager.default.fileExists(atPath: relativeCandidate.path)
            ? relativeCandidate
            : nil
    }

    private func latexBibliographyEntry(
        for key: String,
        tab: DocumentTab,
        projectRoot: URL
    ) -> (url: URL, source: String, offset: Int)? {
        for url in latexBibliographyURLs(tab: tab, projectRoot: projectRoot) {
            guard let source = try? String(contentsOf: url, encoding: .utf8),
                  let offset = LatexCitationLookup.bibliographyEntryOffset(
                      for: key,
                      in: source
                  ) else { continue }
            return (url, source, offset)
        }
        return nil
    }

    private func latexFirstBibliography(
        tab: DocumentTab,
        projectRoot: URL
    ) -> (url: URL, source: String, offset: Int)? {
        for url in latexBibliographyURLs(tab: tab, projectRoot: projectRoot) {
            if let source = try? String(contentsOf: url, encoding: .utf8) {
                return (url, source, 0)
            }
        }
        return nil
    }

    private func latexBibliographyURLs(tab: DocumentTab, projectRoot: URL) -> [URL] {
        let rootURL = storedLatexRoot(for: projectRoot) ?? tab.url
        let dependencies = Set(
            tab.previewDependencies
                + LocalLatexAdapter().sourceDependencies(
                    rootURL: rootURL,
                    projectRoot: projectRoot
                )
        )
        return dependencies
            .filter {
                $0.pathExtension.lowercased() == "bib"
                    && isInside($0, project: projectRoot)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func latexUTF8Offset(in source: String, line: Int, column: Int) -> Int {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return 0 }
        let lineIndex = min(max(line - 1, 0), max(lines.count - 1, 0))
        let prefix = lines.prefix(lineIndex).joined(separator: "\n")
        return prefix.utf8.count + (lineIndex > 0 ? 1 : 0)
            + min(max(column, 0), lines[lineIndex].utf8.count)
    }

    func updateLatexEditing(tabID: String, text: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .latex,
              let session = tabs[index].latexEditSession,
              let transition = documentEditCoordinator.updateLatex(
                  session: session,
                  source: text
              ) else { return }

        tabs[index].latexEditSession = transition.session
        tabs[index].errorMessage = nil
        scheduleLatexRender(tabID: tabID)
    }

    func endLatexEditing(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession else { return }
        if session.currentSource == session.baseSource {
            tabs[index].latexEditSession?.isEditing = false
            tabs[index].diffSession = nil
            renderLatex(tabID: tabID)
        } else {
            tabs[index].latexEditSession?.saveState = .saving
            Task { @MainActor [weak self] in
                _ = await self?.saveLatexEdit(tabID: tabID, finishEditing: true)
            }
        }
    }

    @discardableResult
    func undoLatexEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession,
              let transition = documentEditCoordinator.undoLatex(session: session) else { return false }
        tabs[index].latexEditSession = transition.session
        scheduleLatexRender(tabID: tabID)
        return true
    }

    @discardableResult
    func redoLatexEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession,
              let transition = documentEditCoordinator.redoLatex(session: session) else { return false }
        tabs[index].latexEditSession = transition.session
        scheduleLatexRender(tabID: tabID)
        return true
    }

    func keepLocalLatexEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession else { return }
        applyLatexSaveOutcome(
            documentEditCoordinator.commitLatex(
                url: tabs[index].editableSourceURL,
                source: session.currentSource
            ),
            tabID: tabID,
            finishEditing: true
        )
    }

    func useExternalLatexEdit(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession,
              let conflict = session.conflict else { return }
        let external = documentEditCoordinator.useExternal(
            session: session,
            externalSource: conflict.externalSource
        )
        tabs[index].latexEditSession = external.session
        tabs[index].diffSession = nil
        tabs[index].errorMessage = nil
        renderLatex(tabID: tabID)
    }

    @discardableResult
    private func saveLatexEdit(tabID: String, finishEditing: Bool = false) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession else { return false }

        guard session.currentSource != session.baseSource else {
            if finishEditing {
                tabs[index].latexEditSession?.isEditing = false
                tabs[index].diffSession = nil
                renderLatex(tabID: tabID)
            }
            return true
        }

        let localSource = session.currentSource
        tabs[index].latexEditSession?.saveState = .saving
        let outcome = await documentEditCoordinator.saveLatex(
            url: tabs[index].editableSourceURL,
            baseSource: session.baseSource,
            localSource: localSource
        )
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[currentIndex].latexEditSession?.currentSource == localSource else {
            return false
        }
        return applyLatexSaveOutcome(outcome, tabID: tabID, finishEditing: finishEditing)
    }

    @discardableResult
    private func applyLatexSaveOutcome(
        _ outcome: DocumentEditSaveOutcome,
        tabID: String,
        finishEditing: Bool
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        switch outcome {
        case let .saved(source):
            tabs[index].latexEditSession?.baseSource = source
            tabs[index].latexEditSession?.currentSource = source
            tabs[index].latexEditSession?.saveState = .saved
            tabs[index].latexEditSession?.conflict = nil
            tabs[index].errorMessage = nil
            if tabs[index].diffSession?.mode == .savedOnDisk {
                tabs[index].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: source
                )
            }
            if finishEditing {
                tabs[index].latexEditSession?.isEditing = false
                tabs[index].diffSession = nil
            }
            renderLatex(tabID: tabID)
            return true
        case let .conflict(conflict):
            tabs[index].latexEditSession?.saveState = .conflict
            tabs[index].latexEditSession?.isEditing = true
            tabs[index].latexEditSession?.conflict = conflict
            return false
        case let .failed(message):
            tabs[index].latexEditSession?.saveState = .failed
            tabs[index].latexEditSession?.isEditing = true
            tabs[index].errorMessage = message
            return false
        }
    }

    func toggleLatexSplitView(tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .latex else { return }
        guard tabs[index].latexEditSession?.isEditing == true else {
            let returnMode = tabs[index].presentationMode
            beginLatexEditing(tabID: tabID)
            tabs[index].latexEditSession?.mode = .split
            tabs[index].latexEditSession?.splitReturnMode = returnMode
            renderLatex(tabID: tabID)
            return
        }

        if tabs[index].presentationMode == .split {
            let returnMode = tabs[index].latexEditSession?.splitReturnMode ?? .source
            let modeAfterClosing = returnMode == .preview && hasUnsavedChanges(in: tabs[index])
                ? .source
                : returnMode
            tabs[index].selectPresentationMode(modeAfterClosing)
            tabs[index].latexEditSession?.splitReturnMode = nil
            renderLatex(tabID: tabID)
            return
        }

        let returnMode = tabs[index].latexEditSession?.splitReturnMode ?? .source
        tabs[index].latexEditSession?.splitReturnMode = returnMode
        tabs[index].selectPresentationMode(.split)
        renderLatex(tabID: tabID)
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

    func updateJSONEditing(
        tabID: String,
        text: String,
        validate: Bool = true
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .json,
              let session = tabs[index].jsonEditSession,
              let transition = documentEditCoordinator.updateJSON(
                  session: session,
                  source: text,
                  validate: validate
              ) else { return }

        applyJSONTransition(transition, at: index)
    }

    func endJSONEditing(tabID: String, source: String? = nil) {
        if let source,
           tabs.first(where: { $0.id == tabID })?.jsonEditSession?.currentSource != source {
            updateJSONEditing(tabID: tabID, text: source, validate: false)
        }

        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .json,
              let session = tabs[index].jsonEditSession else { return }

        if let validationError = documentEditCoordinator.jsonValidationError(
            for: session.currentSource
        ) {
            tabs[index].jsonEditSession?.saveState = .failed
            tabs[index].errorMessage = validationError
            pendingInvalidJSONTabID = tabID
            showingInvalidJSONConfirmation = true
            return
        }

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
        guard tabs[index].markdownEditSession?.isEditing == true else {
            let returnMode = tabs[index].presentationMode
            beginMarkdownEditing(tabID: tabID, mode: .split)
            tabs[index].markdownEditSession?.splitReturnMode = returnMode
            return
        }

        if tabs[index].presentationMode == .split {
            let returnMode = tabs[index].markdownEditSession?.splitReturnMode ?? .source
            let modeAfterClosing = returnMode == .preview && hasUnsavedChanges(in: tabs[index])
                ? .source
                : returnMode
            tabs[index].selectPresentationMode(modeAfterClosing)
            tabs[index].markdownEditSession?.splitReturnMode = nil
            if modeAfterClosing == .preview {
                renderMarkdown(tabID: tabID)
            }
            return
        }

        let returnMode = tabs[index].markdownEditSession?.splitReturnMode ?? .source
        tabs[index].markdownEditSession?.splitReturnMode = returnMode
        tabs[index].selectPresentationMode(.split)
        if let session = tabs[index].markdownEditSession {
            renderMarkdown(tabID: tabID, sourceOverride: session.currentSource)
        }
    }

    @discardableResult
    func undoMarkdownEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let transition = documentEditCoordinator.undoMarkdown(session: session) else { return false }

        markdownUndoGroupTimes[tabID] = nil
        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            scheduleMarkdownRender(tabID: tabID)
        }
        return true
    }

    @discardableResult
    func redoMarkdownEdit() -> Bool {
        guard let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].markdownEditSession,
              let transition = documentEditCoordinator.redoMarkdown(session: session) else { return false }

        markdownUndoGroupTimes[tabID] = nil
        applyMarkdownTransition(transition, at: index)
        if transition.session.mode == .split {
            scheduleMarkdownRender(tabID: tabID)
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

        if tabs[index].isUntitled {
            return await saveUntitledMarkdown(
                tabID: tabID,
                session: session,
                finishEditing: finishEditing
            )
        }

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

    private func saveUntitledMarkdown(
        tabID: String,
        session: MarkdownEditSession,
        finishEditing: Bool
    ) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].isUntitled else { return false }
        tabs[index].markdownEditSession?.saveState = .saving

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Untitled.md"
        panel.title = "Save Markdown File"
        panel.prompt = "Save"

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            tabs[index].markdownEditSession?.saveState = .unsaved
            return false
        }

        return commitUntitledMarkdown(
            tabID: tabID,
            session: session,
            selectedURL: selectedURL,
            finishEditing: finishEditing
        )
    }

    private func commitUntitledMarkdown(
        tabID: String,
        session: MarkdownEditSession,
        selectedURL: URL,
        finishEditing: Bool
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].isUntitled else { return false }
        tabs[index].markdownEditSession?.saveState = .saving

        let targetURL = markdownSaveURL(for: selectedURL)
        let outcome = documentEditCoordinator.commitMarkdown(
            url: targetURL,
            source: session.currentSource
        )
        guard case let .saved(source) = outcome else {
            guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
            if case let .failed(message) = outcome {
                tabs[index].markdownEditSession?.saveState = .failed
                tabs[index].errorMessage = message
            }
            return false
        }

        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        let normalizedURL = targetURL.resolvingSymlinksInPath().standardizedFileURL
        let oldID = tabs[index].id
        documentRenderCoordinator.cancel(tabIDs: [oldID])
        tabs[index].id = normalizedURL.path
        tabs[index].url = normalizedURL
        tabs[index].kind = .markdown
        tabs[index].contextURL = nil
        tabs[index].status = .updating
        tabs[index].isStale = false
        tabs[index].previewBaseURL = nil
        tabs[index].previewDependencies = []
        tabs[index].previewExternalDependencies = []
        tabs[index].markdownSource = source
        tabs[index].markdownBlocks = MarkdownBlockDocument(source: source).blocks
        tabs[index].markdownEditSession?.baseSource = source
        tabs[index].markdownEditSession?.currentSource = source
        tabs[index].markdownEditSession?.saveState = .saved
        tabs[index].markdownEditSession?.conflict = nil
        tabs[index].markdownEditSession?.isEditing = !finishEditing
        if finishEditing {
            tabs[index].diffSession = nil
        }
        if activeTabID == oldID {
            activeTabID = normalizedURL.path
        }
        renderMarkdown(tabID: normalizedURL.path)
        if activeTabID == normalizedURL.path {
            restartWatchingActiveFilesIfNeeded()
        }
        syncPreviewZoomToActiveTab()
        persistState()
        return true
    }

    private func markdownSaveURL(for url: URL) -> URL {
        let extensionName = url.pathExtension.lowercased()
        guard extensionName == "md" || extensionName == "markdown" else {
            return url.appendingPathExtension("md")
        }
        return url
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

    func resizeOutline(to width: Double, forTabID tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let normalizedWidth = DocumentOutlineSizing.clamped(width)
        guard tabs[index].outlineWidth != normalizedWidth else { return }
        tabs[index].outlineWidth = normalizedWidth
    }

    func finishOutlineResize(forTabID tabID: String) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
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
            tabs[oldIndex].outlineWidth = documentState.outlineWidth
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
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
    }

    func setDefaultLatexZoom(_ value: Double) {
        let normalizedValue = normalizedZoom(value)
        guard defaultLatexZoom != normalizedValue else { return }
        defaultLatexZoom = normalizedValue
        applyDefaultZoom(normalizedValue, to: .latex)
        persistState()
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
    }

    func setLatexShellEscapeMode(_ mode: LatexShellEscapeMode) {
        guard latexShellEscapeMode != mode else { return }
        latexShellEscapeMode = mode
        persistState()
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
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
        case .json, .docx, .image, .other:
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
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        persistState()
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
    }

    func setSidebarWidth(_ width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
        persistState()
        WorkspaceWindowManager.shared.synchronizeGlobalPreferences(from: self)
    }

    func applySharedPreferences(from source: AppModel) {
        theme = source.theme
        sidebarVisible = source.sidebarVisible
        sidebarWidth = source.sidebarWidth
        defaultMarkdownZoom = source.defaultMarkdownZoom
        defaultLatexZoom = source.defaultLatexZoom
        latexShellEscapeMode = source.latexShellEscapeMode
        applyDefaultZoom(defaultMarkdownZoom, to: .markdown)
        applyDefaultZoom(defaultLatexZoom, to: .latex)
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
        let configuration = persistsSharedConfiguration
            ? WorkspaceSessionConfiguration(
                theme: theme.rawValue,
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                latexShellEscapeMode: latexShellEscapeMode.rawValue,
                defaultMarkdownZoom: defaultMarkdownZoom,
                defaultLatexZoom: defaultLatexZoom
            )
            : workspaceSession.configuration

        workspaceSession.persist(
            rootURL: rootURL,
            tabs: tabs,
            activeTabID: activeTabID,
            expandedPaths: expandedPaths,
            treeScrollOffset: treeScrollOffset,
            compatibleOnly: compatibleOnly,
            configuration: configuration
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
                outlineWidth: documentState.outlineWidth,
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
              tab.kind == .markdown || tab.kind == .latex || tab.kind == .json || tab.kind == .csv || tab.kind == .pdf || tab.kind == .docx || tab.kind == .image else {
            stopWatchingActiveFiles()
            return
        }

        startWatchingActiveFiles(
            [tab.url, tab.editableSourceURL]
                + tab.previewDependencies + tab.previewExternalDependencies
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
        case .image:
            hasPreview = tab.previewImageData != nil
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
            } else if tab.kind == .image {
                renderImage(tabID: activeTabID)
            }
        }
    }

    private func startWatchingActiveFiles(_ urls: [URL]) {
        guard let activeTabID else { return }
        activeDocumentWatcher.start(
            tabID: activeTabID,
            urls: urls.filter(\.isFileURL)
        )
    }

    private func stopWatchingActiveFiles() {
        activeDocumentWatcher.stop()
    }

    private func restartWatchingActiveFiles(_ urls: [URL]) {
        startWatchingActiveFiles(urls)
    }

    private func handleActiveDocumentChange(_ change: ActiveDocumentChange) {
        guard activeTabID == change.tabID,
              tabs.contains(where: { $0.id == change.tabID }) else { return }

        Task { @MainActor [weak self] in
            guard let self,
                  self.activeTabID == change.tabID,
                  let currentTab = self.tabs.first(where: { $0.id == change.tabID }) else { return }

            switch currentTab.kind {
            case .latex:
                if currentTab.editableSourceURL.standardizedFileURL == change.url.standardizedFileURL,
                   currentTab.latexEditSession?.isEditing == true {
                    await self.handleExternalLatexChange(tabID: change.tabID)
                } else {
                    self.renderLatex(tabID: change.tabID)
                }
            case .json:
                if currentTab.editableSourceURL.standardizedFileURL == change.url.standardizedFileURL,
                   currentTab.jsonEditSession?.isEditing == true {
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
            case .image:
                self.renderImage(tabID: change.tabID)
            case .markdown:
                if currentTab.editableSourceURL.standardizedFileURL == change.url.standardizedFileURL,
                   currentTab.markdownEditSession?.isEditing == true {
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
              session.isEditing else {
            renderMarkdown(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].url)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].markdownEditSession?.currentSource == session.currentSource else { return }

            guard externalSource != session.baseSource else { return }

            if session.currentSource == session.baseSource {
                tabs[currentIndex].markdownSource = externalSource
                tabs[currentIndex].markdownBlocks = MarkdownBlockDocument(source: externalSource).blocks
                var refreshedSession = session
                refreshedSession.baseSource = externalSource
                refreshedSession.currentSource = externalSource
                refreshedSession.saveState = .saved
                refreshedSession.conflict = nil
                tabs[currentIndex].markdownEditSession = refreshedSession
                if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                    tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                        label: "Saved on Disk",
                        source: externalSource
                    )
                }
                renderMarkdown(tabID: tabID)
                return
            }

            if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: externalSource
                )
            }

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
              session.isEditing else {
            renderJSON(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].url)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].jsonEditSession?.currentSource == session.currentSource else { return }

            guard externalSource != session.baseSource else { return }

            if session.currentSource == session.baseSource {
                tabs[currentIndex].jsonSource = externalSource
                var refreshedSession = session
                refreshedSession.baseSource = externalSource
                refreshedSession.currentSource = externalSource
                refreshedSession.saveState = .saved
                refreshedSession.conflict = nil
                tabs[currentIndex].jsonEditSession = refreshedSession
                if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                    tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                        label: "Saved on Disk",
                        source: externalSource
                    )
                }
                renderJSON(tabID: tabID)
                return
            }

            if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: externalSource
                )
            }

            tabs[currentIndex].jsonEditSession?.saveState = .conflict
            tabs[currentIndex].jsonEditSession?.isEditing = true
            tabs[currentIndex].jsonEditSession?.conflict = MarkdownConflict(
                localSource: session.currentSource,
                externalSource: externalSource,
                blockIDs: []
            )
        } catch {
            tabs[index].jsonEditSession?.saveState = .failed
            tabs[index].jsonEditSession?.isEditing = true
            tabs[index].errorMessage = error.localizedDescription
        }
    }

    private func handleExternalLatexChange(tabID: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let session = tabs[index].latexEditSession,
              session.isEditing else {
            renderLatex(tabID: tabID)
            return
        }

        do {
            let externalSource = try await documentEditCoordinator.readSource(at: tabs[index].editableSourceURL)
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabID }),
                  tabs[currentIndex].latexEditSession?.currentSource == session.currentSource else { return }

            guard externalSource != session.baseSource else { return }

            if session.currentSource == session.baseSource {
                var refreshedSession = session
                refreshedSession.baseSource = externalSource
                refreshedSession.currentSource = externalSource
                refreshedSession.saveState = .saved
                refreshedSession.conflict = nil
                tabs[currentIndex].latexEditSession = refreshedSession
                if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                    tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                        label: "Saved on Disk",
                        source: externalSource
                    )
                }
                renderLatex(tabID: tabID)
                return
            }

            if tabs[currentIndex].diffSession?.mode == .savedOnDisk {
                tabs[currentIndex].diffSession?.baseline = DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: externalSource
                )
            }
            tabs[currentIndex].latexEditSession?.saveState = .conflict
            tabs[currentIndex].latexEditSession?.isEditing = true
            tabs[currentIndex].latexEditSession?.conflict = MarkdownConflict(
                localSource: session.currentSource,
                externalSource: externalSource,
                blockIDs: []
            )
        } catch {
            tabs[index].latexEditSession?.saveState = .failed
            tabs[index].latexEditSession?.isEditing = true
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
        guard let source = try? await documentEditCoordinator.readSource(at: tabs[index].editableSourceURL),
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
        let sourceOverride: String?
        if let session = tab.latexEditSession,
           session.isEditing,
           session.currentSource != session.baseSource {
            sourceOverride = session.currentSource
        } else {
            sourceOverride = nil
        }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .latex,
            projectRoot: projectRoot,
            markdownSourceOverride: nil,
            latexSourceURL: sourceOverride == nil ? nil : tab.editableSourceURL,
            latexSourceOverride: sourceOverride,
            latexRootURL: explicitRootURL ?? storedLatexRoot(for: projectRoot),
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: approvedLatexExternalPaths,
            force: force
        ))
    }

    private func scheduleLatexRender(tabID: String) {
        latexRenderDebounceTasks[tabID]?.cancel()
        latexRenderDebounceTasks[tabID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.renderLatex(tabID: tabID)
            self.latexRenderDebounceTasks[tabID] = nil
        }
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
        let effectiveSourceOverride = sourceOverride
            ?? (tab.isUntitled ? tab.markdownEditSession?.currentSource ?? tab.markdownSource ?? "" : nil)
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .markdown,
            projectRoot: rootURL,
            markdownSourceOverride: effectiveSourceOverride,
            latexRootURL: nil,
            latexShellEscapeMode: latexShellEscapeMode,
            approvedLatexExternalPaths: [:],
            force: false
        ))
    }

    private func scheduleMarkdownRender(tabID: String) {
        markdownRenderDebounceTasks[tabID]?.cancel()
        markdownRenderDebounceTasks[tabID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self,
                  let tab = self.tabs.first(where: { $0.id == tabID }),
                  let session = tab.markdownEditSession,
                  session.isEditing,
                  session.mode == .split else { return }
            self.renderMarkdown(tabID: tabID, sourceOverride: session.currentSource)
            self.markdownRenderDebounceTasks[tabID] = nil
        }
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

    private func renderImage(tabID: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }), tab.kind == .image else { return }
        documentRenderCoordinator.render(DocumentRenderRequest(
            tabID: tabID,
            url: tab.url,
            kind: .image,
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
                tabs[index].latexSyncTeXData = output.syncTeXData
                tabs[index].latexGeneratedBibliographySource = output.generatedBibliographySource
                tabs[index].previewHTML = nil
                tabs[index].previewJSON = nil
                tabs[index].previewBaseURL = nil
                tabs[index].previewImageData = nil
            case .image:
                tabs[index].previewImageData = output.imageData
                tabs[index].previewHTML = nil
                tabs[index].previewJSON = nil
                tabs[index].previewCSV = nil
                tabs[index].previewPDFData = nil
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
                    [tabs[index].url, tabs[index].editableSourceURL]
                        + output.dependencies + output.externalDependencies
                )
            }

        case let .failed(tabID, failure):
            guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
            tabs[index].status = failure.status
            tabs[index].isStale = tabs[index].previewHTML != nil
                || tabs[index].previewJSON != nil
                || tabs[index].previewCSV != nil
                || tabs[index].previewPDFData != nil
                || tabs[index].previewImageData != nil
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
