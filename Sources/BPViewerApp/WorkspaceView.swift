import AppKit
import BPViewerCore
import SwiftUI

struct DocumentWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            DocumentSurfaceView()
        }
        .background(BPTokens.Color.canvas)
    }
}

struct TabBarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargetID: String?

    private let endDropTargetID = "__tab_end__"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: model.activeTabID == tab.id,
                        isDropTarget: dropTargetID == tab.id
                    )
                    .draggable(tab.id) {
                        Text(tab.title)
                            .padding(.horizontal, BPTokens.Spacing.sm)
                            .padding(.vertical, BPTokens.Spacing.xs)
                            .background(BPTokens.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceID = items.first, sourceID != tab.id else { return false }
                        model.moveTab(id: sourceID, before: tab.id)
                        dropTargetID = nil
                        return true
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            updateDropTarget(tab.id)
                        } else if dropTargetID == tab.id {
                            updateDropTarget(nil)
                        }
                    }
                }

                Rectangle()
                    .fill(.clear)
                    .frame(minWidth: 36, maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceID = items.first else { return false }
                        model.moveTabToEnd(id: sourceID)
                        dropTargetID = nil
                        return true
                    } isTargeted: { isTargeted in
                        updateDropTarget(isTargeted ? endDropTargetID : nil)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 28)
                            .opacity(dropTargetID == endDropTargetID ? 1 : 0)
                            .scaleEffect(x: dropTargetID == endDropTargetID ? 1 : 0.35, anchor: .leading)
                            .animation(.easeInOut(duration: 0.14), value: dropTargetID == endDropTargetID)
                    }
            }
            .padding(.horizontal, BPTokens.Spacing.xs)
        }
        .frame(height: 38)
        .background(BPTokens.Color.surface)
    }

    private func updateDropTarget(_ targetID: String?) {
        withAnimation(.easeInOut(duration: 0.14)) {
            dropTargetID = targetID
        }
    }
}

struct TabItemView: View {
    @EnvironmentObject private var model: AppModel
    let tab: DocumentTab
    let isActive: Bool
    let isDropTarget: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                model.selectTab(id: tab.id)
            } label: {
                HStack(spacing: BPTokens.Spacing.xs) {
                    Image(systemName: iconName)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tab.title)
                            .lineLimit(1)
                        if tab.subtitle != tab.title {
                            Text(tab.subtitle)
                                .font(BPTokens.Typography.caption)
                                .foregroundStyle(BPTokens.Color.muted)
                        }
                    }
                }
                .font(BPTokens.Typography.caption)
                .padding(.leading, BPTokens.Spacing.xs)
                .padding(.trailing, 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .zIndex(1)
        }
        .padding(.horizontal, BPTokens.Spacing.xs)
        .frame(minWidth: 150, minHeight: 36)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .leading) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .transition(.opacity.combined(with: .scale(scale: 0.35, anchor: .leading)))
            }
        }
        .contextMenu {
            Button("Copy Path") { model.copyPath(tab.url) }
            Divider()
            Button("Close Tab") { model.closeTab(tab) }
            Button("Close Other Tabs") { model.closeOtherTabs(keeping: tab) }
            Button("Close Tabs to the Right") { model.closeTabsToRight(of: tab) }
        }
    }

    private var iconName: String {
        return switch tab.kind {
        case .markdown: "doc.richtext"
        case .latex: "doc.text"
        case .json: "curlybraces"
        case .docx: "doc.text.fill"
        case .pdf: "doc.fill"
        case .other: "doc"
        }
    }
}

