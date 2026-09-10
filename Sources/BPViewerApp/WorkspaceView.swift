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
                model.activeTabID = tab.id
                model.persistState()
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
                }
                .font(BPTokens.Typography.caption)
                .padding(.leading, BPTokens.Spacing.xs)
            }
            .buttonStyle(.plain)

            StatusBadge(status: tab.status)
                .scaleEffect(0.8)

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
        VStack(spacing: BPTokens.Spacing.lg) {
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

            VStack(spacing: BPTokens.Spacing.md) {
                Image(systemName: tab.kind == .latex ? "doc.text.image" : "doc.richtext")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Preview placeholder")
                    .font(BPTokens.Typography.title)
                Text("A superfície está pronta para receber o adapter de \(tab.kind.label), sem alterar a arquitetura da janela.")
                    .font(BPTokens.Typography.body)
                    .foregroundStyle(BPTokens.Color.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(BPTokens.Spacing.lg)
        .background(BPTokens.Color.canvas)
    }
}
