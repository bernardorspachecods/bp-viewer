import AppKit
import BPViewerCore
import SwiftUI

/// Owns the native macOS windows that represent open workspaces.
///
/// Each window keeps its own AppModel alive, so selecting a native window tab
/// does not tear down the tree, document tabs, or preview state.
@MainActor
final class WorkspaceWindowManager: NSObject, ObservableObject {
    static let shared = WorkspaceWindowManager()

    static let tabbingIdentifier = "com.bernardopacheco.bp-viewer.workspace"
    private static let captureWindowIdentifier = NSUserInterfaceItemIdentifier(
        "com.bernardopacheco.bp-viewer.codex-capture"
    )

    let session: WorkspaceSessionCoordinator
    @Published private(set) var activeModel: AppModel?

    private var models: [ObjectIdentifier: AppModel] = [:]
    private var windows: [ObjectIdentifier: NSWindow] = [:]
    private var lastKnownModel: AppModel?
    private var lastKnownWindow: NSWindow?
    private var didRestoreWorkspaces = false
    private var keyWindowObserver: NSObjectProtocol?
    private var isTerminating = false
    private var terminationObserver: NSObjectProtocol?

    private override init() {
        session = WorkspaceSessionCoordinator()
        super.init()

        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.activate(window: window)
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForTermination()
            }
        }
    }

    func register(model: AppModel?, window: NSWindow) {
        guard let model else { return }

        let id = ObjectIdentifier(window)
        models[id] = model
        windows[id] = window
        lastKnownModel = model
        lastKnownWindow = window

        if window.identifier == Self.captureWindowIdentifier {
            window.tabbingMode = .disallowed
        } else {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = Self.tabbingIdentifier
        }
        updateWindowTitle(window, for: model)
        model.attach(to: window)

        if window.isKeyWindow || window.isMainWindow {
            activeModel = model
        }

        if let rootURL = model.rootURL,
           !session.openWorkspacePaths.contains(session.workspaceKey(for: rootURL)) {
            let existing = session.openWorkspacePaths.map(URL.init(fileURLWithPath:))
            session.setOpenWorkspaces(existing + [rootURL], activeRoot: rootURL)
        }

        guard !didRestoreWorkspaces, model.rootURL != nil else { return }
        didRestoreWorkspaces = true
        DispatchQueue.main.async { [weak self, weak model] in
            guard let self, let model else { return }
            self.restoreWorkspaces(anchoredAt: model)
        }
    }

    func unregister(window: NSWindow) {
        let id = ObjectIdentifier(window)
        let removedModel = models.removeValue(forKey: id)
        windows.removeValue(forKey: id)

        if activeModel === removedModel {
            activeModel = keyWindowModel() ?? models.values.first
        }
        guard !isTerminating else { return }
        persistWorkspaceLayout()
    }

    func prepareForTermination() {
        guard !isTerminating else { return }
        isTerminating = true
        persistWorkspaceLayout()
    }

    func activate(window: NSWindow) {
        guard let model = models[ObjectIdentifier(window)] else { return }
        activeModel = model
        persistWorkspaceLayout()
    }

    func chooseAndOpenWorkspace(from sourceModel: AppModel? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(url, from: sourceModel ?? activeModel)
    }

    func openWorkspace(
        _ url: URL,
        opening documents: [URL] = [],
        from sourceModel: AppModel? = nil
    ) {
        let rootURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard isDirectory(rootURL) else { return }

        if let sourceModel,
           let sourceWindow = sourceModel.nativeWindow {
            register(model: sourceModel, window: sourceWindow)
        }

        if let emptyModel = sourceModel ?? activeModel,
           emptyModel.rootURL == nil {
            let emptyWindow = emptyModel.nativeWindow ?? window(for: emptyModel)
            emptyModel.openRoot(rootURL)
            if let emptyWindow {
                register(model: emptyModel, window: emptyWindow)
                updateWindowTitle(emptyWindow, for: emptyModel)
            }
            documents.forEach { emptyModel.openDocument(url: $0) }
            persistWorkspaceLayout()
            return
        }

        if let existing = window(for: rootURL),
           let model = models[ObjectIdentifier(existing)] {
            existing.tabGroup?.selectedWindow = existing
            existing.makeKeyAndOrderFront(nil)
            documents.forEach { model.openDocument(url: $0) }
            persistWorkspaceLayout()
            return
        }

        let model = AppModel(
            workspaceSession: session,
            initialRootURL: rootURL,
            restoresLastWorkspace: false
        )
        let window = makeWindow(for: model)
        register(model: model, window: window)

        if let anchor = anchorWindow(excluding: window, preferredModel: sourceModel) {
            anchor.addTabbedWindow(window, ordered: .above)
            anchor.tabGroup?.selectedWindow = window
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        documents.forEach { model.openDocument(url: $0) }
        persistWorkspaceLayout()
    }

    func closeActiveTabInKeyWindow() {
        guard let keyWindow = NSApp.keyWindow else { return }
        if let snapshotWindow = keyWindow as? SnapshotPanel {
            snapshotWindow.performClose(nil)
            return
        }
        models[ObjectIdentifier(keyWindow)]?.closeActiveTab()
    }

    func modelForActiveWindow(fallback: AppModel? = nil) -> AppModel? {
        keyWindowModel() ?? activeModel ?? fallback
    }

    /// Uses the last focused Viewer window, unless it is minimized. In that
    /// case, a standalone capture window keeps the minimized workspace intact.
    func presentForCapturedReply() -> AppModel? {
        // The shortcut arrives while Terminal is frontmost. `activeModel` is
        // the Viewer window that was focused before the app switch; AppKit's
        // keyWindow may still point at another transient or stale window.
        let model = activeModel ?? lastKnownModel
        guard let model else { return nil }

        let existingWindow = window(for: model)
            ?? (lastKnownModel === model ? lastKnownWindow : nil)

        if let existingWindow, existingWindow.isMiniaturized {
            let captureModel = AppModel(
                workspaceSession: session,
                restoresLastWorkspace: false,
                persistsSharedConfiguration: false
            )
            captureModel.sidebarVisible = false
            let captureWindow = makeWindow(for: captureModel, isCaptureWindow: true)
            register(model: captureModel, window: captureWindow)
            bringForward(captureWindow, model: captureModel)
            return captureModel
        }

        if let existingWindow {
            if windows[ObjectIdentifier(existingWindow)] == nil {
                register(model: model, window: existingWindow)
            }
            bringForward(existingWindow, model: model)
            return model
        }

        let restoredWindow = makeWindow(for: model)
        register(model: model, window: restoredWindow)
        bringForward(restoredWindow, model: model)
        return model
    }

    func synchronizeGlobalPreferences(from source: AppModel) {
        for model in models.values where model !== source {
            model.applySharedPreferences(from: source)
        }
    }

    private func restoreWorkspaces(anchoredAt initialModel: AppModel) {
        let initialRootPath = initialModel.rootURL.map(session.workspaceKey(for:))
        let storedPaths = session.openWorkspacePaths
        let validPaths = storedPaths.filter { path in
            let url = URL(fileURLWithPath: path)
            return isDirectory(url)
        }

        for path in validPaths where path != initialRootPath {
            openWorkspace(URL(fileURLWithPath: path))
        }

        if let activePath = session.activeWorkspacePath,
           let activeWindow = window(for: URL(fileURLWithPath: activePath)) {
            activeWindow.tabGroup?.selectedWindow = activeWindow
            activeWindow.makeKeyAndOrderFront(nil)
        } else {
            initialModelWindow()?.makeKeyAndOrderFront(nil)
        }

        persistWorkspaceLayout()
    }

    private func makeWindow(for model: AppModel, isCaptureWindow: Bool = false) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        if isCaptureWindow {
            window.identifier = Self.captureWindowIdentifier
            window.tabbingMode = .disallowed
        }
        window.contentView = NSHostingView(
            rootView: RootView().environmentObject(model)
        )
        window.center()
        return window
    }

    private func bringForward(_ window: NSWindow, model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        activeModel = model
    }

    private func window(for rootURL: URL) -> NSWindow? {
        let path = session.workspaceKey(for: rootURL)
        return windows.values.first { window in
            guard let model = models[ObjectIdentifier(window)], let modelRoot = model.rootURL else {
                return false
            }
            return session.workspaceKey(for: modelRoot) == path
        }
    }

    private func window(for model: AppModel) -> NSWindow? {
        guard let windowID = models.first(where: { $0.value === model })?.key else {
            return nil
        }
        return windows[windowID]
    }

    private func anchorWindow(
        excluding excludedWindow: NSWindow? = nil,
        preferredModel: AppModel? = nil
    ) -> NSWindow? {
        if let preferredModel,
           let window = window(for: preferredModel),
           window !== excludedWindow {
            return window
        }
        if let activeModel,
           let window = windows.first(where: { $0.value === activeModel })?.value {
            if window !== excludedWindow {
                return window
            }
        }
        if let keyWindow = keyWindowModel(),
           let window = windows.first(where: { $0.value === keyWindow })?.value,
           window !== excludedWindow {
            return window
        }
        return windows.values.first { $0 !== excludedWindow }
    }

    private func initialModelWindow() -> NSWindow? {
        windows.values.first { window in
            guard let model = models[ObjectIdentifier(window)] else { return false }
            return model.rootURL?.path == session.activeWorkspacePath
        } ?? windows.values.first
    }

    private func keyWindowModel() -> AppModel? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return models[ObjectIdentifier(keyWindow)]
    }

    private func updateWindowTitle(_ window: NSWindow, for model: AppModel) {
        let title = model.rootURL?.lastPathComponent ?? "Viewer"
        window.title = title
        window.tab.title = title
    }

    private func persistWorkspaceLayout() {
        let orderedWindows: [NSWindow]
        if let group = anchorWindow()?.tabGroup {
            orderedWindows = group.windows
        } else {
            orderedWindows = Array(windows.values)
        }

        let roots = orderedWindows.compactMap { window in
            models[ObjectIdentifier(window)]?.rootURL
        }
        guard !roots.isEmpty else {
            session.setOpenWorkspaces([], activeRoot: nil)
            return
        }

        session.setOpenWorkspaces(
            roots,
            activeRoot: activeModel?.rootURL ?? keyWindowModel()?.rootURL
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
