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
        try write("plain", to: root.appendingPathComponent("zeta.txt"))
        try write("hidden", to: root.appendingPathComponent(".hidden.md"))
        try write("# Inside", to: docs.appendingPathComponent("inside.md"))
        try write("\\documentclass{article}", to: nested.appendingPathComponent("deep.tex"))
    }

    private func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func runScannerContracts(root: URL) {
        let scanner = FileSystemScanner()
        let topLevel = scanner.scanTopLevel(root: root)

        expect(topLevel.map(\.title) == ["docs", "empty", "README.md", "zeta.txt"], "top-level order and hidden-file omission")
        expect(topLevel.first?.isDirectory == true, "directories precede files")
        expect(topLevel.first(where: { $0.title == "docs" })?.childrenLoaded == false, "top-level scan is lazy")
        expect(topLevel.first(where: { $0.title == "empty" })?.children.isEmpty == true, "empty directory has no eager children")

        let compatible = scanner.filter(topLevel, compatibleOnly: true, query: "")
        expect(compatible.map(\.title) == ["docs", "empty", "README.md"], "compatible filter keeps unknown lazy directories")

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

        let allFiles = scanner.filter(topLevel, compatibleOnly: false, query: "")
        expect(allFiles.map(\.title) == ["docs", "empty", "README.md", "zeta.txt"], "unfiltered tree keeps all visible entries")
        expect(scanner.scan(root: root.appendingPathComponent("missing")) .isEmpty, "missing root is non-fatal")
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
