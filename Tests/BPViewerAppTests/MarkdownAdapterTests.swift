import Testing
import Foundation
@testable import BPViewerApp
@testable import BPViewerCore

@Test("renders core Markdown and keeps resource URLs relative")
func rendersCoreMarkdownAndKeepsResourceURLsRelative() throws {
        let source = """
        # Heading

        This is **important** with [a link](chapter-2.md) and an image:

        ![Figure](images/figure.png)
        """

        let result = try SwiftMarkdownAdapter().render(
            source: source,
            baseURL: URL(fileURLWithPath: "/tmp/project/chapter-1")
        )

    #expect(result.html.contains("<h1 id=\"heading\""))
    #expect(result.html.contains("<strong>important</strong>"))
    #expect(result.html.contains("href=\"bpviewer://open-local-file?path=/tmp/project/chapter-1/chapter-2.md\""))
    #expect(result.html.contains("src=\"images/figure.png\""))
}

@Test("keeps the Markdown page width stable while the preview resizes")
func keepsMarkdownPageWidthStableWhilePreviewResizes() throws {
    let result = try SwiftMarkdownAdapter().render(
        source: "# Heading",
        baseURL: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(result.html.contains("<main class=\"bp-document-content\">"))
    #expect(result.html.contains("body {"))
    #expect(result.html.contains("width: 100%;"))
    #expect(result.html.contains("overflow-x: hidden;"))
    #expect(result.html.contains("scrollbar-gutter: stable;"))
    #expect(result.html.contains("margin: 0;"))
    #expect(result.html.contains(".bp-document-content {"))
    #expect(result.html.contains("max-width: 860px;"))
}

@Test("clamps and persists the outline width per document")
func clampsAndPersistsOutlineWidthPerDocument() throws {
    let state = DocumentState(
        outlineVisible: true,
        outlineWidth: 340
    )
    let encoded = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(DocumentState.self, from: encoded)

    #expect(decoded.outlineVisible)
    #expect(decoded.outlineWidth == 340)
    #expect(DocumentState(outlineWidth: 80).outlineWidth == DocumentOutlineSizing.minimumWidth)
    #expect(DocumentState(outlineWidth: 900).outlineWidth == DocumentOutlineSizing.maximumWidth)
}

@Test("does not pass raw HTML through to the preview")
func doesNotPassRawHTMLThroughToThePreview() throws {
        let source = """
        # Safe title

        <script>alert('unsafe')</script>
        <span>raw HTML</span>
        """

        let result = try SwiftMarkdownAdapter().render(
            source: source,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )

    #expect(result.html.contains("<h1 id=\"safe-title\""))
    #expect(!result.html.contains("<script"))
    #expect(!result.html.contains("<span>raw HTML</span>"))
}

@Test("renders common TeX math as local MathML")
func rendersCommonTeXMathAsLocalMathML() throws {
    let result = try SwiftMarkdownAdapter().render(
        source: "Einstein: $E = mc^2$\n\n$$\\frac{a}{b}$$",
        baseURL: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(result.html.contains("<math"))
    #expect(result.html.contains("<msup>"))
    #expect(result.html.contains("<mfrac>"))
}

@Test("exposes a navigable outline with stable heading IDs")
func exposesNavigableMarkdownOutline() throws {
    let source = """
    # Introduction

    ## Methods

    ```markdown
    # Not a heading
    ```

    ## Methods
    """

    let result = try SwiftMarkdownAdapter().render(
        source: source,
        baseURL: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(result.outline.map(\.title) == ["Introduction", "Methods", "Methods"])
    #expect(result.outline.map(\.level) == [1, 2, 2])
    #expect(result.outline.map(\.id) == ["introduction", "methods", "methods-2"])
    #expect(result.outline.allSatisfy { result.html.contains("id=\"\($0.id)\"") })
}

@Test("produces the normalized absolute path used by copy-path actions")
func producesNormalizedAbsolutePathForCopyActions() {
    let url = URL(fileURLWithPath: "/tmp/project/chapters/../working.md")

    #expect(FilePathCopy.string(for: url) == "/tmp/project/working.md")
}

@Test("renames, duplicates, and moves workspace items within the project root")
func performsWorkspaceFileOperationsWithinProjectRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-file-operations-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    let source = sourceDirectory.appendingPathComponent("notes.md")

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    try "# Notes".write(to: source, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let renamed = try WorkspaceFileOperations.rename(
        itemAt: source,
        to: "renamed.md",
        in: root
    )
    #expect(renamed.lastPathComponent == "renamed.md")
    #expect(FileManager.default.fileExists(atPath: renamed.path))

    let duplicate = try WorkspaceFileOperations.duplicate(itemAt: renamed, in: root)
    #expect(duplicate.lastPathComponent == "renamed copy.md")
    #expect(FileManager.default.fileExists(atPath: duplicate.path))

    let moved = try WorkspaceFileOperations.move(
        itemAt: duplicate,
        to: destinationDirectory,
        in: root
    )
    #expect(moved == destinationDirectory.appendingPathComponent("renamed copy.md"))
    #expect(FileManager.default.fileExists(atPath: moved.path))

    let movedToRoot = try WorkspaceFileOperations.move(
        itemAt: renamed,
        to: root,
        in: root
    )
    #expect(movedToRoot == root.appendingPathComponent("renamed.md"))
    #expect(FileManager.default.fileExists(atPath: movedToRoot.path))

    let movedFolder = try WorkspaceFileOperations.move(
        itemAt: sourceDirectory,
        to: destinationDirectory,
        in: root
    )
    #expect(movedFolder == destinationDirectory.appendingPathComponent("source", isDirectory: true))
    #expect(FileManager.default.fileExists(atPath: movedFolder.path))
}

@Test("persists LaTeX approvals across coordinator instances")
@MainActor
func persistsLatexApprovalsAcrossCoordinatorInstances() {
    let suiteName = "bp-viewer-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let projectRoot = URL(fileURLWithPath: "/tmp/project")
    let latexRoot = projectRoot.appendingPathComponent("main.tex")
    let dependency = LatexExternalDependency(
        url: URL(fileURLWithPath: "/tmp/assets/../assets/figure.pdf"),
        sourceURL: latexRoot
    )

    WorkspaceSessionCoordinator(store: AppStateStore(defaults: defaults))
        .approveLatexExternalDependencies(
            [dependency],
            rootURL: latexRoot,
            projectRoot: projectRoot
        )

    let restored = WorkspaceSessionCoordinator(store: AppStateStore(defaults: defaults))
    let grantKey = "/tmp/project\n/tmp/project/main.tex"

    #expect(restored.approvedLatexExternalPaths(for: projectRoot)[grantKey] == ["/tmp/assets/figure.pdf"])
}

@Test("persists a security-scoped bookmark for an opened folder")
@MainActor
func persistsSecurityScopedBookmarkForOpenedFolder() throws {
    let suiteName = "bp-viewer-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-bookmark-(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let coordinator = WorkspaceSessionCoordinator(store: AppStateStore(defaults: defaults))
    #expect(coordinator.storeSecurityScopedBookmark(for: folder))

    let restored = WorkspaceSessionCoordinator(store: AppStateStore(defaults: defaults))
    let resolution = try restored.resolveSecurityScopedBookmark(for: folder)

    #expect(resolution.url.standardizedFileURL == folder.standardizedFileURL)
    #expect(!resolution.isStale)
}

@Test("flattens expanded tree branches into individually lazy rows")
func flattensExpandedTreeBranchesIntoLazyRows() {
    let folderURL = URL(fileURLWithPath: "/tmp/project/chapters", isDirectory: true)
    let fileURL = folderURL.appendingPathComponent("intro.md")
    let file = FileNode(
        id: "chapters/intro.md",
        url: fileURL,
        relativePath: "chapters/intro.md",
        isDirectory: false,
        kind: .markdown,
        children: [],
        childrenLoaded: true
    )
    let folder = FileNode(
        id: "chapters",
        url: folderURL,
        relativePath: "chapters",
        isDirectory: true,
        kind: .other,
        children: [file],
        childrenLoaded: true
    )

    let items = SidebarTreeItem.flatten(
        nodes: [folder],
        expandedPaths: [folder.id]
    )

    #expect(items.map(\.id) == ["chapters", "chapters/intro.md"])
    #expect(items.map(\.level) == [0, 1])
}

@Test("clears all folder expansion records or one folder branch")
@MainActor
func clearsFolderExpansionRecords() {
    let session = WorkspaceTreeSession(
        onStateChange: { _ in },
        onPersistenceRequested: {}
    )
    session.restore(
        expandedPaths: ["chapters", "chapters/part-one", "assets"],
        treeScrollOffset: 0,
        compatibleOnly: true,
        automaticSingleChildExpansion: true
    )

    session.collapseFolder("chapters")
    #expect(session.snapshot.expandedPaths == ["assets"])

    session.collapseAllFolders()
    #expect(session.snapshot.expandedPaths.isEmpty)
}

@Test("expands every ancestor when revealing a workspace file")
@MainActor
func revealsWorkspaceFileByExpandingAncestors() {
    let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let target = root
        .appendingPathComponent("chapters", isDirectory: true)
        .appendingPathComponent("part-one", isDirectory: true)
        .appendingPathComponent("intro.md")
    let session = WorkspaceTreeSession(
        onStateChange: { _ in },
        onPersistenceRequested: {}
    )

    session.reset(rootURL: root)
    session.reveal(url: target)

    #expect(session.snapshot.expandedPaths == ["chapters", "chapters/part-one"])
}

@Test("rejects moving a workspace item outside the project root")
func rejectsWorkspaceFileOperationsOutsideProjectRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-file-operations-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("notes.md")
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-outside-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try "# Notes".write(to: source, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    #expect(throws: WorkspaceFileOperationError.destinationOutsideWorkspace) {
        try WorkspaceFileOperations.move(itemAt: source, to: outside, in: root)
    }
}

@Test("relocates an open tab and its preview paths when its file moves")
func relocatesOpenDocumentTabPaths() {
    let oldURL = URL(fileURLWithPath: "/tmp/project/old/notes.md")
    let newURL = URL(fileURLWithPath: "/tmp/project/new/notes.md")
    var tab = DocumentTab(
        id: oldURL.path,
        url: oldURL,
        kind: .markdown,
        contextURL: oldURL.deletingLastPathComponent(),
        previewBaseURL: oldURL.deletingLastPathComponent(),
        previewDependencies: [oldURL.deletingLastPathComponent().appendingPathComponent("image.png")]
    )

    tab.relocate(from: oldURL.deletingLastPathComponent(), to: newURL.deletingLastPathComponent())

    #expect(tab.id == newURL.path)
    #expect(tab.url == newURL)
    #expect(tab.contextURL == newURL.deletingLastPathComponent())
    #expect(tab.previewBaseURL == newURL.deletingLastPathComponent())
    #expect(tab.previewDependencies == [newURL.deletingLastPathComponent().appendingPathComponent("image.png")])
}

@Test("recognizes Word documents as supported preview files")
func recognizesWordDocuments() {
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/report.docx")) == .docx)
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/REPORT.DOCX")) == .docx)
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/report.doc")) == .other)
}

@Test("recognizes CSV documents as supported preview files")
func recognizesCSVDocuments() {
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/data.csv")) == .csv)
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/DATA.CSV")) == .csv)
}

@Test("parses quoted CSV fields, escaped quotes, and line breaks")
func parsesCSVFields() throws {
    let source = "Name,Note\nAlice,\"hello\nworld\"\nBob,\"He said \"\"hi\"\"\""
    let document = try CSVPreviewAdapter().parse(source: source)

    #expect(document.rows == [
        ["Name", "Note"],
        ["Alice", "hello\nworld"],
        ["Bob", "He said \"hi\""]
    ])
}

