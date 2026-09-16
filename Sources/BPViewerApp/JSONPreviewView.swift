import AppKit
import BPViewerCore
import SwiftUI

struct JSONPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let editingSession: MarkdownEditSession?
    let diffSession: DocumentDiffSession?
    let presentationMode: DocumentPresentationMode
    let onBeginEditing: (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleDiff: (DocumentDiffMode) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onDiscardEditing: () -> Void
    let onDiscardGitChanges: @MainActor @Sendable () -> Void
    let onKeepLocalEdit: () -> Void
    let onUseExternalEdit: () -> Void
    let onSnapshot: (() -> Void)?
    let isSnapshotCaptureActive: Bool
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let findTarget: FindTarget
    let onFindTargetChanged: (FindTarget) -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    @State private var editorSource: String?

    var body: some View {
        VStack(spacing: 0) {
            DocumentInteractionToolbar(
                isOutlineAvailable: false,
                isOutlineVisible: false,
                onToggleOutline: {},
                onSnapshot: onSnapshot,
                editingSession: editingSession,
                presentationMode: presentationMode,
                supportsSplitView: false,
                onToggleSplitView: nil,
                diffSession: diffSession,
                onToggleDiff: onToggleDiff,
                onUndo: onUndo,
                onRedo: onRedo,
                onDiscardEditing: onDiscardEditing,
                onSave: {
                    onEndEditing(editorSource ?? editingSession?.currentSource ?? source)
                }
            )

            if let editingSession {
                if let conflict = editingSession.conflict {
                    JSONConflictView(
                        conflict: conflict,
                        onKeepLocal: onKeepLocalEdit,
                        onUseExternal: onUseExternalEdit
                    )
                }
                Group {
                    if let diffSession {
                        DocumentDiffView(
                        baseline: diffSession.baseline,
                        unavailableMessage: diffSession.unavailableMessage,
                        editedSource: editingSession.currentSource,
                        zoom: zoom,
                        syntaxHighlighting: .json(
                            JSONSyntaxColorPalette(isDark: colorScheme == .dark)
                        ),
                        monospaced: true,
                        markdownShortcutsEnabled: false,
                        findQuery: findQuery,
                        findRequestID: findRequestID,
                        findBackwards: findBackwards,
                        isFindTarget: findTarget == .source,
                        onFindFocus: { onFindTargetChanged(.source) },
                        onFindMatchCount: onFindMatchCount,
                        onSourceChanged: { text in
                            editorSource = text
                            onSourceChanged(text)
                        },
                        onEndEditing: { text in
                            editorSource = text
                            onSourceChanged(text)
                            onEndEditing(text)
                        },
                        onDiscardGitChanges: onDiscardGitChanges
                        )
                    } else {
                        JSONSourceEditor(
                        source: editingSession.currentSource,
                        zoom: zoom,
                        cursorUTF8Offset: cursorUTF8Offset,
                        syntaxHighlightPalette: JSONSyntaxColorPalette(isDark: colorScheme == .dark),
                        findQuery: findQuery,
                        findRequestID: findRequestID,
                        findBackwards: findBackwards,
                        isFindTarget: findTarget == .source,
                        onFindFocus: { onFindTargetChanged(.source) },
                        onFindMatchCount: onFindMatchCount,
                        onSourceChanged: { text in
                            editorSource = text
                            onSourceChanged(text)
                        },
                        onEndEditing: { text in
                            editorSource = text
                            onSourceChanged(text)
                            onEndEditing(text)
                        }
                        )
                    }
                }
                .onAppear {
                    editorSource = editingSession.currentSource
                }
                .onChange(of: editingSession.currentSource) { _, newSource in
                    editorSource = newSource
                }
            } else {
                previewSurface
            }
        }
        .background(BPTokens.Color.canvas)
    }

    private var previewSurface: some View {
        VStack(spacing: 0) {
            ZStack {
                SourceTextView(
                    source: source,
                    zoom: zoom,
                    cursorUTF8Offset: nil,
                    isEditable: false,
                    lineNumbers: true,
                    lineNumberOverrides: [:],
                    lineHighlights: [:],
                    lineSpacingBefore: [:],
                    monospaced: true,
                    syntaxHighlighting: .json(
                        JSONSyntaxColorPalette(isDark: colorScheme == .dark)
                    ),
                    markdownShortcutsEnabled: false,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    isFindTarget: findTarget == .preview,
                    onFindFocus: { onFindTargetChanged(.preview) },
                    onFindMatchCount: onFindMatchCount,
                    onSourceChanged: { _ in },
                    onEndEditing: { _ in },
                    onDoubleClick: onBeginEditing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BPTokens.Color.canvas)

                if isSnapshotCaptureActive {
                    SnapshotSelectionOverlay(
                        onCancel: onSnapshotCancel,
                        onCapture: onSnapshotCapture
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private struct JSONSourceEditor: View {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let syntaxHighlightPalette: JSONSyntaxColorPalette
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SourceTextView(
                source: source,
                zoom: zoom,
                cursorUTF8Offset: cursorUTF8Offset,
                isEditable: true,
                lineNumbers: true,
                lineNumberOverrides: [:],
                lineHighlights: [:],
                lineSpacingBefore: [:],
                monospaced: true,
                syntaxHighlighting: .json(syntaxHighlightPalette),
                markdownShortcutsEnabled: false,
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
                    SourceEditorLayout.contentMaxWidth
                        + (SourceEditorLayout.horizontalPadding * 2)
                ) * CGFloat(zoom),
                maxHeight: .infinity
            )
            Spacer(minLength: 0)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
    }
}

private struct JSONConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("This JSON file was also changed outside bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))

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
}
