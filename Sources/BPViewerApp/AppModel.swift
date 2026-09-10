import AppKit
import Combine
import Darwin
import Foundation

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
    @Published var sidebarVisible = true
    @Published var sidebarWidth: Double = 280
    @Published private(set) var isScanningTree = false
    @Published var pendingRootURL: URL?
    @Published var showingRootChangeConfirmation = false

    private let scanner = FileSystemScanner()
    private let defaults = UserDefaults.standard
    private let markdownAdapter: any MarkdownAdapter = SwiftMarkdownAdapter()
    private var completeNodes: [FileNode] = []
    private var treeScanGeneration = 0
    private var previewGenerations: [String: Int] = [:]
    private var activeFileWatcher: DispatchSourceFileSystemObject?
    private var watchedFileURL: URL?
    private var fileRefreshGeneration = 0

    private enum Keys {
        static let theme = "bp-viewer.theme"
        static let lastRoot = "bp-viewer.lastRoot"
        static let lastTabs = "bp-viewer.lastTabs"
        static let activeTab = "bp-viewer.activeTab"
        static let sidebarVisible = "bp-viewer.sidebarVisible"
        static let sidebarWidth = "bp-viewer.sidebarWidth"
        static let compatibleOnly = "bp-viewer.compatibleOnly"
    }

    init() {
        let savedTheme = defaults.string(forKey: Keys.theme)
        theme = AppThemePreference(rawValue: savedTheme ?? "") ?? .dark
        sidebarVisible = defaults.object(forKey: Keys.sidebarVisible) as? Bool ?? true
        sidebarWidth = defaults.object(forKey: Keys.sidebarWidth) as? Double ?? 280
        compatibleOnly = defaults.object(forKey: Keys.compatibleOnly) as? Bool ?? true

        if let path = defaults.string(forKey: Keys.lastRoot) {
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

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Abrir pasta"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestRoot(url)
    }

    func requestRoot(_ url: URL) {
        guard rootURL != nil, !tabs.isEmpty else {
            openRoot(url)
            return
        }

        pendingRootURL = url
        showingRootChangeConfirmation = true
    }

    func confirmRootChange() {
        guard let pendingRootURL else { return }
        openRoot(pendingRootURL)
        self.pendingRootURL = nil
        showingRootChangeConfirmation = false
    }

    func cancelRootChange() {
        pendingRootURL = nil
        showingRootChangeConfirmation = false
    }

    func openRoot(_ url: URL) {
        stopWatchingActiveFile()
        rootURL = url.standardizedFileURL
        tabs = []
        activeTabID = nil
        expandedPaths = []
        defaults.set(rootURL?.path, forKey: Keys.lastRoot)
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
        isScanningTree = true

        Task { [weak self] in
            let scannedNodes = await Task.detached(priority: .userInitiated) {
                scanner.scan(root: rootURL)
            }.value

            guard let self,
                  self.treeScanGeneration == generation,
                  self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }

            self.completeNodes = scannedNodes
            self.nodes = scanner.filter(
                scannedNodes,
                compatibleOnly: self.compatibleOnly,
                query: self.treeQuery
            )
            self.isScanningTree = false
        }
    }

    func updateTreeQuery(_ query: String) {
        treeQuery = query
        applyTreeFilter()
    }

    func updateCompatibleOnly(_ value: Bool) {
        compatibleOnly = value
        defaults.set(value, forKey: Keys.compatibleOnly)
        applyTreeFilter()
    }

    func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        persistState()
    }

    func open(_ node: FileNode) {
        guard !node.isDirectory else {
            toggleExpanded(node.id)
            return
        }

        let id = node.url.standardizedFileURL.path
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            selectTab(id: tabs[index].id)
            return
        }

        let tab = DocumentTab(
            id: id,
            url: node.url,
            kind: node.kind,
            status: node.kind == .markdown ? .updating : .unavailable
        )
        tabs.append(tab)
        selectTab(id: tab.id)
    }

    func closeTab(_ tab: DocumentTab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)
        if activeTabID == tab.id {
            activeTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
            renderActiveTabIfNeeded()
        }
        persistState()
    }

    func closeOtherTabs(keeping tab: DocumentTab) {
        tabs = [tab]
        activeTabID = tab.id
        renderActiveTabIfNeeded()
        persistState()
    }

    func closeTabsToRight(of tab: DocumentTab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs = Array(tabs.prefix(through: index))
        if let activeTabID, !tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = tabs.last?.id
            renderActiveTabIfNeeded()
        }
        persistState()
    }

    func refreshActiveTab() {
        reloadTree()
        guard let activeTabID else { return }
        if tabs.first(where: { $0.id == activeTabID })?.kind == .markdown {
            renderMarkdown(tabID: activeTabID)
        } else if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].status = .unavailable
            tabs[index].errorMessage = nil
        }
        persistState()
    }

    private func applyTreeFilter() {
        nodes = scanner.filter(
            completeNodes,
            compatibleOnly: compatibleOnly,
            query: treeQuery
        )
    }

    func cycleTheme() {
        switch theme {
        case .light: theme = .dark
        case .dark: theme = .light
        }
        defaults.set(theme.rawValue, forKey: Keys.theme)
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        defaults.set(visible, forKey: Keys.sidebarVisible)
    }

    func setSidebarWidth(_ width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
        defaults.set(sidebarWidth, forKey: Keys.sidebarWidth)
    }

    func resizeSidebar(to width: Double) {
        sidebarWidth = min(max(width, BPTokens.Size.sidebarMin), BPTokens.Size.sidebarMax)
    }

    func selectTab(number: Int) {
        guard tabs.indices.contains(number) else { return }
        selectTab(id: tabs[number].id)
    }

    func selectTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        renderActiveTabIfNeeded()
        persistState()
    }

    func persistState() {
        defaults.set(tabs.map(\.url.path), forKey: Keys.lastTabs)
        defaults.set(activeTabID, forKey: Keys.activeTab)
        defaults.set(Array(expandedPaths), forKey: "bp-viewer.expandedPaths")
    }

    private func restoreTabs() {
        let savedPaths = defaults.stringArray(forKey: Keys.lastTabs) ?? []
        let available = savedPaths.compactMap { path -> DocumentTab? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let kind = DocumentKind(url: url)
            return DocumentTab(id: path, url: url, kind: kind, status: kind == .markdown ? .idle : .unavailable)
        }
        tabs = available
        activeTabID = defaults.string(forKey: Keys.activeTab).flatMap { saved in
            available.contains(where: { $0.id == saved }) ? saved : available.first?.id
        }
        expandedPaths = Set(defaults.stringArray(forKey: "bp-viewer.expandedPaths") ?? [])
        renderActiveTabIfNeeded()
    }

    private func renderActiveTabIfNeeded() {
        guard let activeTabID,
              let tab = tabs.first(where: { $0.id == activeTabID }),
              tab.kind == .markdown else {
            stopWatchingActiveFile()
            return
        }

        startWatchingActiveFile(tab.url)
        if tab.previewHTML == nil || tab.status != .ready {
            renderMarkdown(tabID: activeTabID)
        }
    }

    private func startWatchingActiveFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard watchedFileURL != standardizedURL else { return }

        stopWatchingActiveFile()
        let descriptor = Darwin.open(standardizedURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleActiveFileRefresh(for: standardizedURL)
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        watchedFileURL = standardizedURL
        activeFileWatcher = source
        source.resume()
    }

    private func stopWatchingActiveFile() {
        activeFileWatcher?.cancel()
        activeFileWatcher = nil
        watchedFileURL = nil
        fileRefreshGeneration += 1
    }

    private func scheduleActiveFileRefresh(for url: URL) {
        guard watchedFileURL == url,
              let activeTabID,
              tabs.contains(where: { $0.id == activeTabID && $0.url.standardizedFileURL == url }) else { return }

        fileRefreshGeneration += 1
        let generation = fileRefreshGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.fileRefreshGeneration == generation else { return }
            self.renderMarkdown(tabID: activeTabID)
            self.stopWatchingActiveFile()
            self.startWatchingActiveFile(url)
        }
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
                self.tabs[index].previewBaseURL = result.baseURL
                self.tabs[index].status = .ready
                self.tabs[index].isStale = false
                self.tabs[index].errorMessage = nil
            } catch {
                guard let self,
                      self.previewGenerations[tabID] == generation,
                      let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }

                self.tabs[index].status = .failed
                self.tabs[index].isStale = self.tabs[index].previewHTML != nil
                self.tabs[index].errorMessage = error.localizedDescription
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
