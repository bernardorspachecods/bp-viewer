import Foundation

struct AppState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var global = GlobalState()
    var documentStates: [String: DocumentState] = [:]
    var workspaceStates: [String: WorkspaceState] = [:]
    var lastWorkspacePath: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case global
        case documentStates
        case workspaceStates
        case lastWorkspacePath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        global = try container.decodeIfPresent(GlobalState.self, forKey: .global) ?? GlobalState()
        documentStates = try container.decodeIfPresent([String: DocumentState].self, forKey: .documentStates) ?? [:]
        workspaceStates = try container.decodeIfPresent([String: WorkspaceState].self, forKey: .workspaceStates) ?? [:]
        lastWorkspacePath = try container.decodeIfPresent(String.self, forKey: .lastWorkspacePath)
    }
}

struct GlobalState: Codable {
    var theme = "dark"
    var sidebarVisible = true
    var sidebarWidth = 280.0
    var latexShellEscapeMode = "disabled"
    var defaultMarkdownZoom = 1.0
    var defaultLatexZoom = 1.0

    private enum CodingKeys: String, CodingKey {
        case theme, sidebarVisible, sidebarWidth, latexShellEscapeMode
        case defaultMarkdownZoom, defaultLatexZoom
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        sidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 280
        latexShellEscapeMode = try container.decodeIfPresent(String.self, forKey: .latexShellEscapeMode) ?? "disabled"
        defaultMarkdownZoom = try container.decodeIfPresent(Double.self, forKey: .defaultMarkdownZoom) ?? 1.0
        defaultLatexZoom = try container.decodeIfPresent(Double.self, forKey: .defaultLatexZoom) ?? 1.0
    }
}

struct DocumentState: Codable {
    var zoom: Double?
    var outlineVisible = false
    var markdownReadingPosition: MarkdownReadingPosition?
    var pdfReadingPosition: PDFReadingPosition?

    private enum CodingKeys: String, CodingKey {
        case zoom, outlineVisible, markdownReadingPosition, pdfReadingPosition
    }

    init() {}

    init(
        zoom: Double?,
        outlineVisible: Bool,
        markdownReadingPosition: MarkdownReadingPosition?,
        pdfReadingPosition: PDFReadingPosition?
    ) {
        self.zoom = zoom
        self.outlineVisible = outlineVisible
        self.markdownReadingPosition = markdownReadingPosition
        self.pdfReadingPosition = pdfReadingPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.0
        outlineVisible = try container.decodeIfPresent(Bool.self, forKey: .outlineVisible) ?? false
        markdownReadingPosition = try container.decodeIfPresent(MarkdownReadingPosition.self, forKey: .markdownReadingPosition)
        pdfReadingPosition = try container.decodeIfPresent(PDFReadingPosition.self, forKey: .pdfReadingPosition)
    }
}

struct SnapshotRecord: Codable, Hashable, Identifiable {
    let id: String
    let documentPath: String
    let title: String
    let artifactPath: String
    let createdAt: Date
}

struct WorkspaceState: Codable {
    var tabPaths: [String] = []
    var activeTabPath: String?
    var tabContexts: [String: String] = [:]
    var expandedPaths: [String] = []
    var treeScrollOffset = 0.0
    var compatibleOnly = true
    var latexRootSelections: [String: String] = [:]
    var latexExternalGrants: [String: [String]] = [:]
    var snapshots: [SnapshotRecord] = []

    private enum CodingKeys: String, CodingKey {
        case tabPaths, activeTabPath, tabContexts, expandedPaths, treeScrollOffset
        case compatibleOnly, latexRootSelections, latexExternalGrants, snapshots
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabPaths = try container.decodeIfPresent([String].self, forKey: .tabPaths) ?? []
        activeTabPath = try container.decodeIfPresent(String.self, forKey: .activeTabPath)
        tabContexts = try container.decodeIfPresent([String: String].self, forKey: .tabContexts) ?? [:]
        expandedPaths = try container.decodeIfPresent([String].self, forKey: .expandedPaths) ?? []
        treeScrollOffset = try container.decodeIfPresent(Double.self, forKey: .treeScrollOffset) ?? 0
        compatibleOnly = try container.decodeIfPresent(Bool.self, forKey: .compatibleOnly) ?? true
        latexRootSelections = try container.decodeIfPresent([String: String].self, forKey: .latexRootSelections) ?? [:]
        latexExternalGrants = try container.decodeIfPresent([String: [String]].self, forKey: .latexExternalGrants) ?? [:]
        snapshots = try container.decodeIfPresent([SnapshotRecord].self, forKey: .snapshots) ?? []
    }
}

struct AppStateStore {
    private static let defaultsKey = "bp-viewer.appState"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppState {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return state
    }

    func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
