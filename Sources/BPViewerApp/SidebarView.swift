import BPViewerCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Ficheiros", systemImage: "folder.fill")
                    .font(BPTokens.Typography.title)
                Spacer()
                if model.isScanningTree || model.isFilteringTree {
                    ProgressView()
                        .controlSize(.small)
                        .help(model.isScanningTree ? "A indexar a pasta…" : "A pesquisar ficheiros…")
                }
                Text(model.nodes.count, format: .number)
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
            }
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.top, BPTokens.Spacing.md)
            .padding(.bottom, BPTokens.Spacing.sm)

            TextField("Pesquisar ficheiros", text: Binding(
                get: { model.treeQuery },
                set: { model.updateTreeQuery($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.bottom, BPTokens.Spacing.sm)

            Toggle("Apenas Markdown e LaTeX", isOn: Binding(
                get: { model.compatibleOnly },
                set: { model.updateCompatibleOnly($0) }
            ))
            .font(BPTokens.Typography.caption)
            .toggleStyle(.checkbox)
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.bottom, BPTokens.Spacing.sm)

            Divider()

            if model.rootURL == nil {
                EmptyStateView(
                    systemImage: "folder",
                    title: "Nenhuma pasta aberta",
                    message: "Abre a pasta da tese para começar.",
                    actionTitle: "Abrir pasta",
                    action: model.openFolder
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isScanningTree && model.nodes.isEmpty {
                VStack(spacing: BPTokens.Spacing.sm) {
                    ProgressView()
                    Text("A indexar a pasta…")
                        .font(BPTokens.Typography.caption)
                        .foregroundStyle(BPTokens.Color.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.nodes) { node in
                            FileTreeRow(node: node, level: 0)
                        }
                    }
                    .padding(.vertical, BPTokens.Spacing.xs)
                }
            }
        }
        .background(BPTokens.Color.surface)
    }
}

struct FileTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode
    let level: Int

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    model.toggleExpanded(node.id)
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)

                if model.expandedPaths.contains(node.id) {
                    if node.childrenLoaded {
                        ForEach(node.children) { child in
                            FileTreeRow(node: child, level: level + 1)
                        }
                    } else {
                        HStack(spacing: BPTokens.Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("A carregar…")
                                .font(BPTokens.Typography.caption)
                                .foregroundStyle(BPTokens.Color.muted)
                        }
                        .padding(.leading, BPTokens.Spacing.sm + CGFloat(level + 1) * BPTokens.Spacing.md)
                        .frame(minHeight: BPTokens.Size.row)
                        .overlay(alignment: .leading) {
                            TreeGuides(level: level + 1)
                        }
                    }
                }
            }
        } else {
            Button {
                model.open(node)
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: BPTokens.Spacing.xs) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(node.title)
                .font(BPTokens.Typography.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, BPTokens.Spacing.sm + CGFloat(level) * BPTokens.Spacing.md)
        .padding(.trailing, BPTokens.Spacing.sm)
        .frame(minHeight: BPTokens.Size.row)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            TreeGuides(level: level)
        }
    }

    private var iconName: String {
        if node.isDirectory {
            return model.expandedPaths.contains(node.id) ? "folder.fill" : "folder"
        }
        switch node.kind {
        case .markdown: return "doc.richtext"
        case .latex: return "doc.text"
        case .other: return "doc"
        }
    }

    private var iconColor: Color {
        switch node.kind {
        case .markdown: .blue
        case .latex: .orange
        case .other: BPTokens.Color.muted
        }
    }
}

struct TreeGuides: View {
    let level: Int

    var body: some View {
        Canvas { context, size in
            guard level > 0 else { return }

            var path = Path()
            let baseX = BPTokens.Spacing.sm + BPTokens.Spacing.md / 2

            for depth in 0..<level {
                let x = baseX + CGFloat(depth) * BPTokens.Spacing.md
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            let connectorX = baseX + CGFloat(level - 1) * BPTokens.Spacing.md
            path.move(to: CGPoint(x: connectorX, y: size.height / 2))
            path.addLine(to: CGPoint(x: connectorX + BPTokens.Spacing.md / 2, y: size.height / 2))

            context.stroke(
                path,
                with: .color(BPTokens.Color.separator.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1, lineCap: .square)
            )
        }
        .allowsHitTesting(false)
    }
}