struct DocumentSurfaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let tab = model.activeTab {
                PreviewPane(tab: tab)
            } else {
                EmptyStateView(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No Document Selected",
                    message: model.rootURL == nil
                        ? "Open a folder and choose a Markdown, LaTeX, JSON, DOCX, or PDF file."
                        : "Choose a file in the tree to open a tab."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PreviewPane: View {
    @EnvironmentObject private var model: AppModel
    let tab: DocumentTab
    @State private var isTitleRowHovered = false
    @State private var isPathRowHovered = false

    private var snapshotAction: (() -> Void)? {
        guard model.activeTabID == tab.id, model.canCaptureActivePreview else {
            return nil
        }
        return { model.startSnapshotCapture() }
    }

    private var previewHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                HStack(spacing: BPTokens.Spacing.xxs) {
                    Text(tab.title)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy Title") { model.copyText(tab.title) }
                        }
                    CopyTextButton(text: tab.title, isVisible: isTitleRowHovered) {
                        model.copyText($0)
                    }
                }
                .onHover { isTitleRowHovered = $0 }
                HStack(spacing: BPTokens.Spacing.xxs) {
                    let path = FilePathCopy.string(for: tab.url)
                    Text(path)
                        .font(BPTokens.Typography.caption)
                        .foregroundStyle(BPTokens.Color.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy Path") { model.copyPath(tab.url) }
                        }
                    CopyTextButton(text: path, isVisible: isPathRowHovered, helpText: "Copy Path") {
                        model.copyText($0)
                    }
                }
                .onHover { isPathRowHovered = $0 }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BPTokens.Spacing.xxs) {
                StatusBadge(status: tab.status)
                if let updatedAt = tab.previewUpdatedAt {
                    Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(BPTokens.Typography.caption)
                        .foregroundStyle(BPTokens.Color.muted)
                }
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .overlay(alignment: .center) {
            previewErrorOverlay(showingStalePreview: tab.isStale)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            Divider()
            if model.isFindBarVisible {
                PreviewFindBar()
            }

            VStack(spacing: 0) {
                    if tab.kind == .markdown, let html = tab.previewHTML {
                        VStack(spacing: 0) {
                            MarkdownPreviewView(
                                html: html,
                                baseURL: tab.previewBaseURL ?? tab.url.deletingLastPathComponent(),
                                documentID: tab.id,
                                previewRevision: tab.previewUpdatedAt,
                                outline: tab.markdownOutline,
                                markdownBlocks: tab.markdownBlocks,
                                editingSession: tab.markdownEditSession?.isEditing == true
                                    || tab.markdownEditSession?.conflict != nil
                                    ? tab.markdownEditSession
                                    : nil,
                                onNavigate: model.openPreviewURL,
                                onMarkdownTextChanged: { text in
                                    model.updateMarkdownEditing(tabID: tab.id, text: text)
                                },
                                onMarkdownEditEvent: { event in
                                    switch event.kind {
                                    case .begin:
                                        model.beginMarkdownEditing(tabID: tab.id)
                                    case .change:
                                        model.updateMarkdownEditing(tabID: tab.id, text: event.text)
                                    case .end:
                                        model.endMarkdownEditing(tabID: tab.id)
                                    case .undo:
                                        _ = model.undoMarkdownEdit()
                                    case .redo:
                                        _ = model.redoMarkdownEdit()
                                    }
                                },
                                onUndo: {
                                    _ = model.undoMarkdownEdit()
                                },
                                onRedo: {
                                    _ = model.redoMarkdownEdit()
                                },
                                onToggleMarkdownMode: {
                                    model.toggleMarkdownEditingMode(tabID: tab.id)
                                },
                                onEndMarkdownEditing: {
                                    model.endMarkdownEditing(tabID: tab.id)
                                },
                                onKeepLocalMarkdownEdit: {
                                    model.keepLocalMarkdownEdit(tabID: tab.id)
                                },
                                onUseExternalMarkdownEdit: {
                                    model.useExternalMarkdownEdit(tabID: tab.id)
                                },
                                zoom: tab.previewZoom,
                                findQuery: model.findQuery,
                                findRequestID: model.findRequestID,
                                findBackwards: model.findBackwards,
                                findTarget: model.findTarget,
                                onFindTargetChanged: model.setFindTarget,
                                onFindMatchCount: model.setFindMatchCount,
                                isOutlineVisible: Binding(
                                    get: { model.tabs.first(where: { $0.id == tab.id })?.isOutlineVisible ?? false },
                                    set: { model.setOutlineVisible($0, forTabID: tab.id) }
                                ),
                                readingPosition: tab.markdownReadingPosition,
                                onReadingPositionChanged: { position in
                                    model.updateMarkdownReadingPosition(position, forTabID: tab.id)
                                },
                                isSnapshotCaptureActive: model.isSnapshotCaptureActive && model.activeTabID == tab.id,
                                onSnapshot: snapshotAction,
                                onSnapshotCancel: model.cancelSnapshotCapture,
                                onSnapshotCapture: { image in
                                    model.finishSnapshotCapture(image, forTabID: tab.id)
                                },
                            )
                        }
                    } else if tab.kind == .json, let source = tab.previewJSON {
                        VStack(spacing: 0) {
                            JSONPreviewView(
                                source: source,
                                zoom: tab.previewZoom,
                                cursorUTF8Offset: tab.jsonCursorUTF8Offset,
                                editingSession: tab.jsonEditSession?.isEditing == true
                                    || tab.jsonEditSession?.conflict != nil
                                    ? tab.jsonEditSession
                                    : nil,
                                onBeginEditing: { offset in
                                    model.beginJSONEditing(
                                        tabID: tab.id,
                                        previewUTF8Offset: offset
                                    )
                                },
                                onSourceChanged: { text in
                                    model.updateJSONEditing(tabID: tab.id, text: text)
                                },
                                onUndo: {
                                    _ = model.undoJSONEdit()
                                },
                                onRedo: {
                                    _ = model.redoJSONEdit()
                                },
                                onEndEditing: { source in
                                    model.endJSONEditing(tabID: tab.id, source: source)
                                },
                                onKeepLocalEdit: {
                                    model.keepLocalJSONEdit(tabID: tab.id)
                                },
                                onUseExternalEdit: {
                                    model.useExternalJSONEdit(tabID: tab.id)
                                },
                                onSnapshot: snapshotAction,
                                isSnapshotCaptureActive: model.isSnapshotCaptureActive && model.activeTabID == tab.id,
                                onSnapshotCancel: model.cancelSnapshotCapture,
                                onSnapshotCapture: { image in
                                    model.finishSnapshotCapture(image, forTabID: tab.id)
                                },
                                findQuery: model.findQuery,
                                findRequestID: model.findRequestID,
                                findBackwards: model.findBackwards,
                                findTarget: model.findTarget,
                                onFindTargetChanged: model.setFindTarget,
                                onFindMatchCount: model.setFindMatchCount
                            )
                        }
                    } else if (tab.kind == .latex || tab.kind == .pdf), let pdfData = tab.previewPDFData {
                        VStack(spacing: 0) {
                            PDFPreviewView(
                                data: pdfData,
                                zoom: tab.previewZoom,
                                findQuery: model.findQuery,
                                findRequestID: model.findRequestID,
                                findBackwards: model.findBackwards,
                                isFindTarget: model.findTarget == .preview,
                                onFindFocus: { model.setFindTarget(.preview) },
                                onFindMatchCount: model.setFindMatchCount,
                                pageIndex: tab.previewPageIndex,
                                readingPosition: tab.pdfReadingPosition,
                                onReadingPositionChanged: { position in
                                    model.updatePDFReadingPosition(position, forTabID: tab.id)
                                },
                                isOutlineVisible: Binding(
                                    get: { model.tabs.first(where: { $0.id == tab.id })?.isOutlineVisible ?? false },
                                    set: { model.setOutlineVisible($0, forTabID: tab.id) }
                                ),
                                isSnapshotCaptureActive: model.isSnapshotCaptureActive && model.activeTabID == tab.id,
                                onSnapshot: snapshotAction,
                                onSnapshotCancel: model.cancelSnapshotCapture,
                                onSnapshotCapture: { image in
                                    model.finishSnapshotCapture(image, forTabID: tab.id)
                                }
                            )
                        }
                    } else if tab.kind == .docx {
                        DocxPreviewView(
                            url: tab.url,
                            zoom: tab.previewZoom,
                            previewRevision: tab.previewUpdatedAt,
                            findQuery: model.findQuery,
                            findRequestID: model.findRequestID,
                            findBackwards: model.findBackwards,
                            isFindTarget: model.findTarget == .preview,
                            onFindFocus: { model.setFindTarget(.preview) },
                            onFindMatchCount: model.setFindMatchCount,
                            onZoomChanged: { value in
                                model.setPreviewZoomFromGesture(value)
                            }
                        )
                    } else {
                        VStack(spacing: 0) {
                            EmptyStateView(
                                systemImage: emptyStateSystemImage,
                                title: emptyStateTitle,
                                message: emptyStateMessage
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BPTokens.Color.canvas)
    }

    @ViewBuilder
    private func previewErrorOverlay(showingStalePreview: Bool) -> some View {
        if let errorMessage = tab.errorMessage {
            if tab.kind == .json && tab.jsonEditSession?.isEditing == true {
                PreviewErrorBanner(
                    message: errorMessage,
                    showingStalePreview: showingStalePreview,
                    title: "Invalid JSON — Not Saved"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BPTokens.Spacing.md)
                .padding(.vertical, BPTokens.Spacing.xs)
            } else {
                PreviewErrorBanner(
                    message: errorMessage,
                    showingStalePreview: showingStalePreview,
                    onRetry: model.refreshActiveTab
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BPTokens.Spacing.md)
                .padding(.vertical, BPTokens.Spacing.xs)
            }
        }
    }

    private var emptyStateSystemImage: String {
        return switch tab.kind {
        case .latex: "doc.text.image"
        case .json: "curlybraces"
        case .pdf: "doc.fill"
        case .docx: "doc.text.fill"
        case .markdown: "doc.richtext"
        case .other: "doc"
        }
    }

    private var emptyStateTitle: String {
        guard tab.errorMessage == nil else { return "Unable to Generate Preview" }
        return switch tab.kind {
        case .latex: "Preparing LaTeX Preview…"
        case .json: "Preparing JSON Preview…"
        case .pdf: "Preparing PDF Preview…"
        case .docx: "Preparing Word Preview…"
        case .markdown, .other: "Preparing Preview…"
        }
    }

    private var emptyStateMessage: String {
        guard tab.errorMessage == nil else {
            return "Review the details above, fix the problem, and try again."
        }
        return switch tab.kind {
        case .latex: "Compiling the main document with the local LaTeX installation."
        case .json: "Validating and formatting the JSON file."
        case .pdf: "Reading the PDF file."
        case .docx: "Preparing the Word document view."
        case .markdown: "Reading the Markdown file and generating HTML."
        case .other: "Preparing the file."
        }
    }
}

struct PreviewFindBar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: BPTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BPTokens.Color.muted)

            TextField(
                "Find in Document",
                text: Binding(
                    get: { model.findQuery },
                    set: {
                        model.findQuery = $0
                        model.findBackwards = false
                        model.findMatchCount = nil
                    }
                )
            )
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onKeyPress(phases: .down) { keyPress in
                    guard keyPress.key == .return else { return .ignored }
                    if keyPress.modifiers.contains(.shift) {
                        model.findPrevious()
                    } else {
                        model.findNext()
                    }
                    return .handled
                }

            if let matchCount = model.findMatchCount,
               !model.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(matchCount == 1 ? "1 encontrado" : "\(matchCount) encontrados")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .fixedSize()
            }

            ToolbarIconButton(systemName: "chevron.up", help: "Previous Result") {
                model.findPrevious()
            }
            ToolbarIconButton(systemName: "chevron.down", help: "Next Result") {
                model.findNext()
            }
            ToolbarIconButton(systemName: "xmark", help: "Close Search") {
                model.hideFindBar()
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
        .onAppear { isSearchFocused = true }
        .onExitCommand { model.hideFindBar() }
    }
}

struct PreviewErrorBanner: View {
    let message: String
    let showingStalePreview: Bool
    let title: String?
    let onRetry: (() -> Void)?
    @State private var didCopy = false

    init(
        message: String,
        showingStalePreview: Bool,
        title: String? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.showingStalePreview = showingStalePreview
        self.title = title
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            HStack(alignment: .center, spacing: BPTokens.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BPTokens.Color.warning)
                VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                    Text(title ?? (showingStalePreview ? "Error — Showing Last Preview" : "Error Generating Preview"))
                        .font(BPTokens.Typography.caption.weight(.semibold))
                }
                Text(message)
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    didCopy = true
                } label: {
                    Image(systemName: didCopy ? "checkmark.circle" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(didCopy ? "Copied" : "Copy Message")
                Spacer()
                if let onRetry {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BPTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BPTokens.Radius.md)
                .stroke(BPTokens.Color.warning.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
