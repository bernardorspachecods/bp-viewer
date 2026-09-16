import Foundation

public enum PreviewStatus: String, Hashable, Sendable {
    case idle
    case updating
    case ready
    case stale
    case failed
    case unavailable
    case cancelled
    case timeout
}

public struct MarkdownReadingPosition: Codable, Hashable, Sendable {
    public let scrollY: Double
    public let anchorID: String?
    public let anchorOffset: Double

    public init(scrollY: Double, anchorID: String?, anchorOffset: Double) {
        self.scrollY = scrollY
        self.anchorID = anchorID
        self.anchorOffset = anchorOffset
    }
}

public struct PDFReadingPosition: Codable, Hashable, Sendable {
    public let pageIndex: Int
    public let x: Double?
    public let y: Double?

    public init(pageIndex: Int, x: Double?, y: Double?) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
    }
}

public enum MarkdownSaveState: String, Hashable, Sendable {
    case saved
    case unsaved
    case saving
    case conflict
    case failed
}

public struct MarkdownConflict: Hashable, Sendable {
    public let localSource: String
    public let externalSource: String
    public let blockIDs: [String]

    public init(localSource: String, externalSource: String, blockIDs: [String]) {
        self.localSource = localSource
        self.externalSource = externalSource
        self.blockIDs = blockIDs
    }
}

public struct MarkdownEditSession: Hashable, Sendable {
    public var mode: MarkdownEditingMode
    public var isEditing: Bool
    public var baseSource: String
    public var currentSource: String
    public var saveState: MarkdownSaveState
    public var undoSources: [String]
    public var redoSources: [String]
    public var conflict: MarkdownConflict?

    public init(
        mode: MarkdownEditingMode = .markdown,
        isEditing: Bool = true,
        baseSource: String,
        currentSource: String,
        saveState: MarkdownSaveState = .saved,
        undoSources: [String] = [],
        redoSources: [String] = [],
        conflict: MarkdownConflict? = nil
    ) {
        self.mode = mode
        self.isEditing = isEditing
        self.baseSource = baseSource
        self.currentSource = currentSource
        self.saveState = saveState
        self.undoSources = undoSources
        self.redoSources = redoSources
        self.conflict = conflict
    }
}

public struct CSVEditSession: Hashable, Sendable {
    public var isEditing: Bool
    public var baseSource: String
    public var currentSource: String
    public var saveState: MarkdownSaveState
    public var undoSources: [String]
    public var redoSources: [String]
    public var conflict: MarkdownConflict?

    public init(
        isEditing: Bool = true,
        baseSource: String,
        currentSource: String,
        saveState: MarkdownSaveState = .saved,
        undoSources: [String] = [],
        redoSources: [String] = [],
        conflict: MarkdownConflict? = nil
    ) {
        self.isEditing = isEditing
        self.baseSource = baseSource
        self.currentSource = currentSource
        self.saveState = saveState
        self.undoSources = undoSources
        self.redoSources = redoSources
        self.conflict = conflict
    }
}

public struct DocumentTab: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let kind: DocumentKind
    public var contextURL: URL?
    public var status: PreviewStatus
    public var isStale: Bool
    public var previewHTML: String?
    public var previewJSON: String?
    public var previewCSV: CSVDocument?
    public var csvEditSession: CSVEditSession?
    public var previewPDFData: Data?
    public var markdownOutline: [MarkdownOutlineEntry]
    public var isOutlineVisible: Bool
    public var previewZoom: Double
    public var isPreviewZoomCustomized: Bool
    public var previewPageIndex: Int
    public var markdownReadingPosition: MarkdownReadingPosition?
    public var pdfReadingPosition: PDFReadingPosition?
    public var previewUpdatedAt: Date?
    public var previewBaseURL: URL?
    public var previewDependencies: [URL]
    public var previewExternalDependencies: [URL]
    public var errorMessage: String?
    public var markdownSource: String?
    public var markdownBlocks: [MarkdownEditableBlock]
    public var markdownEditSession: MarkdownEditSession?
    public var jsonSource: String?
    public var jsonEditSession: MarkdownEditSession?
    public var jsonCursorUTF8Offset: Int?
    public var diffSession: DocumentDiffSession?

    public init(
        id: String,
        url: URL,
        kind: DocumentKind,
        contextURL: URL? = nil,
        status: PreviewStatus = .idle,
        isStale: Bool = false,
        previewHTML: String? = nil,
        previewJSON: String? = nil,
        previewCSV: CSVDocument? = nil,
        csvEditSession: CSVEditSession? = nil,
        previewPDFData: Data? = nil,
        markdownOutline: [MarkdownOutlineEntry] = [],
        isOutlineVisible: Bool = false,
        previewZoom: Double = 1.0,
        isPreviewZoomCustomized: Bool = false,
        previewPageIndex: Int = 0,
        markdownReadingPosition: MarkdownReadingPosition? = nil,
        pdfReadingPosition: PDFReadingPosition? = nil,
        previewUpdatedAt: Date? = nil,
        previewBaseURL: URL? = nil,
        previewDependencies: [URL] = [],
        previewExternalDependencies: [URL] = [],
        errorMessage: String? = nil,
        markdownSource: String? = nil,
        markdownBlocks: [MarkdownEditableBlock] = [],
        markdownEditSession: MarkdownEditSession? = nil,
        jsonSource: String? = nil,
        jsonEditSession: MarkdownEditSession? = nil,
        jsonCursorUTF8Offset: Int? = nil,
        diffSession: DocumentDiffSession? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.contextURL = contextURL
        self.status = status
        self.isStale = isStale
        self.previewHTML = previewHTML
        self.previewJSON = previewJSON
        self.previewCSV = previewCSV
        self.csvEditSession = csvEditSession
        self.previewPDFData = previewPDFData
        self.markdownOutline = markdownOutline
        self.isOutlineVisible = isOutlineVisible
        self.previewZoom = previewZoom
        self.isPreviewZoomCustomized = isPreviewZoomCustomized
        self.previewPageIndex = previewPageIndex
        self.markdownReadingPosition = markdownReadingPosition
        self.pdfReadingPosition = pdfReadingPosition
        self.previewUpdatedAt = previewUpdatedAt
        self.previewBaseURL = previewBaseURL
        self.previewDependencies = previewDependencies
        self.previewExternalDependencies = previewExternalDependencies
        self.errorMessage = errorMessage
        self.markdownSource = markdownSource
        self.markdownBlocks = markdownBlocks
        self.markdownEditSession = markdownEditSession
        self.jsonSource = jsonSource
        self.jsonEditSession = jsonEditSession
        self.jsonCursorUTF8Offset = jsonCursorUTF8Offset
        self.diffSession = diffSession
    }

    public var title: String { url.deletingPathExtension().lastPathComponent }

    public var subtitle: String {
        contextURL?.path ?? url.deletingLastPathComponent().lastPathComponent
    }
}

