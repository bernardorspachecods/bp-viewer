import BPViewerCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()
            Divider()
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView()
                        .frame(width: model.sidebarWidth)
                    SidebarResizeHandle()
                }

                DocumentWorkspaceView()
            }
        }
        .background(BPTokens.Color.canvas)
        .preferredColorScheme(model.theme.colorScheme)
        .frame(minWidth: 900, minHeight: 600)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            for provider in providers {
                let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        model.openDroppedURLs([url])
                    }
                }
            }
            return !providers.isEmpty
        }
        .alert("Trocar pasta aberta?", isPresented: $model.showingRootChangeConfirmation) {
            Button("Cancelar", role: .cancel, action: model.cancelRootChange)
            Button("Trocar", role: .destructive, action: model.confirmRootChange)
        } message: {
            Text("As tabs atuais serão fechadas e a nova pasta passará a ser a raiz do projeto.")
        }
        .sheet(item: $model.pendingLatexRootSelection) { request in
            LatexRootSelectionView(request: request)
                .environmentObject(model)
        }
        .sheet(item: $model.pendingLatexExternalDependencies) { request in
            LatexExternalDependencyView(request: request)
                .environmentObject(model)
        }
    }
}

struct LatexRootSelectionView: View {
    @EnvironmentObject private var model: AppModel
    let request: LatexRootSelectionRequest
    @State private var selectedRoot: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                Text("Escolher documento principal LaTeX")
                    .font(.title2.weight(.semibold))
                Text(
                    request.candidates.isEmpty
                        ? "Não foi possível identificar automaticamente o documento principal. A escolha manual fica guardada para as próximas compilações."
                        : "Foram encontrados vários documentos principais neste projeto. A escolha fica guardada para as próximas compilações."
                )
                    .font(BPTokens.Typography.body)
                    .foregroundStyle(BPTokens.Color.muted)
            }

            if request.candidates.isEmpty {
                VStack(alignment: .leading, spacing: BPTokens.Spacing.sm) {
                    Text("Não foi encontrado automaticamente nenhum documento principal nesta pasta.")
                        .font(BPTokens.Typography.body)
                        .foregroundStyle(BPTokens.Color.muted)
                    Button("Escolher ficheiro principal…") {
                        model.chooseLatexRootFile()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: BPTokens.Spacing.xs) {
                        ForEach(request.candidates, id: \.url) { candidate in
                            Button {
                                selectedRoot = candidate.url
                            } label: {
                                HStack(spacing: BPTokens.Spacing.sm) {
                                    Image(systemName: selectedRoot == candidate.url ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedRoot == candidate.url ? Color.accentColor : BPTokens.Color.muted)
                                    VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                                        Text(candidate.url.lastPathComponent)
                                            .font(BPTokens.Typography.body.weight(.medium))
                                        Text(relativePath(candidate.url))
                                            .font(BPTokens.Typography.caption)
                                            .foregroundStyle(BPTokens.Color.muted)
                                    }
                                    Spacer()
                                }
                                .padding(BPTokens.Spacing.sm)
                                .background(
                                    selectedRoot == candidate.url
                                        ? BPTokens.Color.selection
                                        : BPTokens.Color.surface
                                )
                                .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    model.cancelLatexRootSelection()
                }
                Button("Escolher") {
                    guard let selectedRoot else { return }
                    model.chooseLatexRoot(selectedRoot)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRoot == nil || request.candidates.isEmpty)
            }
        }
        .padding(BPTokens.Spacing.lg)
        .frame(width: 560, height: 390)
        .onAppear {
            selectedRoot = request.candidates.first?.url
        }
    }

    private func relativePath(_ url: URL) -> String {
        let rootPath = request.projectRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath ? "." : String(path.dropFirst(rootPath.count + 1))
    }
}

