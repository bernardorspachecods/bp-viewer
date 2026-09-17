import Foundation

public enum DocumentDiffMode: String, CaseIterable, Hashable, Sendable {
    case savedOnDisk
    case gitHead

    public var label: String {
        switch self {
        case .savedOnDisk: "Disk Diff"
        case .gitHead: "Git Diff"
        }
    }
}

public struct DocumentDiffBaseline: Hashable, Sendable {
    public let label: String
    public let source: String

    public init(label: String, source: String) {
        self.label = label
        self.source = source
    }
}

public enum DocumentDiffBaselineResolution: Hashable, Sendable {
    case available(DocumentDiffBaseline)
    case unavailable(String)
}

public enum GitDocumentRestoreResolution: Hashable, Sendable {
    case restored(source: String)
    case unavailable(String)
    case failed(String)
}

public struct DocumentDiffSession: Hashable, Sendable {
    public var mode: DocumentDiffMode
    public var baseline: DocumentDiffBaseline?
    public var unavailableMessage: String?
    public var returnMode: DocumentPresentationMode

    public init(
        mode: DocumentDiffMode,
        baseline: DocumentDiffBaseline? = nil,
        unavailableMessage: String? = nil,
        returnMode: DocumentPresentationMode = .source
    ) {
        self.mode = mode
        self.baseline = baseline
        self.unavailableMessage = unavailableMessage
        self.returnMode = returnMode
    }
}

public protocol DocumentDiffBaselineProviding: Sendable {
    func baseline(for url: URL) -> DocumentDiffBaselineResolution
}

public struct DiskDocumentDiffBaselineProvider: DocumentDiffBaselineProviding {
    public init() {}

    public func baseline(for url: URL) -> DocumentDiffBaselineResolution {
        do {
            return .available(
                DocumentDiffBaseline(
                    label: "Saved on Disk",
                    source: try String(contentsOf: url, encoding: .utf8)
                )
            )
        } catch {
            return .unavailable("Unable to read the version saved on disk.")
        }
    }
}

private struct GitDocumentLocation: Sendable {
    let repositoryURL: URL
    let relativePath: String
}

private enum GitDocumentLocationResolution {
    case available(GitDocumentLocation)
    case unavailable(String)
}

private struct GitDocumentLocator: Sendable {
    let runner: any ProcessRunning
    let gitExecutable: URL

    func locate(_ url: URL) -> GitDocumentLocationResolution {
        let directory = url.deletingLastPathComponent()
        let repositoryResult: ProcessResult
        do {
            repositoryResult = try runner.run(
                ProcessRequest(
                    executable: gitExecutable,
                    arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"],
                    workingDirectory: directory,
                    timeout: 10,
                    maxOutputBytes: 32_000
                )
            )
        } catch {
            return .unavailable("Git is not available for this document.")
        }

        guard repositoryResult.status == .success,
              let repositoryPath = nonEmptyPath(from: repositoryResult.standardOutput) else {
            return .unavailable("This file is not inside a Git repository.")
        }

        let repositoryURL = URL(fileURLWithPath: repositoryPath).standardizedFileURL
        let documentURL = url.standardizedFileURL
        let repositoryPrefix = repositoryURL.path.hasSuffix("/")
            ? repositoryURL.path
            : repositoryURL.path + "/"
        guard documentURL.path.hasPrefix(repositoryPrefix) else {
            return .unavailable("This file is outside the Git repository.")
        }

        let relativePath = String(documentURL.path.dropFirst(repositoryPrefix.count))
            .replacingOccurrences(of: "\\", with: "/")
        return .available(GitDocumentLocation(
            repositoryURL: repositoryURL,
            relativePath: relativePath
        ))
    }

