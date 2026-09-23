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

public struct SourceEditSession: Hashable, Sendable {
    public var mode: SourceEditingMode
    public var splitReturnMode: DocumentPresentationMode?
    public var isEditing: Bool
    public var baseSource: String
    public var currentSource: String
    public var saveState: MarkdownSaveState
    public var undoSources: [String]
    public var redoSources: [String]
    public var conflict: MarkdownConflict?

    public init(
        mode: SourceEditingMode = .markdown,
        splitReturnMode: DocumentPresentationMode? = nil,
        isEditing: Bool = true,
        baseSource: String,
        currentSource: String,
        saveState: MarkdownSaveState = .saved,
        undoSources: [String] = [],
        redoSources: [String] = [],
        conflict: MarkdownConflict? = nil
    ) {
        self.mode = mode
        self.splitReturnMode = splitReturnMode
        self.isEditing = isEditing
        self.baseSource = baseSource
        self.currentSource = currentSource
        self.saveState = saveState
        self.undoSources = undoSources
        self.redoSources = redoSources
        self.conflict = conflict
    }
}

public typealias MarkdownEditSession = SourceEditSession

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

public enum DocumentPresentationMode: Hashable, Sendable {
    case preview
    case source
    case split
    case diff(DocumentDiffMode)
}

public enum DocumentOutlineSizing {
    public static let defaultWidth = 250.0
    public static let minimumWidth = 220.0
    public static let maximumWidth = 480.0

    public static func clamped(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }
}

public struct DocumentTab: Identifiable, Hashable, Sendable {
    public var id: String
    public var url: URL
    public var kind: DocumentKind
    public var contextURL: URL?
    public var status: PreviewStatus
    public var isStale: Bool
    public var previewHTML: String?
    public var previewJSON: String?
    public var previewCSV: CSVDocument?
    public var csvEditSession: CSVEditSession?
    public var previewPDFData: Data?
    public var previewImageData: Data?
    public var latexSyncTeXData: Data?
    public var latexGeneratedBibliographySource: String?
    public var markdownOutline: [MarkdownOutlineEntry]
    public var isOutlineVisible: Bool
    public var outlineWidth: Double
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
    public var latexEditSession: SourceEditSession?
    public var latexCursorUTF8Offset: Int?
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
        previewImageData: Data? = nil,
        latexSyncTeXData: Data? = nil,
        latexGeneratedBibliographySource: String? = nil,
        markdownOutline: [MarkdownOutlineEntry] = [],
        isOutlineVisible: Bool = false,
        outlineWidth: Double = DocumentOutlineSizing.defaultWidth,
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
        latexEditSession: SourceEditSession? = nil,
        latexCursorUTF8Offset: Int? = nil,
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
        self.previewImageData = previewImageData
        self.latexSyncTeXData = latexSyncTeXData
        self.latexGeneratedBibliographySource = latexGeneratedBibliographySource
        self.markdownOutline = markdownOutline
        self.isOutlineVisible = isOutlineVisible
        self.outlineWidth = DocumentOutlineSizing.clamped(outlineWidth)
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
        self.latexEditSession = latexEditSession
        self.latexCursorUTF8Offset = latexCursorUTF8Offset
        self.jsonCursorUTF8Offset = jsonCursorUTF8Offset
        self.diffSession = diffSession
    }

    public static func untitledMarkdown() -> DocumentTab {
        let id = UUID().uuidString.lowercased()
        let url = URL(string: "bpviewer://untitled/\(id)")!
        return DocumentTab(
            id: url.absoluteString,
            url: url,
            kind: .markdown,
            status: .updating
        )
    }

    public var isUntitled: Bool {
        url.scheme?.lowercased() == "bpviewer"
            && url.host?.lowercased() == "untitled"
    }

    public var title: String { isUntitled ? "Untitled" : url.deletingPathExtension().lastPathComponent }

    public var subtitle: String {
        if isUntitled { return "Not saved" }
        return contextURL?.path ?? url.deletingLastPathComponent().lastPathComponent
    }

    public var editableSourceURL: URL {
        contextURL ?? url
    }

    public var presentationMode: DocumentPresentationMode {
        if let diffSession {
            return .diff(diffSession.mode)
        }
        if markdownEditSession?.isEditing == true,
           markdownEditSession?.mode == .split {
            return .split
        }
        if jsonEditSession?.isEditing == true,
           jsonEditSession?.mode == .split {
            return .split
        }
        if latexEditSession?.isEditing == true,
           latexEditSession?.mode == .split {
            return .split
        }
        if markdownEditSession?.isEditing == true
            || markdownEditSession?.conflict != nil
            || jsonEditSession?.isEditing == true
            || jsonEditSession?.conflict != nil
            || latexEditSession?.isEditing == true
            || latexEditSession?.conflict != nil {
            return .source
        }
        return .preview
    }

    public mutating func selectPresentationMode(_ mode: DocumentPresentationMode) {
        switch mode {
        case .preview:
            diffSession = nil
            markdownEditSession?.isEditing = false
            jsonEditSession?.isEditing = false
            latexEditSession?.isEditing = false
        case .source, .diff:
            diffSession = nil
            markdownEditSession?.mode = .markdown
            jsonEditSession?.mode = .markdown
            latexEditSession?.mode = .markdown
        case .split:
            diffSession = nil
            markdownEditSession?.mode = .split
            jsonEditSession?.mode = .split
            latexEditSession?.mode = .split
        }
    }

    public mutating func activateDiff(_ diffSession: DocumentDiffSession) {
        self.diffSession = diffSession
        markdownEditSession?.mode = .markdown
        jsonEditSession?.mode = .markdown
        latexEditSession?.mode = .markdown
    }

    public mutating func restorePreviousPresentationMode() {
        guard let diffSession else { return }
        self.diffSession = nil
        selectPresentationMode(diffSession.returnMode)
    }

    public mutating func relocate(from oldURL: URL, to newURL: URL) {
        guard !isUntitled else { return }
        guard let newLocation = relocatedURL(self.url, from: oldURL, to: newURL) else { return }

        url = newLocation
        id = newLocation.standardizedFileURL.path
        kind = DocumentKind(url: newLocation)
        contextURL = contextURL.flatMap { self.relocatedURL($0, from: oldURL, to: newURL) }
        previewBaseURL = previewBaseURL.flatMap { self.relocatedURL($0, from: oldURL, to: newURL) }
        previewDependencies = previewDependencies.compactMap { self.relocatedURL($0, from: oldURL, to: newURL) }
        previewExternalDependencies = previewExternalDependencies.compactMap { self.relocatedURL($0, from: oldURL, to: newURL) }
    }

    private func relocatedURL(_ candidate: URL, from oldURL: URL, to newURL: URL) -> URL? {
        let candidatePath = candidate.standardizedFileURL.path
        let oldPath = oldURL.standardizedFileURL.path
        guard candidatePath == oldPath || candidatePath.hasPrefix(oldPath + "/") else {
            return candidate
        }
        guard candidatePath != oldPath else { return newURL.standardizedFileURL }

        let relativePath = String(candidatePath.dropFirst(oldPath.count + 1))
        return newURL.standardizedFileURL.appendingPathComponent(relativePath)
    }
}

