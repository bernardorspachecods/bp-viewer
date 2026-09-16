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

enum DocumentEditSaveEvent {
    case markdown(tabID: String, source: String, outcome: DocumentEditSaveOutcome)
}

/// Encapsulates document-edit state transitions and file reconciliation. It
/// deliberately exchanges values instead of mutating AppModel's tabs.
@MainActor
final class DocumentEditCoordinator {
    private let onSaveEvent: (DocumentEditSaveEvent) -> Void
    private var markdownSaveTasks: [String: Task<Void, Never>] = [:]

    init(onSaveEvent: @escaping (DocumentEditSaveEvent) -> Void) {
        self.onSaveEvent = onSaveEvent
    }

    func beginMarkdown(source: String) -> DocumentEditTransition {
        let session = MarkdownEditSession(baseSource: source, currentSource: source)
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

    func beginJSON(
        source: String,
        formattedSource: String,
        previewUTF8Offset: Int
    ) -> DocumentEditTransition {
        let rawOffset = JSONPreviewAdapter().sourceOffset(
            forFormattedUTF8Offset: previewUTF8Offset,
            source: source,
            formattedSource: formattedSource
        )
        let session = MarkdownEditSession(baseSource: source, currentSource: source)
        return transition(
            session: session,
            source: source,
            jsonCursorUTF8Offset: rawOffset
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

    func scheduleMarkdownSave(
        tabID: String,
        url: URL,
        baseSource: String,
        localSource: String
    ) {
        markdownSaveTasks[tabID]?.cancel()
        markdownSaveTasks[tabID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            let outcome = await self.saveMarkdown(
                url: url,
                baseSource: baseSource,
                localSource: localSource
            )
            guard !Task.isCancelled else { return }
            self.onSaveEvent(.markdown(tabID: tabID, source: localSource, outcome: outcome))
        }
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

    func cancel(tabIDs: some Sequence<String>) {
        for tabID in tabIDs {
            markdownSaveTasks[tabID]?.cancel()
            markdownSaveTasks.removeValue(forKey: tabID)
        }
    }

    private func transition(
        session: MarkdownEditSession,
        source: String,
        jsonErrorMessage: String? = nil,
        jsonCursorUTF8Offset: Int? = nil
    ) -> DocumentEditTransition {
        DocumentEditTransition(
            session: session,
            source: source,
            markdownBlocks: MarkdownBlockDocument(source: source).blocks,
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