    private func nonEmptyPath(from output: String) -> String? {
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

public struct GitHeadDocumentDiffBaselineProvider: DocumentDiffBaselineProviding {
    private let runner: any ProcessRunning
    private let gitExecutable: URL

    public init(
        runner: any ProcessRunning = LiveProcessRunner(),
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.runner = runner
        self.gitExecutable = gitExecutable
    }

    public func baseline(for url: URL) -> DocumentDiffBaselineResolution {
        let locator = GitDocumentLocator(runner: runner, gitExecutable: gitExecutable)
        let location: GitDocumentLocation
        switch locator.locate(url) {
        case let .available(value):
            location = value
        case let .unavailable(message):
            return .unavailable(message)
        }

        let headResult: ProcessResult
        do {
            headResult = try runner.run(
                ProcessRequest(
                    executable: gitExecutable,
                    arguments: ["show", "HEAD:\(location.relativePath)"],
                    workingDirectory: location.repositoryURL,
                    timeout: 10,
                    maxOutputBytes: 8_000_000
                )
            )
        } catch {
            return .unavailable("Git could not read this file from HEAD.")
        }

        guard headResult.status == .success else {
            return .unavailable("This file has no version in the latest Git commit.")
        }
        return .available(
            DocumentDiffBaseline(
                label: "HEAD",
                source: headResult.standardOutput
            )
        )
    }
}

public struct GitHeadDocumentRestorer: Sendable {
    private let runner: any ProcessRunning
    private let gitExecutable: URL

    public init(
        runner: any ProcessRunning = LiveProcessRunner(),
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.runner = runner
        self.gitExecutable = gitExecutable
    }

    public func restoreToHead(for url: URL) -> GitDocumentRestoreResolution {
        let locator = GitDocumentLocator(runner: runner, gitExecutable: gitExecutable)
        let location: GitDocumentLocation
        switch locator.locate(url) {
        case let .available(value):
            location = value
        case let .unavailable(message):
            return .unavailable(message)
        }

        let headResult: ProcessResult
        do {
            headResult = try runner.run(
                ProcessRequest(
                    executable: gitExecutable,
                    arguments: ["show", "HEAD:\(location.relativePath)"],
                    workingDirectory: location.repositoryURL,
                    timeout: 10,
                    maxOutputBytes: 8_000_000
                )
            )
        } catch {
            return .unavailable("Git could not read this file from HEAD.")
        }

        guard headResult.status == .success else {
            return .unavailable("This file has no version in the latest Git commit.")
        }

        let restoreResult: ProcessResult
        do {
            restoreResult = try runner.run(
                ProcessRequest(
                    executable: gitExecutable,
                    arguments: [
                        "restore",
                        "--source=HEAD",
                        "--staged",
                        "--worktree",
                        "--",
                        location.relativePath
                    ],
                    workingDirectory: location.repositoryURL,
                    timeout: 10,
                    maxOutputBytes: 32_000
                )
            )
        } catch {
            return .failed("Git could not restore this file to HEAD.")
        }

        guard restoreResult.status == .success else {
            let detail = restoreResult.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(
                detail.isEmpty
                    ? "Git could not restore this file to HEAD."
                    : "Git could not restore this file to HEAD.\n\(detail)"
            )
        }
        return .restored(source: headResult.standardOutput)
    }
}

public enum DocumentDiffCellKind: String, Hashable, Sendable {
    case unchanged
    case added
    case removed
}

public struct DocumentDiffCell: Hashable, Sendable {
    public let lineNumber: Int
    public let text: String
    public let kind: DocumentDiffCellKind

    public init(lineNumber: Int, text: String, kind: DocumentDiffCellKind) {
        self.lineNumber = lineNumber
        self.text = text
        self.kind = kind
    }
}

public struct DocumentDiffRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let left: DocumentDiffCell?
    public let right: DocumentDiffCell?

    public init(id: Int, left: DocumentDiffCell?, right: DocumentDiffCell?) {
        self.id = id
        self.left = left
        self.right = right
    }
}

public struct DocumentDiff: Hashable, Sendable {
    public let rows: [DocumentDiffRow]
    public let addedLineCount: Int
    public let removedLineCount: Int

    public init(rows: [DocumentDiffRow]) {
        self.rows = rows
        addedLineCount = rows.reduce(into: 0) { count, row in
            if row.right?.kind == .added { count += 1 }
        }
        removedLineCount = rows.reduce(into: 0) { count, row in
            if row.left?.kind == .removed { count += 1 }
        }
    }

    public var hasChanges: Bool {
        addedLineCount > 0 || removedLineCount > 0
    }

    public var rightLineKinds: [Int: DocumentDiffCellKind] {
        Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let cell = row.right else { return nil }
                return (cell.lineNumber, cell.kind)
            }
        )
    }
}

/// Produces a deterministic, line-oriented side-by-side diff. The engine is
/// deliberately unaware of document formats and of the source of either side.
public struct DocumentDiffEngine: Sendable {
    public init() {}