public struct AppState: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Self.currentSchemaVersion
    public var global = GlobalState()
    public var documentStates: [String: DocumentState] = [:]
    public var workspaceStates: [String: WorkspaceState] = [:]
    public var lastWorkspacePath: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, global, documentStates, workspaceStates, lastWorkspacePath
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        global = try container.decodeIfPresent(GlobalState.self, forKey: .global) ?? GlobalState()
        documentStates = try container.decodeIfPresent([String: DocumentState].self, forKey: .documentStates) ?? [:]
        workspaceStates = try container.decodeIfPresent([String: WorkspaceState].self, forKey: .workspaceStates) ?? [:]
        lastWorkspacePath = try container.decodeIfPresent(String.self, forKey: .lastWorkspacePath)
    }
}

public struct GlobalState: Codable, Sendable {
    public var theme = "dark"
    public var sidebarVisible = true
    public var sidebarWidth = 280.0
    public var latexShellEscapeMode = "disabled"
    public var defaultMarkdownZoom = 1.0
    public var defaultLatexZoom = 1.0

    private enum CodingKeys: String, CodingKey {
        case theme, sidebarVisible, sidebarWidth, latexShellEscapeMode
        case defaultMarkdownZoom, defaultLatexZoom
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        sidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 280
        latexShellEscapeMode = try container.decodeIfPresent(String.self, forKey: .latexShellEscapeMode) ?? "disabled"
        defaultMarkdownZoom = try container.decodeIfPresent(Double.self, forKey: .defaultMarkdownZoom) ?? 1.0
        defaultLatexZoom = try container.decodeIfPresent(Double.self, forKey: .defaultLatexZoom) ?? 1.0
    }
}

public struct DocumentState: Codable, Sendable {
    public var zoom: Double?
    public var outlineVisible: Bool
    public var markdownReadingPosition: MarkdownReadingPosition?
    public var pdfReadingPosition: PDFReadingPosition?

    private enum CodingKeys: String, CodingKey {
        case zoom, outlineVisible, markdownReadingPosition, pdfReadingPosition
    }

    public init(
        zoom: Double? = nil,
        outlineVisible: Bool = false,
        markdownReadingPosition: MarkdownReadingPosition? = nil,
        pdfReadingPosition: PDFReadingPosition? = nil
    ) {
        self.zoom = zoom
        self.outlineVisible = outlineVisible
        self.markdownReadingPosition = markdownReadingPosition
        self.pdfReadingPosition = pdfReadingPosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.0
        outlineVisible = try container.decodeIfPresent(Bool.self, forKey: .outlineVisible) ?? false
        markdownReadingPosition = try container.decodeIfPresent(MarkdownReadingPosition.self, forKey: .markdownReadingPosition)
        pdfReadingPosition = try container.decodeIfPresent(PDFReadingPosition.self, forKey: .pdfReadingPosition)
    }
}

public struct SnapshotRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let documentPath: String
    public let title: String
    public let artifactPath: String
    public let createdAt: Date

    public init(id: String, documentPath: String, title: String, artifactPath: String, createdAt: Date) {
        self.id = id
        self.documentPath = documentPath
        self.title = title
        self.artifactPath = artifactPath
        self.createdAt = createdAt
    }
}

public struct WorkspaceState: Codable, Sendable {
    public var tabPaths: [String] = []
    public var activeTabPath: String?
    public var tabContexts: [String: String] = [:]
    public var expandedPaths: [String] = []
    public var treeScrollOffset = 0.0
    public var compatibleOnly = true
    public var latexRootSelections: [String: String] = [:]
    public var latexExternalGrants: [String: [String]] = [:]
    public var snapshots: [SnapshotRecord] = []

    private enum CodingKeys: String, CodingKey {
        case tabPaths, activeTabPath, tabContexts, expandedPaths, treeScrollOffset
        case compatibleOnly, latexRootSelections, latexExternalGrants, snapshots
    }

    public init() {}

    public init(from decoder: Decoder) throws {
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

public struct AppStateStore {
    private static let defaultsKey = "bp-viewer.appState"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppState {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return state
    }

    public func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