struct LatexExternalDependencyView: View {
    @EnvironmentObject private var model: AppModel
    let request: LatexExternalDependencyRequest

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                Text("Confirmar dependências externas")
                    .font(.title2.weight(.semibold))
                Text("O documento principal referencia ficheiros fora da pasta do projeto. A compilação só continuará depois desta confirmação.")
                    .font(BPTokens.Typography.body)
                    .foregroundStyle(BPTokens.Color.muted)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
                    ForEach(request.dependencies, id: \.url) { dependency in
                        VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
                            Text(dependency.url.path)
                                .font(BPTokens.Typography.code)
                                .textSelection(.enabled)
                            Text("Referenciado por \(dependency.sourceURL.lastPathComponent)")
                                .font(BPTokens.Typography.caption)
                                .foregroundStyle(BPTokens.Color.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BPTokens.Spacing.sm)
                        .background(BPTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    model.cancelLatexExternalDependencies()
                }
                Button("Permitir e compilar") {
                    model.approveLatexExternalDependencies()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(BPTokens.Spacing.lg)
        .frame(width: 620, height: 390)
    }
}

struct SidebarResizeHandle: View {
    @EnvironmentObject private var model: AppModel
    @State private var initialWidth: Double?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.45) : BPTokens.Color.separator)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if initialWidth == nil {
                            initialWidth = model.sidebarWidth
                        }
                        guard let initialWidth else { return }
                        model.resizeSidebar(to: initialWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        model.setSidebarWidth(model.sidebarWidth)
                        initialWidth = nil
                    }
            )
            .help("Redimensionar sidebar")
    }
}

struct TopBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            ToolbarIconButton(systemName: "folder", help: "Abrir pasta") {
                model.openFolder()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.rootURL?.lastPathComponent ?? "bp-viewer")
                    .font(BPTokens.Typography.title)
                Text(model.rootURL?.path ?? "Nenhuma pasta aberta")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .lineLimit(1)
            }

            Spacer()

            if let activeTab = model.activeTab {
                StatusBadge(status: activeTab.status)
            }

            if model.activeTab?.kind == .markdown || model.activeTab?.kind == .latex {
                if model.activeTab?.kind == .latex {
                    ToolbarIconButton(systemName: "list.bullet.rectangle", help: "Escolher documento principal LaTeX") {
                        model.changeLatexRoot()
                    }
                    Menu {
                        Picker("Shell escape", selection: Binding(
                            get: { model.latexShellEscapeMode },
                            set: { model.setLatexShellEscapeMode($0) }
                        )) {
                            ForEach(LatexShellEscapeMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: BPTokens.Size.control, height: BPTokens.Size.control)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Configuração avançada LaTeX")
                }
                ToolbarIconButton(systemName: "magnifyingglass", help: "Pesquisar no preview") {
                    model.showFindBar()
                }
                ToolbarIconButton(systemName: "minus.magnifyingglass", help: "Diminuir zoom") {
                    model.zoomOut()
                }
                Button("\(Int(model.previewZoom * 100))%", action: model.resetPreviewZoom)
                    .buttonStyle(.plain)
                    .font(BPTokens.Typography.caption)
                    .frame(minWidth: 42)
                    .help("Repor zoom")
                ToolbarIconButton(systemName: "plus.magnifyingglass", help: "Aumentar zoom") {
                    model.zoomIn()
                }
            }

            ToolbarIconButton(systemName: "arrow.clockwise", help: "Atualizar preview") {
                model.refreshActiveTab()
            }

            ToolbarIconButton(systemName: model.theme == .dark ? "sun.max" : "moon", help: "Alternar tema") {
                model.cycleTheme()
            }

            ToolbarIconButton(
                systemName: model.sidebarVisible ? "sidebar.left" : "sidebar.right",
                help: model.sidebarVisible ? "Esconder sidebar" : "Mostrar sidebar"
            ) {
                model.setSidebarVisible(!model.sidebarVisible)
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .frame(height: BPTokens.Size.toolbar)
        .background(BPTokens.Color.surface)
    }
}
