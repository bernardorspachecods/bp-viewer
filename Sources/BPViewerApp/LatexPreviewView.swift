import AppKit
import BPViewerCore
@preconcurrency import PDFKit
import SwiftUI

struct LatexPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: Data
    let documentID: String
    let sourceURL: URL
    let editingSession: SourceEditSession?
    let cursorUTF8Offset: Int?
    let diffSession: DocumentDiffSession?
    let presentationMode: DocumentPresentationMode
    let zoom: Double
    let onNavigate: (URL) -> Void
    let onBeginEditing: (Int, CGPoint) -> Void
    let onOpenCitation: (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleSplitView: () -> Void
    let onToggleDiff: (DocumentDiffMode) -> Void
    let onEndEditing: () -> Void
    let onDiscardEditing: () -> Void
    let onDiscardGitChanges: @MainActor @Sendable () -> Void
    let onKeepLocalEdit: () -> Void
    let onUseExternalEdit: () -> Void
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let findTarget: FindTarget
    let onFindTargetChanged: (FindTarget) -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    @Binding var isOutlineVisible: Bool
    let pageIndex: Int
    let readingPosition: PDFReadingPosition?
    let onReadingPositionChanged: (PDFReadingPosition) -> Void
    let isSnapshotCaptureActive: Bool
    let onSnapshot: (() -> Void)?
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DocumentInteractionToolbar(
                isOutlineAvailable: !PDFOutlineEntryProxy.entries(from: data).isEmpty,
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
                onDiscardEditing: onDiscardEditing,
                onSave: onEndEditing
            )

            if let editingSession, let conflict = editingSession.conflict {
                MarkdownConflictView(
                    conflict: conflict,
                    onKeepLocal: onKeepLocalEdit,
                    onUseExternal: onUseExternalEdit
                )
            }

            HStack(spacing: 0) {
                if let editingSession {
                    if let diffSession {
                        DocumentDiffView(
                            baseline: diffSession.baseline,
                            unavailableMessage: diffSession.unavailableMessage,
                            editedSource: editingSession.currentSource,
                            zoom: zoom,
                            syntaxHighlighting: .latex(LatexSyntaxColorPalette(isDark: colorScheme == .dark)),
                            monospaced: true,
                            markdownShortcutsEnabled: false,
                            findQuery: findQuery,
                            findRequestID: findRequestID,
                            findBackwards: findBackwards,
                            isFindTarget: findTarget == .source,
                            onFindFocus: { onFindTargetChanged(.source) },
                            onFindMatchCount: onFindMatchCount,
                            onSourceChanged: onSourceChanged,
                            onEndEditing: { _ in onEndEditing() },
                            onDiscardGitChanges: onDiscardGitChanges
                        )
                    } else if editingSession.mode == .split {
                        ResizableSplitView {
                            latexSourceEditor(editingSession: editingSession)
                        } trailing: {
                            pdfSurface
                        }
                    } else {
                        latexSourceEditor(editingSession: editingSession)
                    }
                } else {
                    pdfSurface
                }
            }
        }
        .id(documentID)
    }

    private func latexSourceEditor(editingSession: SourceEditSession) -> some View {
        LatexSourceEditor(
            source: editingSession.currentSource,
            zoom: zoom,
            cursorUTF8Offset: cursorUTF8Offset,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: findTarget == .source,
            onFindFocus: { onFindTargetChanged(.source) },
            onFindMatchCount: onFindMatchCount,
            onEndEditing: onEndEditing,
            onSourceChanged: onSourceChanged,
            onOpenCitation: onOpenCitation
        )
        .id(sourceURL.standardizedFileURL.path)
    }

    private var pdfSurface: some View {
        PDFPreviewView(
            data: data,
            zoom: zoom,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: findTarget == .preview,
            onFindFocus: { onFindTargetChanged(.preview) },
            onFindMatchCount: onFindMatchCount,
            pageIndex: pageIndex,
            readingPosition: readingPosition,
            onReadingPositionChanged: onReadingPositionChanged,
            isOutlineVisible: $isOutlineVisible,
            isSnapshotCaptureActive: isSnapshotCaptureActive,
            onSnapshot: onSnapshot,
            onSnapshotCancel: onSnapshotCancel,
            onSnapshotCapture: onSnapshotCapture,
            onNavigate: onNavigate,
            onDoubleClick: onBeginEditing
        )
    }
}

private struct LatexSourceEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onEndEditing: () -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onOpenCitation: (Int) -> Void

    var body: some View {
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
            syntaxHighlighting: .latex(LatexSyntaxColorPalette(isDark: colorScheme == .dark)),
            markdownShortcutsEnabled: false,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: isFindTarget,
            onFindFocus: onFindFocus,
            onFindMatchCount: onFindMatchCount,
            onSourceChanged: onSourceChanged,
            onEndEditing: { _ in onEndEditing() },
            onDoubleClick: onOpenCitation
        )
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
        .onExitCommand(perform: onEndEditing)
    }
}

// PDFPreviewView intentionally keeps its outline implementation private. The
// toolbar only needs to know whether the PDF contains an outline.
private enum PDFOutlineEntryProxy {
    static func entries(from data: Data) -> [String] {
        guard let document = PDFDocument(data: data), document.outlineRoot != nil else { return [] }
        return ["outline"]
    }
}
