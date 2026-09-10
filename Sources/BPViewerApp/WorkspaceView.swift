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
    @State private var isHovered = false
    let tab: DocumentTab
    let isActive: Bool
    let isDropTarget: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
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
                .padding(.trailing, 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .opacity(isHovered ? 1 : 0)
            .zIndex(1)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .padding(.horizontal, BPTokens.Spacing.xs)
        .frame(minWidth: 150, minHeight: 36)
        .onHover { isHovered = $0 }
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
    @EnvironmentObject private var model: AppModel
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
                        if model.isFindBarVisible {
                            MarkdownFindBar()
                        }
                        if let errorMessage = tab.errorMessage {
                            PreviewErrorBanner(message: errorMessage, showingStalePreview: tab.isStale)
                        }
                    MarkdownPreviewView(
                        html: html,
                        baseURL: tab.previewBaseURL ?? tab.url.deletingLastPathComponent(),
                        documentID: tab.id,
                        onNavigate: model.openPreviewURL,
                        zoom: model.previewZoom,
                        findQuery: model.findQuery,
                        findRequestID: model.findRequestID,
                        findBackwards: model.findBackwards
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

struct MarkdownFindBar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: BPTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BPTokens.Color.muted)

            TextField("Pesquisar no preview", text: $model.findQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit { model.findNext() }

            ToolbarIconButton(systemName: "chevron.up", help: "Resultado anterior") {
                model.findPrevious()
            }
            ToolbarIconButton(systemName: "chevron.down", help: "Resultado seguinte") {
                model.findNext()
            }
            ToolbarIconButton(systemName: "xmark", help: "Fechar pesquisa") {
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