@Test("detects semicolon-delimited CSV files")
func detectsSemicolonDelimitedCSV() throws {
    let document = try CSVPreviewAdapter().parse(source: "Name;Age\nAlice;42")

    #expect(document.delimiter == ";")
    #expect(document.rows == [["Name", "Age"], ["Alice", "42"]])
}

@Test("parses CRLF CSV records as separate rows")
func parsesCRLFCSVRecords() throws {
    let document = try CSVPreviewAdapter().parse(source: "Name,Age\r\nAlice,42\r\nBob,37")

    #expect(document.rows == [["Name", "Age"], ["Alice", "42"], ["Bob", "37"]])
}

@Test("updates and serializes a CSV cell using the detected delimiter")
func updatesAndSerializesCSVCell() throws {
    let adapter = CSVPreviewAdapter()
    let document = try adapter.parse(source: "Name;Note\nAlice;plain")
    let updated = try #require(document.replacingCell(atRow: 1, column: 1, with: "needs;quotes"))

    #expect(adapter.serialize(document: updated) == "Name;Note\nAlice;\"needs;quotes\"")
}

@Test("serializes CSV quotes and line breaks safely")
func serializesCSVQuotesAndLineBreaks() throws {
    let document = try CSVPreviewAdapter().parse(source: "Name,Note\nAlice,plain")
    let updated = try #require(document.replacingCell(atRow: 1, column: 1, with: "He said \"hi\"\nnext"))

    #expect(CSVPreviewAdapter().serialize(document: updated) == "Name,Note\nAlice,\"He said \"\"hi\"\"\nnext\"")
}

