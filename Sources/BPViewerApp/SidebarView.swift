import BPViewerCore
import SwiftUI

struct CollapseFoldersButton: View {
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .frame(width: 22, height: 22)
                .iconButtonHitArea()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(helpText)
    }
}

struct SidebarTreeItem: Identifiable {
    let id: String
    let node: FileNode?
    let level: Int

    init(node: FileNode, level: Int) {
        id = node.id
        self.node = node
        self.level = level
    }

    init(loadingFor node: FileNode, level: Int) {
        id = node.id + "/loading"
        self.node = nil
        self.level = level
    }

    static func flatten(
        nodes: [FileNode],
        expandedPaths: Set<String>
    ) -> [SidebarTreeItem] {
        var result: [SidebarTreeItem] = []

        func append(_ nodes: [FileNode], level: Int) {
            for node in nodes {
                result.append(SidebarTreeItem(node: node, level: level))
                guard node.isDirectory,
                      expandedPaths.contains(node.id) else { continue }

                if node.childrenLoaded {
                    append(node.children, level: level + 1)
                } else {
                    result.append(SidebarTreeItem(loadingFor: node, level: level + 1))
                }
            }
        }

        append(nodes, level: 0)
        return result
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var highlightedSearchNodeIDs: Set<String> = []
    @State private var highlightedRevealNodeID: String?
    @State private var isRootDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BPTokens.Spacing.xs) {
                Toggle(isOn: Binding(
                    get: { model.compatibleOnly },
                    set: { model.updateCompatibleOnly($0) }
                )) {
                    Text("Supported files only")
                        .padding(.leading, BPTokens.Spacing.xxs)
                }
                .font(BPTokens.Typography.caption)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .tint(BPTokens.Color.muted)

                Spacer(minLength: 0)

                CollapseFoldersButton(
                    helpText: "Close all folders",
                    action: model.collapseAllFolders
                )
                .opacity(model.expandedPaths.isEmpty ? 0 : 1)
                .allowsHitTesting(!model.expandedPaths.isEmpty)
                .accessibilityHidden(model.expandedPaths.isEmpty)
                if model.isScanningTree || model.isFilteringTree || model.isPerformingFileOperation {
                    ProgressView()
                        .controlSize(.small)
                        .help(
                            model.isPerformingFileOperation
                                ? "Copying file…"
                                : model.isScanningTree
                                    ? "Indexing folder…"
                                : "Searching files…"
                        )
                }
            }
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.top, BPTokens.Spacing.xs)
            .padding(.bottom, BPTokens.Spacing.xs)

            TextField("Search files", text: Binding(
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
                    title: "No Folder Open",
                    message: "Open the thesis folder to get started.",
                    actionTitle: "Open Folder",
                    action: model.openFolder
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isScanningTree && model.nodes.isEmpty {
                VStack(spacing: BPTokens.Spacing.sm) {
                    ProgressView()
                    Text("Indexing folder…")
                        .font(BPTokens.Typography.caption)
                        .foregroundStyle(BPTokens.Color.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(
                                    SidebarTreeItem.flatten(
                                        nodes: model.nodes,
                                        expandedPaths: model.expandedPaths
                                    )
                                ) { item in
                                    if let node = item.node {
                                        FileTreeRow(
                                            node: node,
                                            level: item.level,
                                            highlightedNodeIDs: activeHighlightedNodeIDs
                                        )
                                    } else {
                                        TreeLoadingRow(level: item.level)
                                    }
                                }
                            }
                            .padding(.vertical, BPTokens.Spacing.xs)
                        }
                        .onChange(of: model.treeQuery) { _, _ in
                            focusSearchResult(using: proxy)
                        }
                        .onChange(of: model.nodes) { _, _ in
                            focusSearchResult(using: proxy)
                            revealTreeTarget(using: proxy)
                        }
                        .onChange(of: model.treeRevealTargetID) { _, _ in
                            revealTreeTarget(using: proxy)
                        }
                        .onAppear {
                            focusSearchResult(using: proxy)
                            revealTreeTarget(using: proxy)
                        }
                    }

                    HStack(spacing: 0) {
                        rootDropZone
                        Spacer(minLength: 0)
                        rootDropZone
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(BPTokens.Color.surface)
    }

    private func revealTreeTarget(using proxy: ScrollViewProxy) {
        guard let targetID = model.treeRevealTargetID else { return }
        let visibleIDs = SidebarTreeItem.flatten(
            nodes: model.nodes,
            expandedPaths: model.expandedPaths
        ).map(\.id)
        guard visibleIDs.contains(targetID) else { return }

        highlightedRevealNodeID = targetID
        DispatchQueue.main.async {
            proxy.scrollTo(targetID, anchor: .center)
            model.clearTreeRevealTarget()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if highlightedRevealNodeID == targetID {
                    highlightedRevealNodeID = nil
                }
            }
        }
    }

    private var activeHighlightedNodeIDs: Set<String> {
        var IDs = highlightedSearchNodeIDs
        if let highlightedRevealNodeID {
            IDs.insert(highlightedRevealNodeID)
        }
        return IDs
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

    private var rootDropZone: some View {
        Color.accentColor.opacity(isRootDropTarget ? 0.16 : 0)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let rootURL = model.rootURL else {
                    isRootDropTarget = false
                    return false
                }
                let didMove = items.reduce(false) { movedAny, path in
                    model.moveFile(
                        at: URL(fileURLWithPath: path),
                        to: rootURL
                    ) || movedAny
                }
                isRootDropTarget = false
                return didMove
            } isTargeted: { isTargeted in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isRootDropTarget = isTargeted
                }
            }
    }
}

