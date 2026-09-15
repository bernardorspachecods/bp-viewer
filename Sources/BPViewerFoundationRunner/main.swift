import BPViewerCore
import Foundation

@main
struct BPViewerFoundationRunner {
    static func main() throws {
        var runner = Runner()
        try runner.run()
    }
}

private struct Runner {
    private var passed = 0
    private var failed = 0

    mutating func run() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-viewer-foundation-" + UUID().uuidString)
        try makeFixture(at: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        runScannerContracts(root: fixture)
        runTabContracts(root: fixture)
        runPathCopyContracts(root: fixture)
        runMarkdownEditingContracts()

        print("Foundation contracts: " + String(passed) + " passed, " + String(failed) + " failed")
        if failed > 0 {
            exit(1)
        }
    }

    private func makeFixture(at root: URL) throws {
        let fileManager = FileManager.default
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let nested = docs.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("empty", isDirectory: true),
            withIntermediateDirectories: true
        )

        try write("# README", to: root.appendingPathComponent("README.md"))
        try write("{\"name\":\"bp-viewer\"}", to: root.appendingPathComponent("config.json"))
        try write("%PDF-1.7", to: root.appendingPathComponent("sample.pdf"))
        try write("plain", to: root.appendingPathComponent("zeta.txt"))
        try write("hidden", to: root.appendingPathComponent(".hidden.md"))
        try write("# Inside", to: docs.appendingPathComponent("inside.md"))
        try write("\\documentclass{article}", to: nested.appendingPathComponent("deep.tex"))
        try write("docx fixture", to: root.appendingPathComponent("report.docx"))
    }

    private func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func runScannerContracts(root: URL) {
        let scanner = FileSystemScanner()
        let topLevel = scanner.scanTopLevel(root: root)

        expect(topLevel.map(\.title) == ["docs", "empty", "config.json", "README.md", "report.docx", "sample.pdf", "zeta.txt"], "top-level order and hidden-file omission")
        expect(topLevel.first?.isDirectory == true, "directories precede files")
        expect(topLevel.first(where: { $0.title == "docs" })?.childrenLoaded == false, "top-level scan is lazy")
        expect(topLevel.first(where: { $0.title == "empty" })?.children.isEmpty == true, "empty directory has no eager children")

        let compatible = scanner.filter(topLevel, compatibleOnly: true, query: "")
        expect(compatible.map(\.title) == ["docs", "empty", "config.json", "README.md", "report.docx", "sample.pdf"], "compatible filter keeps unknown lazy directories")

        let docsURL = root.appendingPathComponent("docs", isDirectory: true)
        let docsChildren = scanner.scanChildren(of: docsURL, root: root)
        expect(docsChildren.map(\.title) == ["nested", "inside.md"], "lazy child scan order")
        expect(docsChildren.first?.childrenLoaded == false, "nested directory remains lazy after child scan")

        let complete = scanner.scan(root: root)
        let docs = complete.first(where: { $0.title == "docs" })
        expect(docs?.childrenLoaded == true, "full scan loads descendants")
        expect(docs?.children.first(where: { $0.title == "nested" })?.childrenLoaded == true, "full scan loads nested descendants")

        let search = scanner.filter(complete, compatibleOnly: true, query: "  DEEP  ")
        expect(search.first?.title == "docs", "search is case-insensitive and trims whitespace")
        expect(search.first?.children.first?.title == "nested", "search preserves matching ancestor chain")
        expect(search.first?.children.first?.children.first?.title == "deep.tex", "search reaches nested compatible file")

        let topLevelSearch = scanner.filterTopLevel(complete, compatibleOnly: true, query: "  DOCS  ")
        expect(topLevelSearch.map(\.title) == ["docs"], "top-level search matches only root entries")
        expect(topLevelSearch.first?.children.isEmpty == true, "top-level search does not return descendants")
        expect(scanner.filterTopLevel(complete, compatibleOnly: true, query: "DEEP").isEmpty, "top-level search ignores nested entries")

        let allFiles = scanner.filter(topLevel, compatibleOnly: false, query: "")
        expect(allFiles.map(\.title) == ["docs", "empty", "config.json", "README.md", "report.docx", "sample.pdf", "zeta.txt"], "unfiltered tree keeps all visible entries")
        expect(scanner.scan(root: root.appendingPathComponent("missing")) .isEmpty, "missing root is non-fatal")
        expect(DocumentKind(url: root.appendingPathComponent("sample.PDF")) == .pdf, "PDF files are recognized case-insensitively")

        do {
            let formatted = try JSONPreviewAdapter().format(source: "{\"z\": 1, \"a\": [true, null]}")
            expect(formatted == "{\n  \"z\": 1,\n  \"a\": [\n    true,\n    null\n  ]\n}", "JSON is validated and formatted")
        } catch {
            expect(false, "JSON is validated and formatted")
        }

        do {
            _ = try JSONPreviewAdapter().format(source: "{\"missing\": }")
            expect(false, "invalid JSON is rejected for editing")
        } catch is JSONPreviewError {
            expect(true, "invalid JSON is rejected for editing")
        } catch {
            expect(false, "invalid JSON is rejected for editing")
        }

        do {
            _ = try JSONPreviewAdapter().format(source: "{\"value\": \"texto”\n}")
            expect(false, "JSON errors report line and character")
        } catch let error as JSONPreviewError {
            expect(
                error.localizedDescription.contains("linha")
                    && error.localizedDescription.contains("carácter"),
                "JSON errors report line and character"
            )
        } catch {
            expect(false, "JSON errors report line and character")
        }

        let syntaxTokens = JSONSyntaxHighlighter().tokenize(
            "{\"name\": \"bp\", \"count\": 2, \"active\": true, \"missing\": null}"
        )
        let syntaxKinds = Set(syntaxTokens.map(\.kind))
        expect(
            syntaxKinds.isSuperset(of: [.punctuation, .key, .string, .number, .boolean, .null]),
            "JSON syntax highlighting tokenizes JSON values"
        )
        let invalidSyntaxTokens = JSONSyntaxHighlighter().tokenize("{\"value\": \"bad\n\"}")
        expect(
            invalidSyntaxTokens.contains(where: { $0.kind == .invalid }),
            "JSON syntax highlighting marks invalid characters"
        )

        do {
            let formatted = try JSONPreviewAdapter().format(
                source: "{\"z\":0,\"a\":1,\"middle\":2,\"nested\":{\"last\":3,\"first\":4}}"
            )
            expect(
                formatted == "{\n  \"z\": 0,\n  \"a\": 1,\n  \"middle\": 2,\n  \"nested\": {\n    \"last\": 3,\n    \"first\": 4\n  }\n}",
                "JSON preview preserves source key order"
            )
        } catch {
            expect(false, "JSON preview preserves source key order")
        }

        do {
            _ = try JSONPreviewAdapter().format(source: """
            {
              "schema_version": "1.1.0",
              "status": "in_progress",
              "title": "Discovering and Forecasting Emerging AI Capabilities from Patent Data: A Reproducible Data Science Pipeline",
              "supervisor": "Bruno Damásio",
              "deadline": null,
              "created_at": "2026-04-17",
              "last_updated": "2026-09-13"
            }
            """)
            expect(true, "valid JSON with accented text can be corrected and saved")
        } catch {
            expect(false, "valid JSON with accented text can be corrected and saved")
        }

        let originalJSON = "{\"title\":\"A\",\"value\":1}"
        let formattedJSON = (try? JSONPreviewAdapter().format(source: originalJSON)) ?? ""
        if let valueRange = formattedJSON.range(of: "\"value\"") {
            let formattedOffset = formattedJSON.utf8.distance(
                from: formattedJSON.utf8.startIndex,
                to: valueRange.lowerBound.samePosition(in: formattedJSON.utf8)!
            )
            let originalOffset = JSONPreviewAdapter().sourceOffset(
                forFormattedUTF8Offset: formattedOffset,
                source: originalJSON,
                formattedSource: formattedJSON
            )
            let expectedOffset = originalJSON.utf8.distance(
                from: originalJSON.utf8.startIndex,
                to: originalJSON.range(of: "\"value\"")!.lowerBound.samePosition(in: originalJSON.utf8)!
            )
            expect(originalOffset == expectedOffset, "JSON preview clicks map to raw source offsets")
        } else {
            expect(false, "JSON preview clicks map to raw source offsets")
        }
    }

    private mutating func runTabContracts(root: URL) {
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        let third = root.appendingPathComponent("third.tex")
        let missing = root.appendingPathComponent("missing.md")

        var state = TabSessionState()
        expect(state.open(first), "opening a new tab inserts it")
        expect(state.open(second), "opening a second tab inserts it")
        expect(!state.open(first), "opening an existing tab does not duplicate it")
        expect(state.paths == [first.standardizedFileURL, second.standardizedFileURL], "tab order remains stable after duplicate open")
        expect(state.activePath == first.standardizedFileURL, "duplicate open focuses existing tab")
        expect(state.select(second), "selecting an existing tab succeeds")
        expect(!state.select(missing), "selecting an unknown tab is ignored")
        expect(state.select(first), "selecting the first tab succeeds")
        expect(state.selectNext(), "control-tab advances to the next tab")
        expect(state.activePath == second.standardizedFileURL, "control-tab selects the next tab")
        expect(state.selectNext(), "control-tab wraps after the last tab")
        expect(state.activePath == first.standardizedFileURL, "control-tab cycles to the first tab")
        expect(state.close(second), "closing an existing tab succeeds")
        expect(state.activePath == first.standardizedFileURL, "closing active tab selects adjacent remaining tab")

        _ = state.open(second)
        _ = state.open(third)
        _ = state.select(first)
        expect(state.closeToRight(of: first), "closing tabs to the right succeeds")
        expect(state.paths == [first.standardizedFileURL], "closing right removes only later tabs")
        expect(state.activePath == first.standardizedFileURL, "closing right preserves active tab when retained")

        let restored = TabSessionState.restored(
            paths: [first.path, first.path, missing.path, second.path],
            activePath: missing.path,
            fileExists: { $0 == first || $0 == second }
        )
        expect(restored.paths == [first.standardizedFileURL, second.standardizedFileURL], "restore removes missing and duplicate tabs")
        expect(restored.activePath == first.standardizedFileURL, "restore falls back to first available tab")
        expect(restored.persistedPaths == [first.standardizedFileURL.path, second.standardizedFileURL.path], "persistence emits stable paths")

        var keepState = TabSessionState(paths: [first, second, third], activePath: third)
        expect(keepState.closeOthers(keeping: second), "close others keeps requested tab")
        expect(keepState.paths == [second.standardizedFileURL] && keepState.activePath == second.standardizedFileURL, "close others selects kept tab")

        var reorderState = TabSessionState(paths: [first, second, third], activePath: second)
        expect(reorderState.move(third, before: first), "moving a tab before another tab succeeds")
        expect(reorderState.paths == [third.standardizedFileURL, first.standardizedFileURL, second.standardizedFileURL], "tab order changes after drag and drop")
        expect(reorderState.activePath == second.standardizedFileURL, "reordering keeps the active tab")
        expect(reorderState.moveToEnd(third), "moving a tab to the end succeeds")
        expect(reorderState.paths == [first.standardizedFileURL, second.standardizedFileURL, third.standardizedFileURL], "tab can be dropped after the last tab")
        expect(reorderState.reorder([second, third, first]), "accepting a native tab order succeeds")
        expect(reorderState.paths == [second.standardizedFileURL, third.standardizedFileURL, first.standardizedFileURL], "native tab order is applied")
        expect(!reorderState.reorder([second, second, first]), "invalid native tab order is ignored")
    }

    private mutating func runPathCopyContracts(root: URL) {
        let path = root.appendingPathComponent("chapters/../working.md")
        expect(
            FilePathCopy.string(for: path) == root.appendingPathComponent("working.md").path,
            "copy path is normalized and absolute"
        )
    }

    private mutating func runMarkdownEditingContracts() {
        expect(MarkdownEditingMode.allCases == [.markdown, .split], "Markdown editing exposes source and split modes")
        expect(MarkdownEditingMode(rawValue: "visual") == nil, "visual Markdown editing mode is no longer supported")

        let positioned = MarkdownBlockDocument(source: "# Title\n\nBody **strong**.")
        expect(positioned.blocks[0].sourceOffset(forRenderedTextOffset: 0) == 2, "heading cursor skips Markdown marker")
        expect(positioned.blocks[1].sourceOffset(forRenderedTextOffset: 5) == 7, "inline formatting cursor skips Markdown markers")

        let source = """
        # Title

        First paragraph.
        It keeps its second line.

        - One
        - Two

        ## Final heading
        """
        let document = MarkdownBlockDocument(source: source)

        expect(document.blocks.map(\.kind) == [.heading, .paragraph, .unorderedList, .heading], "Markdown blocks preserve top-level structure")
        expect(document.blocks[1].source == "First paragraph.\nIt keeps its second line.", "paragraph block keeps its exact source")
        let formatted = MarkdownBlockDocument(source: "A **formatted** paragraph")
        expect(formatted.blocks[0].supportsVisualEditing, "supported inline Markdown remains visually editable")

        let updated = document.replacingBlock(id: document.blocks[1].id, withSource: "Edited paragraph.")
        expect(updated.source.contains("# Title\n\nEdited paragraph.\n\n- One"), "editing a block preserves surrounding Markdown")

        let visualDocument = document.replacingVisualEntries([
            MarkdownVisualEntry(id: document.blocks[1].id, text: "Visual paragraph."),
            MarkdownVisualEntry(id: document.blocks[2].id, text: "First visual\nSecond visual")
        ])
        expect(
            visualDocument.source.contains("Visual paragraph.\n\n- First visual\n- Second visual"),
            "document visual editing serializes supported regions without exposing blocks"
        )

        let structural = MarkdownBlockDocument(source: "Before\n\n> Existing quote\n> continues\n\n---")
        expect(
            structural.blocks.map(\.kind) == [.paragraph, .blockquote, .thematicBreak],
            "blockquote and separator regions remain part of the document model"
        )
        let quoted = MarkdownBlockDocument(source: "Plain text").replacingVisualEntries([
            MarkdownVisualEntry(id: "markdown-block-1", text: "Quoted text", kind: .blockquote)
        ])
        expect(quoted.source == "> Quoted text", "visual quote transformation preserves Markdown syntax")
        let withSeparator = MarkdownBlockDocument(source: "Plain text").insertingVisualBlock(
            MarkdownVisualInsertion(afterID: "markdown-block-1", kind: .thematicBreak)
        )
        expect(withSeparator.source == "Plain text\n\n---", "visual separator insertion preserves document order")

        let editedHeading = updated.replacingBlock(id: updated.blocks[3].id, withVisualText: "Closing heading")
        expect(editedHeading.source.contains("## Closing heading"), "visual heading edits preserve heading syntax")

        let base = MarkdownBlockDocument(source: "# Title\n\nFirst\n\nSecond")
        let local = base.replacingBlock(id: base.blocks[1].id, withVisualText: "Local first")
        let external = base.replacingBlock(id: base.blocks[2].id, withVisualText: "External second")
        let merged = MarkdownThreeWayMerge.resolve(
            base: base.source,
            local: local.source,
            external: external.source
        )
        expect(
            merged == .merged("# Title\n\nLocal first\n\nExternal second"),
            "non-overlapping Markdown edits merge automatically"
        )

        let conflictingExternal = base.replacingBlock(id: base.blocks[1].id, withVisualText: "External first")
        let conflict = MarkdownThreeWayMerge.resolve(
            base: base.source,
            local: local.source,
            external: conflictingExternal.source
        )
        expect(conflict.isConflict, "overlapping Markdown edits become an explicit conflict")

        let rendered = try? SwiftMarkdownAdapter().render(
            source: "# Title\n\nParagraph\n\n- One\n- Two",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(rendered?.html.contains("data-bp-block-id=\"markdown-block-2\"") == true, "paragraph HTML exposes its block ID")
        expect(rendered?.html.contains("data-bp-block-id=\"markdown-block-3\"") == true, "list HTML exposes its block ID")
        expect(rendered?.html.contains("data-bp-editable=\"true\"") == true, "supported Markdown regions are visually editable")

        let linked = try? SwiftMarkdownAdapter().render(
            source: "A [link](notes.md) and **strong** text.",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(linked?.html.contains("data-bp-editable=\"true\"") == true, "inline links and formatting stay visually editable")
        expect(linked?.html.contains("data-bp-markdown-href=\"notes.md\"") == true, "rendered links preserve their Markdown destination")

        let tasks = MarkdownBlockDocument(source: "- [ ] Draft\n- [x] Done")
        let taskEdited = tasks.replacingVisualEntries([
            MarkdownVisualEntry(
                id: tasks.blocks[0].id,
                text: "[x] Draft\n[ ] Done",
                kind: .unorderedList
            )
        ])
        expect(taskEdited.source == "- [x] Draft\n- [ ] Done", "visual task list edits preserve checkbox markers")

        let renderedTasks = try? SwiftMarkdownAdapter().render(
            source: "- [ ] Draft\n- [x] Done",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedTasks?.html.contains("data-bp-task-checkbox=\"true\"") == true, "task list checkboxes expose an editing hook")

        let codeSource = "Before\n\n```swift\nlet value = 1\n```\n\nAfter"
        let codeDocument = MarkdownBlockDocument(source: codeSource)
        expect(codeDocument.blocks.map(\.kind) == [.paragraph, .codeBlock, .paragraph], "fenced code blocks remain distinct document regions")
        expect(codeDocument.blocks[1].visualText == "let value = 1", "code block visual text omits its fence")
        let editedCode = codeDocument.replacingVisualEntries([
            MarkdownVisualEntry(id: codeDocument.blocks[1].id, text: "let value = 2", kind: .codeBlock)
        ])
        expect(editedCode.source.contains("```swift\nlet value = 2\n```"), "visual code edits preserve fence and language")
        let renderedCode = try? SwiftMarkdownAdapter().render(
            source: codeSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedCode?.html.contains("data-bp-editable=\"true\"") == true, "fenced code blocks expose an editing hook")

        let tableSource = "| Name | Value |\n| --- | --- |\n| One | 1 |\n| Two | 2 |"
        let tableDocument = MarkdownBlockDocument(source: tableSource)
        expect(tableDocument.blocks.map(\.kind) == [.table], "Markdown tables remain distinct document regions")
        let editedTable = tableDocument.replacingVisualEntries([
            MarkdownVisualEntry(
                id: tableDocument.blocks[0].id,
                text: "| Name | Value |\n| --- | --- |\n| One | 10 |\n| Two | 2 |",
                kind: .table
            )
        ])
        expect(editedTable.source.contains("| One | 10 |"), "visual table edits preserve Markdown rows")
        let renderedTable = try? SwiftMarkdownAdapter().render(
            source: tableSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedTable?.html.contains("<table data-bp-block-id=\"markdown-block-1\"") == true, "tables expose an editing hook")

        let imageSource = "![Old label](images/figure.png \"Old title\")"
        let imageDocument = MarkdownBlockDocument(source: imageSource)
        let imageRegion = imageDocument.specialRegions.first
        expect(imageRegion?.kind == .image, "images expose specialized source regions")
        let editedImage = imageRegion.map {
            imageDocument.replacingSpecialEdits([
                MarkdownSpecialEdit(
                    id: $0.id,
                    kind: .image,
                    replacement: "![New label](images/figure.png \"New title\")"
                )
            ])
        }
        expect(editedImage?.source == "![New label](images/figure.png \"New title\")", "visual image edits preserve Markdown image syntax")
        let renderedImage = try? SwiftMarkdownAdapter().render(
            source: imageSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedImage?.html.contains("data-bp-special-kind=\"image\"") == true, "images expose a specialized editing hook")

        let mathSource = "$$\na + b\n$$"
        let mathDocument = MarkdownBlockDocument(source: mathSource)
        expect(mathDocument.specialRegions.first?.kind == .math, "block formulas expose specialized source regions")
        let editedMath = mathDocument.specialRegions.first.map {
            mathDocument.replacingSpecialEdits([
                MarkdownSpecialEdit(id: $0.id, kind: .math, replacement: "$$\na - b\n$$")
            ])
        }
        expect(editedMath?.source == "$$\na - b\n$$", "visual formula edits preserve delimiters")
        let renderedMath = try? SwiftMarkdownAdapter().render(
            source: mathSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedMath?.html.contains("data-bp-special-kind=\"math\"") == true, "block formulas expose a specialized editing hook")
        let inlineMath = try? SwiftMarkdownAdapter().render(
            source: "Inline $a+b$ formula",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(
            inlineMath?.html.contains("class=\"math-inline bp-special-placeholder\"") == true
                && inlineMath?.html.contains("data-bp-special-kind=\"math\"") == true,
            "inline formulas expose a specialized editing hook"
        )

        let htmlSource = "<div class=\"note\">Raw HTML</div>"
        let htmlDocument = MarkdownBlockDocument(source: htmlSource)
        expect(htmlDocument.specialRegions.first?.kind == .html, "raw HTML exposes specialized source regions")
        let renderedHTML = try? SwiftMarkdownAdapter().render(
            source: htmlSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedHTML?.html.contains("data-bp-special-kind=\"html\"") == true, "raw HTML exposes a specialized editing hook")
        let inlineHTML = try? SwiftMarkdownAdapter().render(
            source: "Text <span>raw</span>",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(inlineHTML?.html.contains("data-bp-special-kind=\"html\"") == true, "inline HTML exposes a specialized editing hook")

        let frontMatterSource = "---\ntitle: Draft\n---\n\n# Body"
        let frontMatterDocument = MarkdownBlockDocument(source: frontMatterSource)
        expect(frontMatterDocument.blocks.first?.kind == .frontMatter, "front matter remains a distinct document region")
        expect(frontMatterDocument.specialRegions.first?.kind == .frontMatter, "front matter exposes specialized source regions")
        let renderedFrontMatter = try? SwiftMarkdownAdapter().render(
            source: frontMatterSource,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(renderedFrontMatter?.html.contains("data-bp-special-kind=\"frontMatter\"") == true, "front matter exposes a specialized editing hook")

        let protected = try? SwiftMarkdownAdapter().render(
            source: "![image](photo.png)",
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )
        expect(protected?.html.contains("data-bp-editable=\"false\"") == true, "unsupported Markdown regions remain protected")
    }

    private mutating func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            passed += 1
            print("PASS " + name)
        } else {
            failed += 1
            print("FAIL " + name)
        }
    }
}