@Test("renders CSV spreadsheet coordinates and focusable cells")
func rendersCSVSpreadsheetCoordinates() throws {
    let document = try CSVPreviewAdapter().parse(source: "Name,Age\nAlice,42")
    let html = CSVPreviewAdapter().html(document: document, isDark: false)

    #expect(html.contains("data-column-header=\"A\""))
    #expect(html.contains("data-column-header=\"B\""))
    #expect(html.contains("data-row-header=\"1\""))
    #expect(html.contains("data-row-index=\"0\" data-column-index=\"0\""))
    #expect(html.contains("tabindex=\"0\""))
    #expect(html.contains("data-row-index=\"0\" data-column-index=\"0\" tabindex=\"0\" aria-selected=\"false\""))
    #expect(!html.contains("aria-selected=\"true\""))
    #expect(html.contains(">Name</div>"))
    #expect(html.contains("data-row-index=\"1\" data-column-index=\"0\""))
    #expect(html.contains("<div class=\"sheet\" data-bp-csv"))
    #expect(html.contains("grid-template-columns: 42px repeat(2"))
    #expect(!html.contains("<table data-bp-csv"))
    #expect(html.contains("background-color: #e9e9eb !important"))
    #expect(html.contains(".coordinate-header"))
    #expect(!html.contains("opacity: 0.56"))
    #expect(!html.contains("selected-header"))
}

