import AppKit
import BPViewerCore
import SwiftUI

struct DocumentDiffView: View {
    @State private var scrollCoordinator = DocumentDiffScrollCoordinator()

    let baseline: DocumentDiffBaseline?
    let unavailableMessage: String?
    let editedSource: String
    var cursorUTF8Offset: Int? = nil
    var cursorRequestID: Int = 0
    let zoom: Double
    let syntaxHighlighting: SourceSyntaxHighlighting?
    let monospaced: Bool
    let markdownShortcutsEnabled: Bool
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onDiscardGitChanges: @MainActor @Sendable () -> Void

    private var diff: DocumentDiff? {
        guard let baseline else { return nil }
        return DocumentDiffEngine().compare(
            reference: baseline.source,
            edited: editedSource
        )
    }

    var body: some View {
        let currentDiff = diff

        VStack(spacing: 0) {
            header(diff: currentDiff)
            Divider()
            GeometryReader { proxy in
                let layout = currentDiff.map {
                    DocumentDiffLayout(
                        diff: $0,
                        panelWidth: proxy.size.width / 2,
                        zoom: zoom,
                        monospaced: monospaced
                    )
                }
                HStack(spacing: 0) {
                    referenceSurface(layout: layout)
                    Divider()
                    editedSurface(layout: layout, diff: currentDiff)
                }
            }
        }
        .background(BPTokens.Color.canvas)
        .onDisappear {
            scrollCoordinator.reset()
        }
    }

    private func header(diff: DocumentDiff?) -> some View {
        HStack(spacing: 0) {
            headerLabel(
                title: baseline?.label ?? "Reference",
                subtitle: diff.map { "\($0.removedLineCount) removed" } ?? "Unavailable"
            )
            Divider()
                .frame(height: 24)
            currentDraftHeader(diff: diff)
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }

    private func currentDraftHeader(diff: DocumentDiff?) -> some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            headerLabel(
                title: "Current Draft",
                subtitle: diff.map { "\($0.addedLineCount) added" } ?? "Editable",
                fillsAvailableWidth: false
            )
            if baseline != nil {
                Button("Discard Git Changes", role: .destructive, action: onDiscardGitChanges)
                    .buttonStyle(.bordered)
                    .disabled(diff?.hasChanges != true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BPTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerLabel(
        title: String,
        subtitle: String,
        fillsAvailableWidth: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(BPTokens.Typography.caption.weight(.semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(BPTokens.Color.muted)
        }
        .padding(.horizontal, BPTokens.Spacing.sm)
        .frame(
            maxWidth: fillsAvailableWidth ? .infinity : nil,
            alignment: .leading
        )
    }

    @ViewBuilder
    private func referenceSurface(layout: DocumentDiffLayout?) -> some View {
        if let layout {
            SourceTextView(
                source: layout.referenceSource,
                zoom: zoom,
                cursorUTF8Offset: nil,
                isEditable: false,
                lineNumbers: true,
                lineNumberOverrides: layout.referenceLineNumberOverrides,
                lineHighlights: layout.referenceLineHighlights,
                lineSpacingBefore: layout.referenceLineSpacingBefore,
                monospaced: monospaced,
                syntaxHighlighting: syntaxHighlighting,
                markdownShortcutsEnabled: false,
                findQuery: "",
                findRequestID: 0,
                findBackwards: false,
                isFindTarget: false,
                onFindFocus: onFindFocus,
                onFindMatchCount: { _ in },
                onSourceChanged: { _ in },
                onEndEditing: { _ in },
                onDoubleClick: nil,
                onScrollViewReady: { scrollView in
                    scrollCoordinator.register(scrollView, as: .reference)
                }
            )
            .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            .background(BPTokens.Color.canvas)
        } else {
            VStack(alignment: .leading, spacing: BPTokens.Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 24))
                    .foregroundStyle(BPTokens.Color.muted)
                Text(unavailableMessage ?? "No reference is available.")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BPTokens.Spacing.lg)
            .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BPTokens.Color.canvas)
        }
    }

    private func editedSurface(
        layout: DocumentDiffLayout?,
        diff: DocumentDiff?
    ) -> some View {
        SourceTextView(
            source: editedSource,
            zoom: zoom,
            cursorUTF8Offset: cursorUTF8Offset,
            cursorRequestID: cursorRequestID,
            isEditable: true,
            lineNumbers: true,
            lineNumberOverrides: [:],
            lineHighlights: diff?.rightLineKinds ?? [:],
            lineSpacingBefore: layout?.editedLineSpacingBefore ?? [:],
            monospaced: monospaced,
            syntaxHighlighting: syntaxHighlighting,
            markdownShortcutsEnabled: markdownShortcutsEnabled,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: isFindTarget,
            onFindFocus: onFindFocus,
            onFindMatchCount: onFindMatchCount,
            onSourceChanged: onSourceChanged,
            onEndEditing: onEndEditing,
            onDoubleClick: nil,
            onScrollViewReady: { scrollView in
                scrollCoordinator.register(scrollView, as: .edited)
            }
        )
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }
}
