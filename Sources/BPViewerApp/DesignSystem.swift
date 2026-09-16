import AppKit
import BPViewerCore
import SwiftUI

enum PreviewCanvasStyle {
    static let backgroundColor = NSColor.windowBackgroundColor
}

enum BPTokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    enum Size {
        static let toolbar: CGFloat = 44
        static let row: CGFloat = 28
        static let control: CGFloat = 28
        static let sidebarMin: CGFloat = 220
        static let sidebarMax: CGFloat = 480
    }

    enum Color {
        static let canvas = SwiftUI.Color(nsColor: PreviewCanvasStyle.backgroundColor)
        static let surface = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let elevated = SwiftUI.Color(nsColor: .textBackgroundColor)
        static let separator = SwiftUI.Color(nsColor: .separatorColor)
        static let muted = SwiftUI.Color.secondary
        static let selection = SwiftUI.Color.accentColor.opacity(0.14)
        static let warning = SwiftUI.Color.orange
        static let danger = SwiftUI.Color.red
        static let success = SwiftUI.Color.green
    }

    enum Typography {
        static let title = Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let code = Font.system(.caption, design: .monospaced)
    }
}

struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(BPTokens.Color.muted)
                .frame(width: BPTokens.Size.control, height: BPTokens.Size.control)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(Rectangle())
        .help(help)
    }
}

struct CopyTextButton: View {
    let text: String
    let isVisible: Bool
    let helpText: String
    let onCopy: (String) -> Void
    @State private var didCopy = false

    init(
        text: String,
        isVisible: Bool = true,
        helpText: String = "Copiar texto",
        onCopy: @escaping (String) -> Void
    ) {
        self.text = text
        self.isVisible = isVisible
        self.helpText = helpText
        self.onCopy = onCopy
    }

    var body: some View {
        Button {
            onCopy(text)
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .frame(width: BPTokens.Size.control, height: BPTokens.Size.control)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .help(didCopy ? "Texto copiado" : helpText)
    }
}

struct StatusBadge: View {
    let status: PreviewStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(BPTokens.Typography.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, BPTokens.Spacing.xs)
            .padding(.vertical, BPTokens.Spacing.xxs)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: BPTokens.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(BPTokens.Color.muted)

            VStack(spacing: BPTokens.Spacing.xs) {
                Text(title)
                    .font(BPTokens.Typography.title)
                Text(message)
                    .font(BPTokens.Typography.body)
                    .foregroundStyle(BPTokens.Color.muted)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(BPTokens.Spacing.xl)
        .frame(maxWidth: 440)
    }
}
