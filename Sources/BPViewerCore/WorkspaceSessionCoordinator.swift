import Foundation

public struct WorkspaceSessionConfiguration: Sendable {
    public let theme: String
    public let sidebarVisible: Bool
    public let sidebarWidth: Double
    public let latexShellEscapeMode: String
    public let defaultMarkdownZoom: Double
    public let defaultLatexZoom: Double

    public init(
        theme: String,
        sidebarVisible: Bool,
        sidebarWidth: Double,
        latexShellEscapeMode: String,
        defaultMarkdownZoom: Double,
        defaultLatexZoom: Double
    ) {
        self.theme = theme
        self.sidebarVisible = sidebarVisible
        self.sidebarWidth = sidebarWidth
        self.latexShellEscapeMode = latexShellEscapeMode
        self.defaultMarkdownZoom = defaultMarkdownZoom
        self.defaultLatexZoom = defaultLatexZoom
    }
}

/// Owns persisted workspace/session state without knowing the SwiftUI model.
@MainActor
public final class WorkspaceSessionCoordinator {
    private var state: AppState
    private let store: AppStateStore

    public init(store: AppStateStore = AppStateStore()) {
        self.store = store
        self.state = store.load()
    }

    public var configuration: WorkspaceSessionConfiguration {
        WorkspaceSessionConfiguration(
            theme: state.global.theme,
            sidebarVisible: state.global.sidebarVisible,
            sidebarWidth: state.global.sidebarWidth,
            latexShellEscapeMode: state.global.latexShellEscapeMode,
            defaultMarkdownZoom: state.global.defaultMarkdownZoom,
            defaultLatexZoom: state.global.defaultLatexZoom
        )
    }

    public var lastWorkspacePath: String? {
        state.lastWorkspacePath
    }

    public func workspaceState(for rootURL: URL) -> WorkspaceState {
        state.workspaceStates[workspaceKey(for: rootURL)] ?? WorkspaceState()
    }

    public func hasWorkspaceState(for rootURL: URL) -> Bool {
        state.workspaceStates[workspaceKey(for: rootURL)] != nil
    }

    public func documentState(for url: URL) -> DocumentState {
        state.documentStates[documentKey(for: url)] ?? DocumentState()
    }

    public func snapshots(for rootURL: URL) -> [SnapshotRecord] {
        workspaceState(for: rootURL).snapshots
    }

    public func storedLatexRoot(for projectRoot: URL) -> URL? {
        let workspace = workspaceState(for: projectRoot)
        guard let path = workspace.latexRootSelections[projectRoot.standardizedFileURL.path] else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    public func approvedLatexExternalPaths(for projectRoot: URL) -> [String: Set<String>] {
        workspaceState(for: projectRoot).latexExternalGrants.mapValues(Set.init)
    }

    public func persist(
        rootURL: URL?,
        tabs: [DocumentTab],
        activeTabID: String?,
        expandedPaths: Set<String>,
        treeScrollOffset: Double,
        compatibleOnly: Bool,
        configuration: WorkspaceSessionConfiguration
    ) {
        state.global.theme = configuration.theme
        state.global.sidebarVisible = configuration.sidebarVisible
        state.global.sidebarWidth = configuration.sidebarWidth
        state.global.latexShellEscapeMode = configuration.latexShellEscapeMode
        state.global.defaultMarkdownZoom = configuration.defaultMarkdownZoom
        state.global.defaultLatexZoom = configuration.defaultLatexZoom

        guard let rootURL else {
            save()
            return
        }

        let rootKey = workspaceKey(for: rootURL)
        var workspace = state.workspaceStates[rootKey] ?? WorkspaceState()
        workspace.tabPaths = tabs.map { $0.url.standardizedFileURL.path }
        workspace.activeTabPath = activeTabID
        workspace.expandedPaths = expandedPaths.sorted()
        workspace.treeScrollOffset = treeScrollOffset
        workspace.compatibleOnly = compatibleOnly
        workspace.tabContexts = tabs.reduce(into: [String: String]()) { result, tab in
            guard tab.kind == .latex, let contextURL = tab.contextURL else { return }
            LatexTabContextPersistence.store(contextURL: contextURL, forTabID: tab.id, in: &result)
        }
        state.workspaceStates[rootKey] = workspace

        for tab in tabs {
            state.documentStates[documentKey(for: tab.url)] = DocumentState(
                zoom: tab.isPreviewZoomCustomized ? tab.previewZoom : nil,
                outlineVisible: tab.isOutlineVisible,
                markdownReadingPosition: tab.markdownReadingPosition,
                pdfReadingPosition: tab.pdfReadingPosition
            )
        }

        state.lastWorkspacePath = rootKey
        save()
    }

    public func updateGlobal(_ update: (inout GlobalState) -> Void) {
        update(&state.global)
        save()
    }

    public func storeLatexRoot(_ rootURL: URL, for projectRoot: URL) {
        let key = workspaceKey(for: projectRoot)
        var workspace = state.workspaceStates[key] ?? WorkspaceState()
        workspace.latexRootSelections[projectRoot.standardizedFileURL.path] = rootURL.standardizedFileURL.path
        state.workspaceStates[key] = workspace
        save()
    }

    public func approveLatexExternalDependencies(
        _ dependencies: [LatexExternalDependency],
        rootURL: URL,
        projectRoot: URL
    ) {
        let key = workspaceKey(for: projectRoot)
        var workspace = state.workspaceStates[key] ?? WorkspaceState()
        let grantKey = latexExternalGrantKey(projectRoot: projectRoot, rootURL: rootURL)
        var grants = Set(workspace.latexExternalGrants[grantKey] ?? [])
        grants.formUnion(dependencies.map { $0.url.standardizedFileURL.path })
        workspace.latexExternalGrants[grantKey] = grants.sorted()
        state.workspaceStates[key] = workspace
        save()
    }

    public func addSnapshot(_ record: SnapshotRecord, for rootURL: URL) {
        let key = workspaceKey(for: rootURL)
        var workspace = state.workspaceStates[key] ?? WorkspaceState()
        workspace.snapshots.append(record)
        state.workspaceStates[key] = workspace
        save()
    }

    @discardableResult
    public func removeSnapshot(id: String) -> String? {
        for key in state.workspaceStates.keys {
            guard var workspace = state.workspaceStates[key],
                  let index = workspace.snapshots.firstIndex(where: { $0.id == id }) else { continue }
            let artifactPath = workspace.snapshots.remove(at: index).artifactPath
            state.workspaceStates[key] = workspace
            save()
            return artifactPath
        }
        save()
        return nil
    }

    public func save() {
        store.save(state)
    }

    public func workspaceKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public func documentKey(for url: URL) -> String {
        workspaceKey(for: url)
    }

    private func latexExternalGrantKey(projectRoot: URL, rootURL: URL) -> String {
        "\(projectRoot.standardizedFileURL.path)\n\(rootURL.standardizedFileURL.path)"
    }
}
