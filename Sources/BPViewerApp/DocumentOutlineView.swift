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
    let onSnapshot: (() -> Void)?

    init(
        isVisible: Bool,
        onToggle: @escaping () -> Void,
        onSnapshot: (() -> Void)? = nil
    ) {
        self.isVisible = isVisible
        self.onToggle = onToggle
        self.onSnapshot = onSnapshot
    }

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Label(
                    isVisible ? "Hide Outline" : "Show Outline",
                    systemImage: "list.bullet.rectangle"
                )
            }
            .buttonStyle(.borderless)
            Spacer()
            if let onSnapshot {
                Button(action: onSnapshot) {
                    Image(systemName: "camera.viewfinder")
                        .font(BPTokens.Typography.body)
                        .foregroundStyle(BPTokens.Color.muted)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .contentShape(Rectangle())
                .help("Create Preview Snapshot")
            }
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
    let onSnapshot: (() -> Void)?
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
                    Button(action: onToggleOutline) {
                        Label(
                            isOutlineVisible ? "Hide Outline" : "Show Outline",
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                    .buttonStyle(.borderless)
                }

                if let onSnapshot {
                    Button(action: onSnapshot) {
                        Image(systemName: "camera.viewfinder")
                            .font(BPTokens.Typography.body)
                            .foregroundStyle(BPTokens.Color.muted)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Capture")
                    .help("Create Preview Snapshot")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(spacing: BPTokens.Spacing.xs) {
                            Image(systemName: "list.bullet.indent")
                                .foregroundStyle(BPTokens.Color.muted)
                            Text(entry.title)
                                .font(BPTokens.Typography.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(
                            .leading,
                            BPTokens.Spacing.sm
                                + CGFloat(max(entry.level, 0)) * BPTokens.Spacing.md
                        )
                        .padding(.trailing, BPTokens.Spacing.xs)
                        .padding(.vertical, BPTokens.Spacing.xs)
                        .background(selectedID == entry.id ? BPTokens.Color.selection : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!entry.isSelectable)
                }
            }
            .padding(.vertical, BPTokens.Spacing.xs)
        }
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
        .background(BPTokens.Color.surface)
    }
}