public struct AppState: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion = Self.currentSchemaVersion
    public var global = GlobalState()
    public var documentStates: [String: DocumentState] = [:]
    public var workspaceStates: [String: WorkspaceState] = [:]
    public var lastWorkspacePath: String?
    public var openWorkspacePaths: [String] = []
    public var activeWorkspacePath: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, global, documentStates, workspaceStates, lastWorkspacePath
        case openWorkspacePaths, activeWorkspacePath
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        global = try container.decodeIfPresent(GlobalState.self, forKey: .global) ?? GlobalState()
        documentStates = try container.decodeIfPresent([String: DocumentState].self, forKey: .documentStates) ?? [:]
        workspaceStates = try container.decodeIfPresent([String: WorkspaceState].self, forKey: .workspaceStates) ?? [:]
        lastWorkspacePath = try container.decodeIfPresent(String.self, forKey: .lastWorkspacePath)
        openWorkspacePaths = try container.decodeIfPresent([String].self, forKey: .openWorkspacePaths) ?? []
        activeWorkspacePath = try container.decodeIfPresent(String.self, forKey: .activeWorkspacePath)
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
    public var outlineWidth: Double
    public var markdownReadingPosition: MarkdownReadingPosition?
    public var pdfReadingPosition: PDFReadingPosition?

    private enum CodingKeys: String, CodingKey {
        case zoom, outlineVisible, outlineWidth, markdownReadingPosition, pdfReadingPosition
    }

    public init(
        zoom: Double? = nil,
        outlineVisible: Bool = false,
        outlineWidth: Double = DocumentOutlineSizing.defaultWidth,
        markdownReadingPosition: MarkdownReadingPosition? = nil,
        pdfReadingPosition: PDFReadingPosition? = nil
    ) {
        self.zoom = zoom
        self.outlineVisible = outlineVisible
        self.outlineWidth = DocumentOutlineSizing.clamped(outlineWidth)
        self.markdownReadingPosition = markdownReadingPosition
        self.pdfReadingPosition = pdfReadingPosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.0
        outlineVisible = try container.decodeIfPresent(Bool.self, forKey: .outlineVisible) ?? false
        outlineWidth = DocumentOutlineSizing.clamped(
            try container.decodeIfPresent(Double.self, forKey: .outlineWidth)
                ?? DocumentOutlineSizing.defaultWidth
        )
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
    public var securityScopedBookmark: Data?
    public var snapshots: [SnapshotRecord] = []

    private enum CodingKeys: String, CodingKey {
        case tabPaths, activeTabPath, tabContexts, expandedPaths, treeScrollOffset
        case compatibleOnly, latexRootSelections, latexExternalGrants, securityScopedBookmark, snapshots
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
        securityScopedBookmark = try container.decodeIfPresent(Data.self, forKey: .securityScopedBookmark)
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