@Test("CSV preview exposes keyboard navigation for the active cell")
func exposesCSVKeyboardNavigation() throws {
    let document = try CSVPreviewAdapter().parse(source: "Name,Age\nAlice,42")
    let html = CSVPreviewAdapter().html(document: document, isDark: false)

    #expect(html.contains("ArrowRight"))
    #expect(html.contains("ArrowLeft"))
    #expect(html.contains("ArrowDown"))
    #expect(html.contains("ArrowUp"))
    #expect(html.contains("event.key === 'Tab'"))
    #expect(html.contains("event.key === 'Enter'"))
    #expect(html.contains("function revealCell"))
    #expect(html.contains("const visibleLeft"))
    #expect(html.contains("viewport.scrollLeft"))
    #expect(html.contains("let hasActiveSelection = false"))
    #expect(html.contains("if (hasActiveSelection)"))
    #expect(html.contains("dblclick"))
    #expect(html.contains("if (editingCell !== cell)"))
    #expect(html.contains("contentEditable = 'true'"))
    #expect(html.contains("function commitCellEditing"))
    #expect(html.contains("commitCellEditing();"))
    #expect(!html.contains("cellChangedAndSave"))
    #expect(html.contains("document.addEventListener('keydown'"))
    #expect(html.contains("if (event.key !== 'Escape' || editingCell)"))
    #expect(html.contains("type: 'save'"))
    #expect(html.contains("window.webkit.messageHandlers.csvEdit.postMessage"))
}

@Test("hides completed document actions after saving")
@MainActor
func hidesCompletedDocumentActionsAfterSaving() {
    let savedBar = DocumentEditActionBar(
        saveState: .saved,
        onDiscard: {},
        onSave: {}
    )
    let unsavedBar = DocumentEditActionBar(
        saveState: .unsaved,
        onDiscard: {},
        onSave: {}
    )

    #expect(savedBar.showsStatus == false)
    #expect(savedBar.showsDiscardChanges == false)
    #expect(savedBar.isSaveDisabled)
    #expect(savedBar.saveButtonOpacity == 0.55)
    #expect(unsavedBar.showsStatus)
    #expect(unsavedBar.showsDiscardChanges)
    #expect(unsavedBar.isSaveDisabled == false)
    #expect(unsavedBar.saveButtonOpacity == 1)
}

@Test("rejects CSV files with an unterminated quoted field")
func rejectsUnterminatedCSVField() {
    #expect(throws: CSVPreviewError.self) {
        try CSVPreviewAdapter().parse(source: "Name,Note\nAlice,\"missing end")
    }
}

@Test("Markdown editing exposes source and split modes")
func exposesMarkdownEditingModes() {
    #expect(MarkdownEditingMode.allCases == [.markdown, .split])
    #expect(MarkdownEditingMode(rawValue: "visual") == nil)
}

@Test("discards an active Markdown draft without closing its tab")
@MainActor
func discardsActiveMarkdownDraftWithoutClosingTab() {
    let tabID = "file:///tmp/project/notes.md"
    let tab = DocumentTab(
        id: tabID,
        url: URL(fileURLWithPath: "/tmp/project/notes.md"),
        kind: .markdown,
        markdownSource: "# Draft",
        markdownEditSession: MarkdownEditSession(
            baseSource: "# Saved",
            currentSource: "# Draft",
            saveState: .unsaved,
            undoSources: ["# Saved"]
        )
    )
    let model = AppModel()
    model.tabs = [tab]
    model.activeTabID = tabID

    model.discardEditing(tabID: tabID)

    let updated = model.tabs[0]
    #expect(model.tabs.count == 1)
    #expect(updated.markdownEditSession?.currentSource == "# Saved")
    #expect(updated.markdownEditSession?.isEditing == true)
    #expect(updated.markdownEditSession?.saveState == .saved)
    #expect(updated.markdownEditSession?.undoSources.isEmpty == true)
}

@Test("keeps CSV editing active after discarding its draft")
@MainActor
func keepsCSVEditingActiveAfterDiscardingDraft() throws {
    let source = "Name,Age\nAlice,30"
    let editedSource = "Name,Age\nAlice,31"
    let url = URL(fileURLWithPath: "/tmp/bp-viewer-discard-csv-\(UUID().uuidString).csv")
    let tabID = url.path
    let tab = DocumentTab(
        id: tabID,
        url: url,
        kind: .csv,
        previewCSV: try CSVPreviewAdapter().parse(source: editedSource),
        csvEditSession: CSVEditSession(
            baseSource: source,
            currentSource: editedSource,
            saveState: .unsaved
        )
    )
    let model = AppModel()
    model.tabs = [tab]
    model.activeTabID = tabID

    model.discardEditing(tabID: tabID)

    let updated = model.tabs[0]
    #expect(updated.csvEditSession?.currentSource == source)
    #expect(updated.csvEditSession?.isEditing == true)
    #expect(updated.csvEditSession?.saveState == .saved)
    #expect(updated.previewCSV?.rows[1][1] == "30")
}

