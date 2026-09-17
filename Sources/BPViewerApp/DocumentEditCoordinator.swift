import BPViewerCore
import Foundation

struct DocumentEditTransition {
    let session: MarkdownEditSession
    let source: String
    let markdownBlocks: [MarkdownEditableBlock]
    let jsonErrorMessage: String?
    let jsonCursorUTF8Offset: Int?
}

enum DocumentEditSaveOutcome: Sendable {
    case saved(source: String)
    case conflict(MarkdownConflict)
    case failed(message: String)
}

/// Encapsulates document-edit state transitions and file reconciliation. It
/// deliberately exchanges values instead of mutating AppModel's tabs.
@MainActor
final class DocumentEditCoordinator {
    init() {}

    func beginMarkdown(
        source: String,
        mode: MarkdownEditingMode = .markdown
    ) -> DocumentEditTransition {
        var session = MarkdownEditSession(baseSource: source, currentSource: source)
        session.mode = mode
        return transition(session: session, source: source)
    }

    func updateMarkdown(
        session: MarkdownEditSession,
        source: String
    ) -> DocumentEditTransition? {
        guard source != session.currentSource else { return nil }
        var updated = session
        updated.undoSources.append(updated.currentSource)
        updated.redoSources.removeAll()
        updated.currentSource = source
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: source)
    }

    func undoMarkdown(session: MarkdownEditSession) -> DocumentEditTransition? {
        guard let previous = session.undoSources.last else { return nil }
        var updated = session
        updated.undoSources.removeLast()
        updated.redoSources.append(updated.currentSource)
        updated.currentSource = previous
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: previous)
    }

    func redoMarkdown(session: MarkdownEditSession) -> DocumentEditTransition? {
        guard let next = session.redoSources.last else { return nil }
        var updated = session
        updated.redoSources.removeLast()
        updated.undoSources.append(updated.currentSource)
        updated.currentSource = next
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: next)
    }

    func beginLatex(source: String) -> DocumentEditTransition {
        transition(
            session: SourceEditSession(baseSource: source, currentSource: source),
            source: source,
            markdownBlocks: []
        )
    }

    func updateLatex(
        session: SourceEditSession,
        source: String
    ) -> DocumentEditTransition? {
        guard source != session.currentSource else { return nil }
        var updated = session
        updated.undoSources.append(updated.currentSource)
        updated.redoSources.removeAll()
        updated.currentSource = source
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: source, markdownBlocks: [])
    }

    func undoLatex(session: SourceEditSession) -> DocumentEditTransition? {
        guard let previous = session.undoSources.last else { return nil }
        var updated = session
        updated.undoSources.removeLast()
        updated.redoSources.append(updated.currentSource)
        updated.currentSource = previous
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: previous, markdownBlocks: [])
    }

    func redoLatex(session: SourceEditSession) -> DocumentEditTransition? {
        guard let next = session.redoSources.last else { return nil }
        var updated = session
        updated.redoSources.removeLast()
        updated.undoSources.append(updated.currentSource)
        updated.currentSource = next
        updated.saveState = .unsaved
        updated.conflict = nil
        return transition(session: updated, source: next, markdownBlocks: [])
    }

    func beginJSON(
        source: String,
        previewUTF8Offset: Int
    ) -> DocumentEditTransition {
        let session = MarkdownEditSession(baseSource: source, currentSource: source)
        return transition(
            session: session,
            source: source,
            jsonCursorUTF8Offset: min(max(previewUTF8Offset, 0), source.utf8.count)
        )
    }

    func updateJSON(
        session: MarkdownEditSession,
        source: String
    ) -> DocumentEditTransition? {
        guard source != session.currentSource else { return nil }
        var updated = session
        updated.undoSources.append(updated.currentSource)
        updated.redoSources.removeAll()
        updated.currentSource = source
        updated.saveState = .unsaved
        updated.conflict = nil

        do {
            _ = try JSONPreviewAdapter().format(source: source)
            return transition(session: updated, source: source)
        } catch {
            updated.saveState = .failed
            return transition(
                session: updated,
                source: source,
                jsonErrorMessage: error.localizedDescription
            )
        }
    }

    func undoJSON(session: MarkdownEditSession) -> DocumentEditTransition? {
        guard let previous = session.undoSources.last else { return nil }
        var updated = session
        updated.undoSources.removeLast()
        updated.redoSources.append(updated.currentSource)
        updated.currentSource = previous
        updated.saveState = .unsaved
        updated.conflict = nil
        return validateJSONTransition(session: updated, source: previous)
    }

    func redoJSON(session: MarkdownEditSession) -> DocumentEditTransition? {
        guard let next = session.redoSources.last else { return nil }
        var updated = session
        updated.redoSources.removeLast()
        updated.undoSources.append(updated.currentSource)
        updated.currentSource = next
        updated.saveState = .unsaved
        updated.conflict = nil
        return validateJSONTransition(session: updated, source: next)
    }

    func useExternal(
        session: MarkdownEditSession,
        externalSource: String
    ) -> DocumentEditTransition {
        var updated = session
        updated.baseSource = externalSource
        updated.currentSource = externalSource
        updated.undoSources.removeAll()
        updated.redoSources.removeAll()
        updated.saveState = .saved
        updated.conflict = nil
        updated.isEditing = false
        return transition(
            session: updated,
            source: externalSource,
            jsonErrorMessage: nil
        )
    }

    func saveMarkdown(
        url: URL,
        baseSource: String,
        localSource: String
    ) async -> DocumentEditSaveOutcome {
        do {
            let externalSource = try await readSource(at: url)
            switch MarkdownThreeWayMerge.resolve(
                base: baseSource,
                local: localSource,
                external: externalSource
            ) {
            case let .merged(mergedSource):
                try mergedSource.write(to: url, atomically: true, encoding: .utf8)
                return .saved(source: mergedSource)
            case let .conflict(_, local, external, blockIDs):
                return .conflict(MarkdownConflict(
                    localSource: local,
                    externalSource: external,
                    blockIDs: blockIDs
                ))
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func saveJSON(
        url: URL,
        baseSource: String,
        localSource: String
    ) async -> DocumentEditSaveOutcome {
        do {
            _ = try JSONPreviewAdapter().format(source: localSource)
            let externalSource = try await readSource(at: url)
            guard externalSource == baseSource else {
                return .conflict(MarkdownConflict(
                    localSource: localSource,
                    externalSource: externalSource,
                    blockIDs: []
                ))
            }
            try localSource.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: localSource)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func saveLatex(
        url: URL,
        baseSource: String,
        localSource: String
    ) async -> DocumentEditSaveOutcome {
        do {
            let externalSource = try await readSource(at: url)
            switch SourceThreeWayMerge.resolve(
                base: baseSource,
                local: localSource,
                external: externalSource
            ) {
            case let .merged(mergedSource):
                try mergedSource.write(to: url, atomically: true, encoding: .utf8)
                return .saved(source: mergedSource)
            case let .conflict(_, local, external):
                return .conflict(MarkdownConflict(
                    localSource: local,
                    externalSource: external,
                    blockIDs: []
                ))
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func saveCSV(
        url: URL,
        baseSource: String,
        localSource: String
    ) async -> DocumentEditSaveOutcome {
        do {
            let externalSource = try await readSource(at: url)
            guard externalSource == baseSource else {
                return .conflict(MarkdownConflict(
                    localSource: localSource,
                    externalSource: externalSource,
                    blockIDs: []
                ))
            }
            try localSource.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: localSource)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func commitMarkdown(url: URL, source: String) -> DocumentEditSaveOutcome {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: source)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func commitJSON(url: URL, source: String) -> DocumentEditSaveOutcome {
        do {
            _ = try JSONPreviewAdapter().format(source: source)
            try source.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: source)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func commitCSV(url: URL, source: String) -> DocumentEditSaveOutcome {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: source)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func commitLatex(url: URL, source: String) -> DocumentEditSaveOutcome {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
            return .saved(source: source)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func transition(
        session: MarkdownEditSession,
        source: String,
        markdownBlocks: [MarkdownEditableBlock]? = nil,
        jsonErrorMessage: String? = nil,
        jsonCursorUTF8Offset: Int? = nil
    ) -> DocumentEditTransition {
        DocumentEditTransition(
            session: session,
            source: source,
            markdownBlocks: markdownBlocks ?? MarkdownBlockDocument(source: source).blocks,
            jsonErrorMessage: jsonErrorMessage,
            jsonCursorUTF8Offset: jsonCursorUTF8Offset
        )
    }

    private func validateJSONTransition(
        session: MarkdownEditSession,
        source: String
    ) -> DocumentEditTransition {
        do {
            _ = try JSONPreviewAdapter().format(source: source)
            return transition(session: session, source: source)
        } catch {
            var failed = session
            failed.saveState = .failed
            return transition(
                session: failed,
                source: source,
                jsonErrorMessage: error.localizedDescription
            )
        }
    }

    func readSource(at url: URL) async throws -> String {
        try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value
    }
}
