import BPViewerCore
import SwiftUI

struct DocumentEditActionBar: View {
    let saveState: MarkdownSaveState
    let onDiscard: () -> Void
    let onSave: () -> Void

    var showsStatus: Bool {
        saveState != .saved
    }

    var showsDiscardChanges: Bool {
        saveState != .saved
    }

    var isSaveDisabled: Bool {
        saveState == .saved
    }

    var saveButtonOpacity: Double {
        isSaveDisabled ? 0.55 : 1
    }

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            if showsStatus {
                Text(saveState.label)
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(saveState == .conflict ? BPTokens.Color.warning : BPTokens.Color.muted)
            }

            if showsDiscardChanges {
                Button("Discard Changes", role: .destructive, action: onDiscard)
                    .buttonStyle(.bordered)
            }

            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .tint(isSaveDisabled ? BPTokens.Color.muted : .accentColor)
                .opacity(saveButtonOpacity)
                .disabled(isSaveDisabled)
        }
    }
}

struct DocumentEditModeButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(BPTokens.Typography.caption)
                .foregroundStyle(isActive ? Color.primary : BPTokens.Color.muted)
                .padding(.horizontal, BPTokens.Spacing.sm)
                .padding(.vertical, BPTokens.Spacing.xs)
                .frame(minHeight: BPTokens.Size.iconHitTarget)
                .background {
                    RoundedRectangle(cornerRadius: BPTokens.Radius.sm)
                        .fill(isActive ? Color.primary.opacity(0.08) : .clear)
                        .padding(.horizontal, BPTokens.Spacing.xxs)
                        .padding(.vertical, BPTokens.Spacing.xs - BPTokens.Spacing.xxs)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityValue(isActive ? "Active" : "Inactive")
    }
}