@Test("undoes and redoes CSV cell edits without saving the file")
@MainActor
func undoesAndRedoesCSVCellEditsWithoutSavingFile() throws {
    let source = "Name,Age\nAlice,30"
    let editedSource = "Name,Age\nAlice,31"
    let url = URL(fileURLWithPath: "/tmp/bp-viewer-undo-csv-\(UUID().uuidString).csv")
    let tabID = url.path
    let tab = DocumentTab(
        id: tabID,
        url: url,
        kind: .csv,
        previewCSV: try CSVPreviewAdapter().parse(source: source)
    )
    let model = AppModel()
    model.tabs = [tab]
    model.activeTabID = tabID

    model.updateCSVEditing(tabID: tabID, row: 1, column: 1, value: "31")
    #expect(model.tabs[0].csvEditSession?.currentSource == editedSource)
    #expect(model.tabs[0].csvEditSession?.undoSources == [source])
    #expect(model.undoCSVEdit())
    #expect(model.tabs[0].previewCSV?.rows[1][1] == "30")
    #expect(model.tabs[0].csvEditSession?.saveState == .saved)
    #expect(model.tabs[0].csvEditSession?.redoSources == [editedSource])
    #expect(model.redoCSVEdit())
    #expect(model.tabs[0].previewCSV?.rows[1][1] == "31")
    #expect(model.tabs[0].csvEditSession?.saveState == .unsaved)
}

@Test("saves an active CSV edit through the shared editing action")
@MainActor
func savesActiveCSVEditThroughSharedEditingAction() async throws {
    let source = "Name,Age\nAlice,30"
    let editedSource = "Name,Age\nAlice,31"
    let url = URL(fileURLWithPath: "/tmp/bp-viewer-shared-csv-(UUID().uuidString).csv")
    try source.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let tab = DocumentTab(
        id: url.path,
        url: url,
        kind: .csv,
        previewCSV: try CSVPreviewAdapter().parse(source: source),
        csvEditSession: CSVEditSession(
            baseSource: source,
            currentSource: editedSource,
            saveState: .unsaved
        )
    )
    let model = AppModel()
    model.tabs = [tab]

    #expect(await model.saveCSVEditing(tabID: url.path))
    #expect(try String(contentsOf: url, encoding: .utf8) == editedSource)
    #expect(model.tabs[0].csvEditSession?.baseSource == editedSource)
    #expect(model.tabs[0].csvEditSession?.saveState == .saved)
    #expect(model.tabs[0].previewCSV?.rows[1][1] == "31")
}

@Test("finds text case-insensitively without distinguishing accents")
func findsTextWithNormalizedMatching() {
    let matches = TextSearch.matches(in: "Café cafe", query: "CAFE")

    #expect(matches.map(\.utf16Range) == [0..<4, 5..<9])
}

@Test("find navigation wraps in both directions")
func findNavigationWraps() {
    #expect(TextSearch.nextMatchIndex(currentIndex: 1, matchCount: 3, backwards: false) == 2)
    #expect(TextSearch.nextMatchIndex(currentIndex: 2, matchCount: 3, backwards: false) == 0)
    #expect(TextSearch.nextMatchIndex(currentIndex: 0, matchCount: 3, backwards: true) == 2)
    #expect(TextSearch.nextMatchIndex(currentIndex: nil, matchCount: 3, backwards: true) == 2)
}

@Test("does not reapply the persisted page while PDF search navigates")
func preservesPDFSearchDestinationDuringViewUpdate() {
    #expect(
        PDFPreviewUpdatePolicy.shouldSynchronizeReadingPosition(
            afterFindNavigationHandled: true
        ) == false
    )
}

@Test("does not capture Markdown reading position for viewport resizing")
func ignoresMarkdownViewportResizeWhenTrackingScroll() {
    let beforeResize = CGRect(x: 0, y: 420, width: 800, height: 600)
    let afterResize = CGRect(x: 0, y: 420, width: 1_050, height: 600)
    let afterScroll = CGRect(x: 0, y: 520, width: 800, height: 600)

    #expect(
        MarkdownScrollObservationPolicy.shouldCapture(
            previousBounds: beforeResize,
            currentBounds: afterResize
        ) == false
    )
    #expect(
        MarkdownScrollObservationPolicy.shouldCapture(
            previousBounds: beforeResize,
            currentBounds: afterScroll
        ) == true
    )
}

@Test("keeps explicit PDF page navigation available")
func appliesExplicitPDFPageNavigationDuringViewUpdate() {
    #expect(
        PDFPreviewUpdatePolicy.pageIndexToApply(
            documentChanged: false,
            requestedPageIndex: 3,
            pageIndex: 0
        ) == 3
    )
}

@Test("keeps the editor cursor when no find query is active")
func keepsEditorCursorWithoutFindQuery() {
    #expect(SourceEditorFindSelectionPolicy.shouldSelectMatch(query: "", matchCount: 0) == false)
    #expect(SourceEditorFindSelectionPolicy.shouldSelectMatch(query: "   ", matchCount: 0) == false)
    #expect(SourceEditorFindSelectionPolicy.shouldSelectMatch(query: "heading", matchCount: 1))
}