    public func compare(reference: String, edited: String) -> DocumentDiff {
        let referenceLines = lines(in: reference)
        let editedLines = lines(in: edited)
        let operations = coalescedChangeOperations(
            diffOperations(reference: referenceLines, edited: editedLines)
        )

        var referenceLineNumber = 1
        var editedLineNumber = 1
        var rows: [DocumentDiffRow] = []

        for (index, operation) in operations.enumerated() {
            switch operation {
            case let .equal(text):
                rows.append(
                    DocumentDiffRow(
                        id: index,
                        left: DocumentDiffCell(
                            lineNumber: referenceLineNumber,
                            text: text,
                            kind: .unchanged
                        ),
                        right: DocumentDiffCell(
                            lineNumber: editedLineNumber,
                            text: text,
                            kind: .unchanged
                        )
                    )
                )
                referenceLineNumber += 1
                editedLineNumber += 1
            case let .remove(text):
                rows.append(
                    DocumentDiffRow(
                        id: index,
                        left: DocumentDiffCell(
                            lineNumber: referenceLineNumber,
                            text: text,
                            kind: .removed
                        ),
                        right: nil
                    )
                )
                referenceLineNumber += 1
            case let .insert(text):
                rows.append(
                    DocumentDiffRow(
                        id: index,
                        left: nil,
                        right: DocumentDiffCell(
                            lineNumber: editedLineNumber,
                            text: text,
                            kind: .added
                        )
                    )
                )
                editedLineNumber += 1
            case let .replace(referenceText, editedText):
                rows.append(
                    DocumentDiffRow(
                        id: index,
                        left: DocumentDiffCell(
                            lineNumber: referenceLineNumber,
                            text: referenceText,
                            kind: .removed
                        ),
                        right: DocumentDiffCell(
                            lineNumber: editedLineNumber,
                            text: editedText,
                            kind: .added
                        )
                    )
                )
                referenceLineNumber += 1
                editedLineNumber += 1
            }
        }

        return DocumentDiff(rows: rows)
    }

    private enum Operation: Sendable {
        case equal(String)
        case remove(String)
        case insert(String)
        case replace(reference: String, edited: String)
    }

    private func coalescedChangeOperations(_ operations: [Operation]) -> [Operation] {
        var coalesced: [Operation] = []
        var index = 0

        while index < operations.count {
            guard case .remove = operations[index] else {
                coalesced.append(operations[index])
                index += 1
                continue
            }

            var removed: [String] = []
            while index < operations.count {
                guard case let .remove(text) = operations[index] else { break }
                removed.append(text)
                index += 1
            }

            var inserted: [String] = []
            while index < operations.count {
                guard case let .insert(text) = operations[index] else { break }
                inserted.append(text)
                index += 1
            }

            let replacementCount = min(removed.count, inserted.count)
            for replacementIndex in 0..<replacementCount {
                coalesced.append(
                    .replace(
                        reference: removed[replacementIndex],
                        edited: inserted[replacementIndex]
                    )
                )
            }
            if replacementCount < removed.count {
                coalesced.append(contentsOf: removed[replacementCount...].map(Operation.remove))
            }
            if replacementCount < inserted.count {
                coalesced.append(contentsOf: inserted[replacementCount...].map(Operation.insert))
            }
        }

        return coalesced
    }

    private func lines(in source: String) -> [String] {
        source.components(separatedBy: "\n")
    }

    private func diffOperations(reference: [String], edited: [String]) -> [Operation] {
        guard !reference.isEmpty || !edited.isEmpty else { return [] }

        let n = reference.count
        let m = edited.count
        var lcs = Array(repeating: 0, count: (n + 1) * (m + 1))
        func index(_ referenceIndex: Int, _ editedIndex: Int) -> Int {
            referenceIndex * (m + 1) + editedIndex
        }

        if n > 0 && m > 0 {
            for referenceIndex in stride(from: n - 1, through: 0, by: -1) {
                for editedIndex in stride(from: m - 1, through: 0, by: -1) {
                    lcs[index(referenceIndex, editedIndex)] = reference[referenceIndex] == edited[editedIndex]
                        ? lcs[index(referenceIndex + 1, editedIndex + 1)] + 1
                        : max(
                            lcs[index(referenceIndex + 1, editedIndex)],
                            lcs[index(referenceIndex, editedIndex + 1)]
                        )
                }
            }
        }

        var referenceIndex = 0
        var editedIndex = 0
        var operations: [Operation] = []
        while referenceIndex < n || editedIndex < m {
            if referenceIndex < n,
               editedIndex < m,
               reference[referenceIndex] == edited[editedIndex] {
                operations.append(.equal(reference[referenceIndex]))
                referenceIndex += 1
                editedIndex += 1
            } else if referenceIndex < n,
                      editedIndex == m || lcs[index(referenceIndex + 1, editedIndex)] >= lcs[index(referenceIndex, editedIndex + 1)] {
                operations.append(.remove(reference[referenceIndex]))
                referenceIndex += 1
            } else {
                operations.append(.insert(edited[editedIndex]))
                editedIndex += 1
            }
        }
        return operations
    }
}
