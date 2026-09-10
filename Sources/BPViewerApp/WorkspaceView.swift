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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.tabs) { tab in
                    TabItemView(tab: tab, isActive: model.activeTabID == tab.id)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BPTokens.Spacing.xs)
        }
        .frame(height: 38)
        .background(BPTokens.Color.surface)
    }
}

struct TabItemView: View {
    @EnvironmentObject private var model: AppModel
    let tab: DocumentTab
    let isActive: Bool

    var body: some View {
        HStack(spacing: BPTokens.Spacing.xs) {
            Button {
                model.selectTab(id: tab.id)
            } label: {
                HStack(spacing: BPTokens.Spacing.xs) {
                    Image(systemName: tab.kind == .latex ? "doc.text" : "doc.richtext")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tab.title)
                            .lineLimit(1)
                        if tab.subtitle != tab.title {
                            Text(tab.subtitle)
                                .font(BPTokens.Typography.caption)
                                .foregroundStyle(BPTokens.Color.muted)
                        }
                    }
                    Spacer(minLength: BPTokens.Spacing.xs)
                    StatusBadge(status: tab.status)
                }
                .font(BPTokens.Typography.caption)
                .padding(.leading, BPTokens.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            ToolbarIconButton(systemName: "xmark", help: "Fechar tab") {
                model.closeTab(tab)
            }
            .frame(width: 20)
        }
        .padding(.horizontal, BPTokens.Spacing.xs)
        .frame(minWidth: 150, minHeight: 36)
        .background(isActive ? BPTokens.Color.selection : .clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contextMenu {
            Button("Fechar tab") { model.closeTab(tab) }
            Button("Fechar as outras") { model.closeOtherTabs(keeping: tab) }
            Button("Fechar as tabs à direita") { model.closeTabsToRight(of: tab) }
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
                    title: "Nenhum documento selecionado",
                    message: model.rootURL == nil
                        ? "Abre uma pasta e escolhe um ficheiro Markdown ou LaTeX."
                        : "Escolhe um ficheiro na árvore para abrir uma tab."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PreviewPane: View {
    let tab: DocumentTab

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                    Text(tab.title)
                        .font(.title2.weight(.semibold))
                    Text(tab.url.path)
                        .font(BPTokens.Typography.caption)
                        .foregroundStyle(BPTokens.Color.muted)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(status: tab.status)
            }
            .padding(.horizontal, BPTokens.Spacing.lg)
            .padding(.vertical, BPTokens.Spacing.md)

            Divider()

            Group {
                if tab.kind == .markdown, let html = tab.previewHTML {
                    VStack(spacing: 0) {
                        if let errorMessage = tab.errorMessage {
                            PreviewErrorBanner(message: errorMessage, showingStalePreview: tab.isStale)
                        }
                        MarkdownPreviewView(
                            html: html,
                            baseURL: tab.previewBaseURL ?? tab.url.deletingLastPathComponent()
                        )
                    }
                } else {
                    EmptyStateView(
                        systemImage: tab.kind == .latex ? "doc.text.image" : "doc.richtext",
                        title: tab.kind == .latex ? "Adapter LaTeX pendente" : tab.status == .failed ? "Não foi possível gerar o preview" : "A preparar preview…",
                        message: tab.errorMessage ?? (tab.kind == .latex
                            ? "O shell está pronto. A compilação LaTeX será ligada no próximo vertical slice."
                            : "A ler o ficheiro Markdown e a gerar HTML.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BPTokens.Color.canvas)
    }
}

struct PreviewErrorBanner: View {
    let message: String
    let showingStalePreview: Bool

    var body: some View {
        HStack(alignment: .top, spacing: BPTokens.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BPTokens.Color.warning)
            VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                Text(showingStalePreview ? "Erro — a mostrar o último preview" : "Erro ao gerar preview")
                    .font(BPTokens.Typography.caption.weight(.semibold))
                Text(message)
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, BPTokens.Spacing.lg)
        .padding(.vertical, BPTokens.Spacing.sm)
        .background(BPTokens.Color.warning.opacity(0.10))
    }
}
