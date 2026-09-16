import SwiftUI

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
