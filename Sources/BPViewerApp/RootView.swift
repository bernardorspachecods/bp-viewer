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
                    ResizableSidebarView()
                }

                DocumentWorkspaceView()
            }
        }
        .background(BPTokens.Color.canvas)
        .background(WindowCloseGuard(model: model))
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
        .alert("Switch Open Folder?", isPresented: $model.showingRootChangeConfirmation) {
            Button("Cancel", role: .cancel, action: model.cancelRootChange)
            Button("Switch", role: .destructive, action: model.confirmRootChange)
        } message: {
            Text("The current tabs will be closed and the new folder will become the project root.")
        }
        .alert(model.pendingFileMoveTitle, isPresented: $model.showingFileMoveConfirmation) {
            Button("Cancel", role: .cancel, action: model.cancelFileMove)
            Button("Move", role: .destructive, action: model.confirmFileMove)
        } message: {
            Text(model.pendingFileMoveMessage)
        }
        .alert(
            "Unsaved Changes",
            isPresented: $model.showingPendingCloseConfirmation
        ) {
            Button("Continue Editing", role: .cancel, action: model.cancelPendingClose)
            if model.pendingCloseCanSave {
                Button(
                    model.pendingCloseRequest?.unsavedCount ?? 1 > 1 ? "Save All" : "Save",
                    action: model.savePendingClose
                )
            }
            Button(
                model.pendingCloseRequest?.unsavedCount ?? 1 > 1 ? "Discard All" : "Discard Changes",
                role: .destructive,
                action: model.discardPendingClose
            )
        } message: {
            if model.pendingCloseRequest?.unsavedCount ?? 1 > 1 {
                Text("\(model.pendingCloseRequest?.unsavedCount ?? 0) documents have unsaved changes. Would you like to save or close without saving?")
            } else if model.pendingCloseCanSave {
                Text("\(model.pendingCloseRequest?.title ?? "This file") has unsaved changes. Would you like to edit, save, or close without saving?")
            } else {
                Text("\(model.pendingCloseRequest?.title ?? "This file") contains invalid JSON. Fix the content before saving, or close without saving.")
            }
        }
        .alert(
            "Invalid JSON",
            isPresented: $model.showingInvalidJSONConfirmation
        ) {
            Button("Continue Editing", role: .cancel, action: model.cancelInvalidJSONEditing)
            Button("Discard Changes", role: .destructive, action: model.discardInvalidJSONEditing)
        } message: {
            Text("This JSON is invalid and cannot be saved. Continue editing or discard the changes?")
        }
        .alert(
            "Discard Git Changes?",
            isPresented: $model.showingGitDiscardConfirmation
        ) {
            Button("Cancel", role: .cancel, action: model.cancelDiscardGitChanges)
            Button("Discard Git Changes", role: .destructive, action: model.confirmDiscardGitChanges)
        } message: {
            Text("\(model.pendingGitDiscardTitle) and its current draft will be restored to HEAD. Staged and unstaged changes will be discarded.")
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

private struct ResizableSidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var liveWidth: Double?

    private var displayedWidth: Double {
        liveWidth ?? model.sidebarWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: displayedWidth)
            SidebarResizeHandle(
                width: displayedWidth,
                onChanged: { liveWidth = $0 },
                onEnded: { width in
                    model.setSidebarWidth(width)
                    liveWidth = nil
                }
            )
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
                Text("Choose Main LaTeX Document")
                    .font(.title2.weight(.semibold))
                Text(
                    request.candidates.isEmpty
                        ? "The main document could not be identified automatically. Your manual choice will be saved for future compilations."
                        : "Several main documents were found in this project. Your choice will be saved for future compilations."
                )
                    .font(BPTokens.Typography.body)
                    .foregroundStyle(BPTokens.Color.muted)
            }

            if request.candidates.isEmpty {
                VStack(alignment: .leading, spacing: BPTokens.Spacing.sm) {
                    Text("No main document was found automatically in this folder.")
                        .font(BPTokens.Typography.body)
                        .foregroundStyle(BPTokens.Color.muted)
                    Button("Choose Main File…") {
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
                Button("Cancel") {
                    model.cancelLatexRootSelection()
                }
                Button("Choose") {
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
                Text("Confirm External Dependencies")
                    .font(.title2.weight(.semibold))
                Text("The main document references files outside the project folder. Compilation will continue only after you confirm.")
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
                            Text("Referenced by \(dependency.sourceURL.lastPathComponent)")
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
                Button("Cancel") {
                    model.cancelLatexExternalDependencies()
                }
                Button("Allow and Compile") {
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
    let width: Double
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    let minimumWidth: Double
    let maximumWidth: Double
    let helpText: String

    @State private var initialWidth: Double?
    @State private var isHovering = false

    init(
        width: Double,
        minimumWidth: Double = Double(BPTokens.Size.sidebarMin),
        maximumWidth: Double = Double(BPTokens.Size.sidebarMax),
        helpText: String = "Resize Sidebar",
        onChanged: @escaping (Double) -> Void,
        onEnded: @escaping (Double) -> Void
    ) {
        self.width = width
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.helpText = helpText
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 5)
            .overlay {
                Rectangle()
                    .fill(isHovering ? Color.accentColor.opacity(0.45) : BPTokens.Color.separator)
                    .frame(width: 1)
            }
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
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if initialWidth == nil {
                            initialWidth = width
                        }
                        guard let baseWidth = initialWidth else { return }
                        let resizedWidth = min(
                            max(baseWidth + value.translation.width, minimumWidth),
                            maximumWidth
                        )
                        onChanged(resizedWidth)
                    }
                    .onEnded { value in
                        guard let baseWidth = initialWidth else { return }
                        let resizedWidth = min(
                            max(baseWidth + value.translation.width, minimumWidth),
                            maximumWidth
                        )
                        onEnded(resizedWidth)
                        initialWidth = nil
                    }
            )
            .help(helpText)
    }
}

struct TopBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            ToolbarIconButton(
                systemName: "sidebar.left",
                help: model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            ) {
                model.setSidebarVisible(!model.sidebarVisible)
            }

            ToolbarIconButton(systemName: "folder", help: "Open Folder") {
                model.openFolder()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.rootURL?.lastPathComponent ?? "Viewer")
                    .font(BPTokens.Typography.title)
                Text(model.rootURL?.path ?? "No Folder Open")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                    .lineLimit(1)
            }

            Spacer()

            if model.activeTab?.kind == .latex {
                ToolbarIconButton(systemName: "list.bullet.rectangle", help: "Choose Main LaTeX Document") {
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
                        .iconButtonHitArea()
                }
                .menuStyle(.borderlessButton)
                .help("Advanced LaTeX Settings")
            }

            if model.canCaptureActivePreview {
                ToolbarIconButton(systemName: "camera.viewfinder", help: "Create Preview Snapshot") {
                    model.startSnapshotCapture()
                }
            }

            if let kind = model.activeTab?.kind,
               [.markdown, .latex, .pdf, .json, .csv, .docx].contains(kind) {
                ToolbarIconButton(systemName: "minus.magnifyingglass", help: "Zoom Out") {
                    model.zoomOut()
                }
                Button("\(Int(model.previewZoom * 100))%", action: model.resetPreviewZoom)
                    .buttonStyle(.plain)
                    .font(BPTokens.Typography.caption)
                    .frame(minWidth: 42)
                    .help("Reset Zoom")
                ToolbarIconButton(systemName: "plus.magnifyingglass", help: "Zoom In") {
                    model.zoomIn()
                }
            }

            ToolbarIconButton(systemName: model.theme == .dark ? "sun.max" : "moon", help: "Toggle Theme") {
                model.cycleTheme()
            }

        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .frame(height: BPTokens.Size.toolbar)
        .background(BPTokens.Color.surface)
    }
}
