import BPViewerCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var highlightedSearchNodeIDs: Set<String> = []

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

            Toggle("Apenas ficheiros suportados", isOn: Binding(
                get: { model.compatibleOnly },
                set: { model.updateCompatibleOnly($0) }
            ))
            .font(BPTokens.Typography.caption)
            .toggleStyle(.checkbox)
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.bottom, BPTokens.Spacing.sm)

            TextField("Pesquisar ficheiros", text: Binding(
                get: { model.treeQuery },
                set: { model.updateTreeQuery($0) }
            ))
            .textFieldStyle(.roundedBorder)
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.nodes) { node in
                                FileTreeRow(
                                    node: node,
                                    level: 0,
                                    highlightedNodeIDs: highlightedSearchNodeIDs
                                )
                                .id(node.id)
                            }
                        }
                        .padding(.vertical, BPTokens.Spacing.xs)
                    }
                    .onChange(of: model.treeQuery) { _, _ in
                        focusSearchResult(using: proxy)
                    }
                    .onChange(of: model.nodes.map(\.id)) { _, _ in
                        focusSearchResult(using: proxy)
                    }
                    .onAppear {
                        focusSearchResult(using: proxy)
                    }
                }
            }
        }
        .background(BPTokens.Color.surface)
    }

    private func focusSearchResult(using proxy: ScrollViewProxy) {
        let normalizedQuery = model.treeQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            highlightedSearchNodeIDs = []
            return
        }

        let matches = model.nodes.filter { node in
            node.isDirectory
                && (node.title.lowercased().contains(normalizedQuery)
                    || node.relativePath.lowercased().contains(normalizedQuery))
        }
        guard let firstMatch = matches.first else {
            highlightedSearchNodeIDs = []
            return
        }

        highlightedSearchNodeIDs = Set(matches.map(\.id))
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(firstMatch.id, anchor: .center)
            }
        }
    }
}

struct FileTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode
    let level: Int
    let highlightedNodeIDs: Set<String>

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 0) {
                rowButton

                if model.expandedPaths.contains(node.id) {
                    if node.childrenLoaded {
                        ForEach(node.children) { child in
                            FileTreeRow(
                                node: child,
                                level: level + 1,
                                highlightedNodeIDs: highlightedNodeIDs
                            )
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
            rowButton
        }
    }

    private var rowButton: some View {
        Button {
            model.open(node)
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copiar path") { model.copyPath(node.url) }
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
        .background(highlightedNodeIDs.contains(node.id) ? BPTokens.Color.selection : .clear)
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
        case .json: return "curlybraces"
        case .docx: return "doc.text.fill"
        case .pdf: return "doc.fill"
        case .other: return "doc"
        }
    }

    private var iconColor: Color {
        switch node.kind {
        case .markdown: .blue
        case .latex: .orange
        case .json: .yellow
        case .docx: .purple
        case .pdf: .red
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
