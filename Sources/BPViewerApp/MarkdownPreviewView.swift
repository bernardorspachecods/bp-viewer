import SwiftUI
import BPViewerCore
import AppKit

struct MarkdownPreviewView: View {
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let outline: [MarkdownOutlineEntry]
    let markdownBlocks: [MarkdownEditableBlock]
    let editingSession: MarkdownEditSession?
    let onNavigate: (URL) -> Void
    let onMarkdownTextChanged: @MainActor @Sendable (String) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndMarkdownEditing: () -> Void
    let onKeepLocalMarkdownEdit: () -> Void
    let onUseExternalMarkdownEdit: () -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    @Binding var isOutlineVisible: Bool
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void
    let isSnapshotCaptureActive: Bool
    let onSnapshot: (() -> Void)?
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    @State private var selectedHeadingID: String?
    @State private var outlineRequestID = 0
    @State private var pendingCursorUTF8Offset: Int?

    private var outlineItems: [DocumentOutlineItem] {
        outline.map {
            DocumentOutlineItem(
                id: $0.id,
                title: $0.title,
                level: max($0.level - 1, 0),
                isSelectable: true
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !outlineItems.isEmpty || onSnapshot != nil {
                DocumentOutlineToolbar(
                    isVisible: isOutlineVisible,
                    onToggle: { isOutlineVisible.toggle() },
                    onSnapshot: onSnapshot
                )
            }

            if let editingSession {
                MarkdownEditToolbar(
                    session: editingSession,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onToggleMarkdownMode: onToggleMarkdownMode,
                    onEndEditing: onEndMarkdownEditing
                )
                if let conflict = editingSession.conflict {
                    MarkdownConflictView(
                        conflict: conflict,
                        onKeepLocal: onKeepLocalMarkdownEdit,
                        onUseExternal: onUseExternalMarkdownEdit
                    )
                }
            }

            HStack(spacing: 0) {
                if isOutlineVisible {
                    DocumentOutlineSidebar(
                        entries: outlineItems,
                        selectedID: selectedHeadingID
                    ) { item in
                        selectedHeadingID = item.id
                        outlineRequestID += 1
                    }
                    Divider()
                }

                if let editingSession {
                    MarkdownSourceEditor(
                        source: editingSession.currentSource,
                        zoom: zoom,
                        cursorUTF8Offset: pendingCursorUTF8Offset,
                        onEndEditing: onEndMarkdownEditing,
                        onSourceChanged: onMarkdownTextChanged
                    )
                    if editingSession.mode == .split {
                        Divider()
                        previewSurface
                    }
                } else {
                    previewSurface
                }
            }
        }
        .id(documentID)
    }

    private var previewSurface: some View {
        ZStack {
            MarkdownWebView(
                html: html,
                baseURL: baseURL,
                documentID: documentID,
                previewRevision: previewRevision,
                canBeginEditing: editingSession == nil,
                onNavigate: onNavigate,
                onMarkdownEditEvent: { event in
                    if event.kind == .begin {
                        pendingCursorUTF8Offset = cursorUTF8Offset(for: event)
                    }
                    onMarkdownEditEvent(event)
                },
                zoom: zoom,
                findQuery: findQuery,
                findRequestID: findRequestID,
                findBackwards: findBackwards,
                requestedHeadingID: selectedHeadingID,
                outlineRequestID: outlineRequestID,
                readingPosition: readingPosition,
                onReadingPositionChanged: onReadingPositionChanged
            )
            if isSnapshotCaptureActive {
                SnapshotSelectionOverlay(
                    onCancel: onSnapshotCancel,
                    onCapture: onSnapshotCapture
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cursorUTF8Offset(for event: MarkdownWebEditEvent) -> Int? {
        guard let blockID = event.blockID,
              let renderedTextOffset = event.renderedTextOffset,
              let block = markdownBlocks.first(where: { $0.id == blockID }) else {
            return nil
        }
        return block.sourceRange.startOffset + block.sourceOffset(forRenderedTextOffset: renderedTextOffset)
    }
}

struct MarkdownWebEditEvent {
    enum Kind {
        case begin
        case change
        case end
        case undo
        case redo
    }

    let kind: Kind
    let text: String
    let blockID: String?
    let renderedTextOffset: Int?
}

private struct MarkdownEditToolbar: View {
    let session: MarkdownEditSession
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndEditing: () -> Void

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            Label(
                session.mode == .split ? "Edição dividida" : "Edição Markdown",
                systemImage: session.mode == .split ? "rectangle.split.2x1" : "chevron.left.forwardslash.chevron.right"
            )
            .font(BPTokens.Typography.caption.weight(.medium))

            Button(session.mode == .split ? "Edição Markdown" : "Abrir split view") {
                onToggleMarkdownMode()
            }
            .buttonStyle(.bordered)

            Button(action: onUndo) {
                Label("Desfazer", systemImage: "arrow.uturn.backward")
            }
            .disabled(session.undoSources.isEmpty)

            Button(action: onRedo) {
                Label("Refazer", systemImage: "arrow.uturn.forward")
            }
            .disabled(session.redoSources.isEmpty)

            Spacer()

            Text(session.saveState.label)
                .font(BPTokens.Typography.caption)
                .foregroundStyle(session.saveState == .conflict ? BPTokens.Color.warning : BPTokens.Color.muted)

            Button("Concluir", action: onEndEditing)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }
}


private struct MarkdownSourceEditor: View {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let onEndEditing: () -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SourceTextView(
                    source: source,
                    zoom: zoom,
                    cursorUTF8Offset: cursorUTF8Offset,
                    monospaced: false,
                    syntaxHighlightPalette: nil,
                    onSourceChanged: onSourceChanged,
                    onEndEditing: { _ in onEndEditing() }
                )
                .frame(
                    maxWidth: (
                        SourceEditorLayout.contentMaxWidth + (SourceEditorLayout.horizontalPadding * 2)
                    ) * CGFloat(zoom),
                    maxHeight: .infinity
                )
                Spacer(minLength: 0)
            }
            .onExitCommand(perform: onEndEditing)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
    }
}


private struct MarkdownConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("Este documento também foi alterado fora do bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))
            HStack(spacing: BPTokens.Spacing.sm) {
                conflictColumn(title: "As minhas alterações", source: conflict.localSource)
                conflictColumn(title: "Versão externa", source: conflict.externalSource)
            }
            HStack {
                Spacer()
                Button("Usar versão externa", action: onUseExternal)
                Button("Manter as minhas alterações", action: onKeepLocal)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.sm)
        .background(BPTokens.Color.warning.opacity(0.1))
    }

    private func conflictColumn(title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
            Text(title)
                .font(BPTokens.Typography.caption.weight(.medium))
            ScrollView {
                Text(source)
                    .font(BPTokens.Typography.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BPTokens.Spacing.xs)
            }
            .frame(maxHeight: 100)
            .background(BPTokens.Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
