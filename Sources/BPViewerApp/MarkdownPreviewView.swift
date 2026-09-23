import SwiftUI
import BPViewerCore
import AppKit

private enum MarkdownOutlineLayout {
    static let animation = Animation.easeInOut(duration: 0.24)
}

struct MarkdownPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let outline: [MarkdownOutlineEntry]
    let markdownBlocks: [MarkdownEditableBlock]
    let editingSession: MarkdownEditSession?
    let diffSession: DocumentDiffSession?
    let presentationMode: DocumentPresentationMode
    let onNavigate: (URL) -> Void
    let onMarkdownTextChanged: @MainActor @Sendable (String) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleSplitView: () -> Void
    let onToggleDiff: (DocumentDiffMode) -> Void
    let onEndMarkdownEditing: () -> Void
    let onSaveMarkdownEditing: () -> Void
    let onDiscardMarkdownEditing: () -> Void
    let onDiscardGitChanges: @MainActor @Sendable () -> Void
    let onKeepLocalMarkdownEdit: () -> Void
    let onUseExternalMarkdownEdit: () -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let findTarget: FindTarget
    let onFindTargetChanged: (FindTarget) -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    @Binding var isOutlineVisible: Bool
    let outlineWidth: Double
    let onOutlineWidthChanged: (Double) -> Void
    let onOutlineWidthChangeEnded: () -> Void
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
            DocumentInteractionToolbar(
                isOutlineAvailable: !outlineItems.isEmpty,
                isOutlineVisible: isOutlineVisible,
                onToggleOutline: { isOutlineVisible.toggle() },
                onSnapshot: onSnapshot,
                editingSession: editingSession,
                presentationMode: presentationMode,
                supportsSplitView: true,
                onToggleSplitView: onToggleSplitView,
                diffSession: diffSession,
                onToggleDiff: onToggleDiff,
                onUndo: onUndo,
                onRedo: onRedo,
                onDiscardEditing: onDiscardMarkdownEditing,
                onSave: onEndMarkdownEditing
            )

            if let editingSession, let conflict = editingSession.conflict {
                MarkdownConflictView(
                    conflict: conflict,
                    onKeepLocal: onKeepLocalMarkdownEdit,
                    onUseExternal: onUseExternalMarkdownEdit
                )
            }

            HStack(spacing: 0) {
                outlineSurface
                documentSurface
            }
            .animation(MarkdownOutlineLayout.animation, value: isOutlineVisible)
        }
        .id(documentID)
        .onExitCommand(perform: exitEditing)
    }

    private var exitEditing: () -> Void {
        if let diffSession {
            return { onToggleDiff(diffSession.mode) }
        }
        if editingSession?.mode == .split {
            return onSaveMarkdownEditing
        }
        return onEndMarkdownEditing
    }

    private var outlineSurface: some View {
        ResizableDocumentOutlineView(
            isVisible: isOutlineVisible,
            width: outlineWidth,
            entries: outlineItems,
            selectedID: selectedHeadingID,
            onSelect: { item in
                selectedHeadingID = item.id
                outlineRequestID += 1
                if editingSession != nil {
                    pendingCursorUTF8Offset = outline.first {
                        $0.id == item.id
                    }?.sourceUTF8Offset
                }
            },
            onChanged: onOutlineWidthChanged,
            onEnded: { _ in onOutlineWidthChangeEnded() }
        )
    }

    @ViewBuilder
    private var documentSurface: some View {
        if let editingSession {
            if let diffSession {
                DocumentDiffView(
                    baseline: diffSession.baseline,
                    unavailableMessage: diffSession.unavailableMessage,
                    editedSource: editingSession.currentSource,
                    cursorUTF8Offset: pendingCursorUTF8Offset,
                    cursorRequestID: outlineRequestID,
                    zoom: zoom,
                    syntaxHighlighting: .markdown(
                        MarkdownSyntaxColorPalette(isDark: colorScheme == .dark)
                    ),
                    monospaced: false,
                    markdownShortcutsEnabled: true,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    isFindTarget: findTarget == .source,
                    onFindFocus: { onFindTargetChanged(.source) },
                    onFindMatchCount: onFindMatchCount,
                    onSourceChanged: onMarkdownTextChanged,
                    onEndEditing: { text in
                        onMarkdownTextChanged(text)
                        exitEditing()
                    },
                    onDiscardGitChanges: onDiscardGitChanges
                )
            } else {
                if editingSession.mode == .split {
                    ResizableSplitView {
                        markdownSourceEditor(editingSession: editingSession)
                    } trailing: {
                        previewSurface
                    }
                } else {
                    markdownSourceEditor(editingSession: editingSession)
                }
            }
        } else {
            previewSurface
        }
    }

    private func markdownSourceEditor(editingSession: MarkdownEditSession) -> some View {
        MarkdownSourceEditor(
            source: editingSession.currentSource,
            zoom: zoom,
            cursorUTF8Offset: pendingCursorUTF8Offset,
            cursorRequestID: outlineRequestID,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: findTarget == .source,
            onFindFocus: { onFindTargetChanged(.source) },
            onFindMatchCount: onFindMatchCount,
            onEndEditing: { text in
                onMarkdownTextChanged(text)
                if editingSession.mode == .split {
                    onSaveMarkdownEditing()
                } else {
                    onEndMarkdownEditing()
                }
            },
            onSourceChanged: onMarkdownTextChanged
        )
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
                isFindTarget: findTarget == .preview,
                onFindFocus: { onFindTargetChanged(.preview) },
                onFindMatchCount: onFindMatchCount,
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

private struct MarkdownSourceEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let cursorRequestID: Int
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SourceTextView(
                    source: source,
                    zoom: zoom,
                    cursorUTF8Offset: cursorUTF8Offset,
                    cursorRequestID: cursorRequestID,
                    isEditable: true,
                    lineNumbers: true,
                    lineNumberOverrides: [:],
                    lineHighlights: [:],
                    lineSpacingBefore: [:],
                    monospaced: false,
                    syntaxHighlighting: .markdown(
                        MarkdownSyntaxColorPalette(isDark: colorScheme == .dark)
                    ),
                    markdownShortcutsEnabled: true,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    isFindTarget: isFindTarget,
                    onFindFocus: onFindFocus,
                    onFindMatchCount: onFindMatchCount,
                    onSourceChanged: onSourceChanged,
                    onEndEditing: onEndEditing,
                    onDoubleClick: nil
                )
                .frame(
                    maxWidth: (
                        SourceEditorLayout.contentMaxWidth + (SourceEditorLayout.horizontalPadding * 2)
                    ) * CGFloat(zoom),
                    maxHeight: .infinity
                )
                Spacer(minLength: 0)
            }
            .onExitCommand {
                onEndEditing(source)
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
    }
}


struct MarkdownConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("This document was also changed outside bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))
            HStack(spacing: BPTokens.Spacing.sm) {
                conflictColumn(title: "My Changes", source: conflict.localSource)
                conflictColumn(title: "External Version", source: conflict.externalSource)
            }
            HStack {
                Spacer()
                Button("Use External Version", action: onUseExternal)
                Button("Keep My Changes", action: onKeepLocal)
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