struct FileTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode
    let level: Int
    let highlightedNodeIDs: Set<String>
    @State private var isDropTarget = false
    @State private var isHovering = false

    var body: some View {
        rowButton
    }

    @ViewBuilder
    private var rowButton: some View {
        if node.isDirectory {
            baseRow
                .draggable(node.url.path) {
                    Label(node.title, systemImage: iconName)
                        .padding(.horizontal, BPTokens.Spacing.sm)
                        .padding(.vertical, BPTokens.Spacing.xs)
                        .background(BPTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
                }
                .dropDestination(for: String.self) { items, _ in
                    let didMove = items.reduce(false) { movedAny, path in
                        model.moveFile(
                            at: URL(fileURLWithPath: path),
                            to: node.url
                        ) || movedAny
                    }
                    isDropTarget = false
                    return didMove
                } isTargeted: { isTargeted in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        isDropTarget = isTargeted
                    }
                }
        } else {
            baseRow
                .draggable(node.url.path) {
                    Label(node.title, systemImage: iconName)
                        .padding(.horizontal, BPTokens.Spacing.sm)
                        .padding(.vertical, BPTokens.Spacing.xs)
                        .background(BPTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
                }
        }
    }

    private var baseRow: some View {
        ZStack(alignment: .trailing) {
            Button {
                model.open(node)
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)

            if shouldShowCollapseButton {
                CollapseFoldersButton(
                    helpText: "Close folder",
                    action: { model.collapseFolder(node) }
                )
                .padding(.trailing, BPTokens.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button {
                model.copyPath(node.url)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            if !node.isDirectory {
                Button {
                    model.reload(node)
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }

            Button {
                model.rename(node)
            } label: {
                Label("Rename…", systemImage: "pencil")
            }

            if !node.isDirectory {
                Divider()
                Button {
                    model.duplicate(node)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(model.isPerformingFileOperation)
            }

            Divider()
            Button(role: .destructive) {
                model.delete(node)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
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
        .padding(
            .trailing,
            shouldShowCollapseButton
                ? BPTokens.Spacing.sm + 28
                : BPTokens.Spacing.sm
        )
        .frame(minHeight: BPTokens.Size.row)
        .background(
            isDropTarget
                ? Color.accentColor.opacity(0.2)
                : highlightedNodeIDs.contains(node.id)
                    ? BPTokens.Color.selection
                    : .clear
        )
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
        case .csv: return "tablecells"
        case .docx: return "doc.text.fill"
        case .pdf: return "doc.fill"
        case .other: return "doc"
        }
    }

    private var shouldShowCollapseButton: Bool {
        node.isDirectory
            && level == 0
            && isHovering
            && model.expandedPaths.contains(node.id)
    }

    private var iconColor: Color {
        switch node.kind {
        case .markdown: .blue
        case .latex: .orange
        case .json: .yellow
        case .csv: .green
        case .docx: .purple
        case .pdf: .red
        case .other: BPTokens.Color.muted
        }
    }
}

struct TreeLoadingRow: View {
    let level: Int

    var body: some View {
        HStack(spacing: BPTokens.Spacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .font(BPTokens.Typography.caption)
                .foregroundStyle(BPTokens.Color.muted)
        }
        .padding(.leading, BPTokens.Spacing.sm + CGFloat(level) * BPTokens.Spacing.md)
        .frame(minHeight: BPTokens.Size.row)
        .overlay(alignment: .leading) {
            TreeGuides(level: level)
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
