import AppKit
import SwiftUI
import BPViewerCore

struct DocumentOutlineItem: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int
    let isSelectable: Bool
}

struct DocumentOutlineToolbar: View {
    let isVisible: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            DocumentEditModeButton(
                title: "Outline",
                systemImage: "list.bullet.rectangle",
                isActive: isVisible,
                action: onToggle
            )
            Spacer()
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
        Divider()
    }
}

struct DocumentInteractionToolbar: View {
    let isOutlineAvailable: Bool
    let isOutlineVisible: Bool
    let onToggleOutline: () -> Void
    let editingSession: MarkdownEditSession?
    let presentationMode: DocumentPresentationMode
    let supportsSplitView: Bool
    let onToggleSplitView: (() -> Void)?
    let diffSession: DocumentDiffSession?
    let onToggleDiff: (DocumentDiffMode) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onDiscardEditing: () -> Void
    let onSave: () -> Void

    private var hasEditingChanges: Bool {
        guard let editingSession else { return false }
        return editingSession.currentSource != editingSession.baseSource
            || editingSession.saveState != .saved
    }

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            HStack(spacing: BPTokens.Spacing.sm) {
                if isOutlineAvailable {
                    DocumentEditModeButton(
                        title: "Outline",
                        systemImage: "list.bullet.rectangle",
                        isActive: isOutlineVisible,
                        action: onToggleOutline
                    )
                }

                if supportsSplitView, let onToggleSplitView {
                    DocumentEditModeButton(
                        title: "Split View",
                        systemImage: "rectangle.split.2x1",
                        isActive: presentationMode == .split,
                        action: onToggleSplitView
                    )
                }

                DocumentEditModeButton(
                    title: "Disk Diff",
                    systemImage: "externaldrive",
                    isActive: presentationMode == .diff(.savedOnDisk),
                    action: { onToggleDiff(.savedOnDisk) }
                )

                DocumentEditModeButton(
                    title: "Git Diff",
                    systemImage: "arrow.triangle.branch",
                    isActive: presentationMode == .diff(.gitHead),
                    action: { onToggleDiff(.gitHead) }
                )
            }

            Spacer()

            if let editingSession {
                if hasEditingChanges {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(editingSession.undoSources.isEmpty)

                    Button(action: onRedo) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(editingSession.redoSources.isEmpty)
                }

                DocumentEditActionBar(
                    saveState: editingSession.saveState,
                    onDiscard: onDiscardEditing,
                    onSave: onSave
                )
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }
}

struct DocumentOutlineSidebar: View {
    let entries: [DocumentOutlineItem]
    let selectedID: String?
    let onSelect: (DocumentOutlineItem) -> Void
    let fixedWidth: CGFloat?

    init(
        entries: [DocumentOutlineItem],
        selectedID: String?,
        fixedWidth: CGFloat? = nil,
        onSelect: @escaping (DocumentOutlineItem) -> Void
    ) {
        self.entries = entries
        self.selectedID = selectedID
        self.fixedWidth = fixedWidth
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            if let fixedWidth {
                outlineList.frame(width: fixedWidth)
            } else {
                outlineList
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            }
        }
        .background(BPTokens.Color.surface)
    }

    private var outlineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(spacing: 0) {
                            Text(entry.title)
                                .font(
                                    entry.level == 0
                                        ? BPTokens.Typography.body.weight(.semibold)
                                        : BPTokens.Typography.caption
                                )
                                .foregroundStyle(
                                    selectedID == entry.id
                                        ? Color.primary
                                        : entry.level == 0
                                            ? Color.primary.opacity(0.9)
                                            : BPTokens.Color.muted
                                )
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(
                            .leading,
                            BPTokens.Spacing.md
                                + CGFloat(max(entry.level, 0)) * BPTokens.Spacing.md
                        )
                        .padding(.trailing, BPTokens.Spacing.sm)
                        .padding(.vertical, BPTokens.Spacing.xxs + 2)
                        .frame(minHeight: BPTokens.Size.row)
                        .background(
                            RoundedRectangle(cornerRadius: BPTokens.Radius.sm)
                                .fill(
                                    selectedID == entry.id
                                        ? Color.primary.opacity(0.12)
                                        : .clear
                                )
                        )
                        .overlay(alignment: .leading) {
                            OutlineGuides(
                                level: max(entry.level, 0),
                                isSelected: selectedID == entry.id
                            )
                            .padding(.leading, BPTokens.Spacing.sm)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("Copy Title", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.title, forType: .string)
                        }
                    }
                    .disabled(!entry.isSelectable)
                }
            }
            .padding(.horizontal, BPTokens.Spacing.xxs)
            .padding(.vertical, BPTokens.Spacing.xs)
        }
    }
}

private struct OutlineGuides: View {
    let level: Int
    let isSelected: Bool

    var body: some View {
        Canvas { context, size in
            guard level > 0 else { return }

            var guides = Path()
            let baseX = BPTokens.Spacing.xs
            let step = BPTokens.Spacing.md

            for depth in 0..<level {
                let x = baseX + CGFloat(depth) * step
                guides.move(to: CGPoint(x: x, y: 0))
                guides.addLine(to: CGPoint(x: x, y: size.height))
            }

            let connectorX = baseX + CGFloat(level - 1) * step
            guides.move(to: CGPoint(x: connectorX, y: size.height / 2))
            guides.addLine(to: CGPoint(x: connectorX + step * 0.5, y: size.height / 2))

            context.stroke(
                guides,
                with: .color(
                    isSelected
                        ? Color.primary.opacity(0.42)
                        : BPTokens.Color.separator.opacity(0.85)
                ),
                style: StrokeStyle(lineWidth: 1, lineCap: .square)
            )
        }
        .frame(width: BPTokens.Spacing.md * CGFloat(max(level, 1)))
        .allowsHitTesting(false)
    }
}

struct ResizableDocumentOutlineView: View {
    let isVisible: Bool
    let width: Double
    let entries: [DocumentOutlineItem]
    let selectedID: String?
    let onSelect: (DocumentOutlineItem) -> Void
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    @State private var liveWidth: Double?

    private var displayedWidth: Double {
        liveWidth ?? DocumentOutlineSizing.clamped(width)
    }

    var body: some View {
        HStack(spacing: 0) {
            DocumentOutlineSidebar(
                entries: entries,
                selectedID: selectedID,
                fixedWidth: displayedWidth,
                onSelect: onSelect
            )
            SidebarResizeHandle(
                width: displayedWidth,
                onChanged: { resizedWidth in
                    liveWidth = resizedWidth
                    onChanged(resizedWidth)
                },
                onEnded: { resizedWidth in
                    onEnded(resizedWidth)
                    liveWidth = nil
                }
            )
        }
        .frame(width: isVisible ? displayedWidth + 5 : 0)
        .frame(maxHeight: .infinity, alignment: .leading)
        .clipped()
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}