@Test("numbers every source line, including empty and trailing lines")
func numbersEverySourceLineIncludingEmptyLines() {
    #expect(SourceEditorLineNumbering.lineCount(in: "one\n\nthree\n") == 4)
    #expect(SourceEditorLineNumbering.lineNumber(atUTF16Offset: 4, in: "one\n\nthree\n") == 2)
    #expect(SourceEditorLineNumbering.lineNumber(atUTF16Offset: 5, in: "one\n\nthree\n") == 3)
}

@Test("maps glyph locations to the line baseline")
func mapsGlyphLocationsToTheLineBaseline() {
    #expect(
        SourceEditorLayout.lineBaselineY(
            lineFragmentRect: CGRect(x: 0, y: 24, width: 200, height: 24),
            glyphLocationY: 21
        ) == 45
    )
}

@Test("keeps the extra line fragment on the configured baseline")
func keepsExtraLineFragmentOnTheConfiguredBaseline() {
    #expect(
        SourceEditorLayout.extraLineBaselineOffset(
            lineHeight: 24,
            defaultBaselineOffset: 13,
            defaultLineHeight: 16
        ) == 21
    )
}

@Test("keeps the trailing line fragment at the editor line height")
func keepsTrailingLineFragmentAtEditorLineHeight() {
    #expect(
        SourceEditorLayout.normalizedLineHeight(
            extraLineHeight: 10,
            configuredLineHeight: 24
        ) == 24
    )
}

@Test("starts the trailing line after the previous line fragment")
func startsTrailingLineAfterPreviousLineFragment() {
    #expect(
        SourceEditorLayout.normalizedExtraLineRect(
            extraLineRect: CGRect(x: 0, y: 96, width: 0, height: 10),
            previousLineMaxY: 100,
            configuredLineHeight: 24
        ) == CGRect(x: 0, y: 100, width: 0, height: 24)
    )
}

@Test("keeps the final diff line inside the full-width highlight row")
func keepsFinalDiffLineInsideFullWidthHighlightRow() {
    #expect(
        SourceEditorLayout.lineHighlightRect(
            lineFragmentRect: CGRect(x: 0, y: 48, width: 240, height: 24),
            textContainerOrigin: CGPoint(x: 52, y: 40),
            viewWidth: 360,
            verticalOffset: 10
        ) == CGRect(x: 0, y: 98, width: 360, height: 24)
    )
}

@Test("builds a side by side diff with stable line numbers")
func buildsSideBySideDiffWithStableLineNumbers() {
    let diff = DocumentDiffEngine().compare(
        reference: "one\ntwo\nthree",
        edited: "one\nchanged\nthree\nfour"
    )

    #expect(diff.hasChanges)
    #expect(diff.rows.count == 4)
    #expect(diff.rows[0].left?.lineNumber == 1)
    #expect(diff.rows[0].left?.text == "one")
    #expect(diff.rows[0].right?.lineNumber == 1)
    #expect(diff.rows[0].right?.text == "one")
    #expect(diff.rows[1].left?.lineNumber == 2)
    #expect(diff.rows[1].left?.text == "two")
    #expect(diff.rows[1].right?.lineNumber == 2)
    #expect(diff.rows[1].right?.text == "changed")
    #expect(diff.rows[1].left?.kind == .removed)
    #expect(diff.rows[1].right?.kind == .added)
    #expect(diff.rows[2].left?.lineNumber == 3)
    #expect(diff.rows[2].right?.lineNumber == 3)
    #expect(diff.rows[3].left == nil)
    #expect(diff.rows[3].right?.lineNumber == 4)
    #expect(diff.rows[3].right?.text == "four")
    #expect(diff.rightLineKinds == [
        1: .unchanged,
        2: .added,
        3: .unchanged,
        4: .added
    ])
}

@Test("keeps replaced lines on the same diff row")
func keepsReplacedLinesOnTheSameDiffRow() {
    let diff = DocumentDiffEngine().compare(
        reference: "before",
        edited: "after"
    )

    #expect(diff.rows.count == 1)
    #expect(diff.rows[0].left?.lineNumber == 1)
    #expect(diff.rows[0].left?.text == "before")
    #expect(diff.rows[0].left?.kind == .removed)
    #expect(diff.rows[0].right?.lineNumber == 1)
    #expect(diff.rows[0].right?.text == "after")
    #expect(diff.rows[0].right?.kind == .added)
}

@Test("uses one AppKit layout model for wrapped diff rows")
func usesOneAppKitLayoutModelForWrappedDiffRows() {
    let diff = DocumentDiffEngine().compare(
        reference: "one\nthree\nfour",
        edited: "one\nthis inserted line is deliberately long enough to wrap across the diff column\nthree\nfour"
    )
    let layout = DocumentDiffLayout(
        diff: diff,
        panelWidth: 360,
        zoom: 1,
        monospaced: true
    )

    #expect((layout.referenceLineSpacingBefore[3] ?? 0) > 0)
    #expect(layout.referenceLineSpacingBefore[4] == 0)
    #expect(layout.editedLineSpacingBefore[2] == 0)
    #expect(layout.editedLineSpacingBefore[3] == 0)
}

