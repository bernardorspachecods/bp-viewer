import SwiftUI

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
                    Divider()
                }

                DocumentWorkspaceView()
            }
        }
        .background(BPTokens.Color.canvas)
        .preferredColorScheme(model.theme.colorScheme)
        .frame(minWidth: 900, minHeight: 600)
        .alert("Trocar pasta aberta?", isPresented: $model.showingRootChangeConfirmation) {
            Button("Cancelar", role: .cancel, action: model.cancelRootChange)
            Button("Trocar", role: .destructive, action: model.confirmRootChange)
        } message: {
            Text("As tabs atuais serão fechadas e a nova pasta passará a ser a raiz do projeto.")
        }
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