@Test("reports an unchanged document without diff rows marked as changes")
func reportsUnchangedDocument() {
    let diff = DocumentDiffEngine().compare(reference: "same", edited: "same")

    #expect(!diff.hasChanges)
    #expect(diff.addedLineCount == 0)
    #expect(diff.removedLineCount == 0)
    #expect(diff.rows.count == 1)
    #expect(diff.rows[0].left?.kind == .unchanged)
    #expect(diff.rows[0].right?.kind == .unchanged)
}

@Test("resolves a Git HEAD baseline through the process seam")
func resolvesGitHeadBaselineThroughProcessSeam() {
    let provider = GitHeadDocumentDiffBaselineProvider(runner: StubGitProcessRunner())
    let result = provider.baseline(for: URL(fileURLWithPath: "/tmp/project/notes.md"))

    guard case let .available(baseline) = result else {
        Issue.record("Expected a Git HEAD baseline")
        return
    }
    #expect(baseline.label == "HEAD")
    #expect(baseline.source == "from head")
}

@Test("restores a tracked file to Git HEAD including staged and worktree changes")
func restoresTrackedFileToGitHead() {
    let runner = RecordingGitProcessRunner()
    let restorer = GitHeadDocumentRestorer(runner: runner)

    let result = restorer.restoreToHead(for: URL(fileURLWithPath: "/tmp/project/notes.md"))

    guard case let .restored(source) = result else {
        Issue.record("Expected the file to be restored from Git HEAD")
        return
    }
    #expect(source == "from head")
    #expect(runner.requests.map(\.arguments) == [
        ["-C", "/tmp/project", "rev-parse", "--show-toplevel"],
        ["show", "HEAD:notes.md"],
        ["restore", "--source=HEAD", "--staged", "--worktree", "--", "notes.md"]
    ])
}

@Test("does not restore a file that has no version in Git HEAD")
func doesNotRestoreFileWithoutGitHeadVersion() {
    let runner = RecordingGitProcessRunner(headResult: ProcessResult(
        status: .failed,
        exitCode: 128,
        standardOutput: "",
        standardError: "pathspec 'notes.md' did not match any file(s) known to git"
    ))
    let restorer = GitHeadDocumentRestorer(runner: runner)

    let result = restorer.restoreToHead(for: URL(fileURLWithPath: "/tmp/project/notes.md"))

    guard case let .unavailable(message) = result else {
        Issue.record("Expected Git restore to be unavailable without a HEAD version")
        return
    }
    #expect(message == "This file has no version in the latest Git commit.")
    #expect(runner.requests.count == 2)
}

@Test("uses direct labels for document diff modes")
func usesDirectLabelsForDocumentDiffModes() {
    #expect(DocumentDiffMode.savedOnDisk.label == "Disk Diff")
    #expect(DocumentDiffMode.gitHead.label == "Git Diff")
}

@Test("toggles document editing modes directly")
@MainActor
func togglesDocumentEditingModesDirectly() {
    let tabID = "file:///tmp/project/notes.md"
    let model = AppModel()
    model.tabs = [
        DocumentTab(
            id: tabID,
            url: URL(fileURLWithPath: "/tmp/project/notes.md"),
            kind: .markdown,
            markdownEditSession: MarkdownEditSession(
                baseSource: "# Notes",
                currentSource: "# Notes"
            )
        )
    ]

    model.toggleMarkdownSplitView(tabID: tabID)
    #expect(model.tabs[0].markdownEditSession?.mode == .split)

    model.toggleDocumentDiff(mode: .savedOnDisk, tabID: tabID)
    #expect(model.tabs[0].markdownEditSession?.mode == .markdown)
    #expect(model.tabs[0].presentationMode == .diff(.savedOnDisk))
    #expect(model.tabs[0].diffSession?.mode == .savedOnDisk)

    model.toggleDocumentDiff(mode: .gitHead, tabID: tabID)
    #expect(model.tabs[0].presentationMode == .diff(.gitHead))
    #expect(model.tabs[0].markdownEditSession?.mode == .markdown)

    model.toggleMarkdownSplitView(tabID: tabID)
    #expect(model.tabs[0].presentationMode == .split)
    #expect(model.tabs[0].diffSession == nil)

    model.toggleDocumentDiff(mode: .gitHead, tabID: tabID)
    #expect(model.tabs[0].markdownEditSession?.mode == .markdown)
    #expect(model.tabs[0].presentationMode == .diff(.gitHead))
    #expect(model.tabs[0].diffSession?.mode == .gitHead)
    model.toggleDocumentDiff(mode: .gitHead, tabID: tabID)
    #expect(model.tabs[0].diffSession == nil)
}

@Test("discards Git changes and leaves Markdown in source mode")
@MainActor
func discardsGitChangesAndLeavesMarkdownInSourceMode() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-git-discard-\(UUID().uuidString)", isDirectory: true)
    let fileURL = root.appendingPathComponent("notes.md")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "# On disk".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let restorer = GitHeadDocumentRestorer(
        runner: RecordingGitProcessRunner(repositoryPath: root.path)
    )
    let model = AppModel(documentDiffCoordinator: DocumentDiffCoordinator(gitRestorer: restorer))
    let tabID = fileURL.path
    model.tabs = [
        DocumentTab(
            id: tabID,
            url: fileURL,
            kind: .markdown,
            markdownSource: "# On disk",
            markdownEditSession: MarkdownEditSession(
                baseSource: "# On disk",
                currentSource: "# Draft"
            ),
            diffSession: DocumentDiffSession(
                mode: .gitHead,
                baseline: DocumentDiffBaseline(label: "HEAD", source: "# Head")
            )
        )
    ]

    model.requestDiscardGitChanges(tabID: tabID)
    #expect(model.showingGitDiscardConfirmation)
    #expect(model.pendingGitDiscardTitle == "notes")

    model.confirmDiscardGitChanges()
    for _ in 0..<10 {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    let updated = model.tabs[0]
    #expect(!model.showingGitDiscardConfirmation)
    #expect(updated.diffSession == nil)
    #expect(updated.presentationMode == .source)
    #expect(updated.markdownEditSession?.isEditing == true)
    #expect(updated.markdownEditSession?.baseSource == "from head")
    #expect(updated.markdownEditSession?.currentSource == "from head")
    #expect(updated.markdownEditSession?.undoSources.isEmpty == true)
}

@Test("discards Git changes and leaves JSON in source mode")
@MainActor
func discardsGitChangesAndLeavesJSONInSourceMode() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bp-viewer-git-discard-json-\(UUID().uuidString)", isDirectory: true)
    let fileURL = root.appendingPathComponent("data.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "{\"disk\":true}".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let restorer = GitHeadDocumentRestorer(
        runner: RecordingGitProcessRunner(
            headResult: ProcessResult(
                status: .success,
                exitCode: 0,
                standardOutput: "{\"head\":true}",
                standardError: ""
            ),
            repositoryPath: root.path
        )
    )
    let model = AppModel(documentDiffCoordinator: DocumentDiffCoordinator(gitRestorer: restorer))
    let tabID = fileURL.path
    model.tabs = [
        DocumentTab(
            id: tabID,
            url: fileURL,
            kind: .json,
            jsonSource: "{\"disk\":true}",
            jsonEditSession: MarkdownEditSession(
                baseSource: "{\"disk\":true}",
                currentSource: "{\"draft\":true}"
            ),
            diffSession: DocumentDiffSession(
                mode: .gitHead,
                baseline: DocumentDiffBaseline(label: "HEAD", source: "{\"head\":true}")
            )
        )
    ]

    model.requestDiscardGitChanges(tabID: tabID)
    model.confirmDiscardGitChanges()
    for _ in 0..<10 {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    let updated = model.tabs[0]
    #expect(updated.diffSession == nil)
    #expect(updated.presentationMode == .source)
    #expect(updated.jsonEditSession?.isEditing == true)
    #expect(updated.jsonEditSession?.baseSource == "{\"head\":true}")
    #expect(updated.jsonEditSession?.currentSource == "{\"head\":true}")
    #expect(updated.jsonEditSession?.saveState == .saved)
}

private struct StubGitProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) throws -> ProcessResult {
        if request.arguments.contains("rev-parse") {
            return ProcessResult(
                status: .success,
                exitCode: 0,
                standardOutput: "/tmp/project\n",
                standardError: ""
            )
        }
        return ProcessResult(
            status: .success,
            exitCode: 0,
            standardOutput: "from head",
            standardError: ""
        )
    }
}

private struct RecordingGitProcessRunner: ProcessRunning {
    let headResult: ProcessResult
    let repositoryPath: String
    private let storage: RequestStorage

    init(
        headResult: ProcessResult = ProcessResult(
            status: .success,
            exitCode: 0,
            standardOutput: "from head",
            standardError: ""
        ),
        repositoryPath: String = "/tmp/project"
    ) {
        self.headResult = headResult
        self.repositoryPath = repositoryPath
        self.storage = RequestStorage()
    }

    var requests: [ProcessRequest] {
        storage.requests
    }

    func run(_ request: ProcessRequest) throws -> ProcessResult {
        storage.requests.append(request)
        if request.arguments.contains("rev-parse") {
            return ProcessResult(
                status: .success,
                exitCode: 0,
                standardOutput: "\(repositoryPath)\n",
                standardError: ""
            )
        }
        if request.arguments.first == "show" {
            return headResult
        }
        return ProcessResult(
            status: .success,
            exitCode: 0,
            standardOutput: "",
            standardError: ""
        )
    }
}

private final class RequestStorage: @unchecked Sendable {
    var requests: [ProcessRequest] = []
}
