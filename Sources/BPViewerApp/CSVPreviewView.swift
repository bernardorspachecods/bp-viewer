import AppKit
import BPViewerCore
import SwiftUI
import WebKit

struct CSVPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let document: CSVDocument
    let editingSession: CSVEditSession?
    let zoom: Double
    let previewRevision: Date?
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onCellChanged: @MainActor @Sendable (Int, Int, String) -> Void
    let onUndo: @MainActor @Sendable () -> Void
    let onRedo: @MainActor @Sendable () -> Void
    let onSaveEditing: @MainActor @Sendable () -> Void
    let onDiscardEditing: () -> Void
    let onKeepLocalEdit: @MainActor @Sendable () -> Void
    let onUseExternalEdit: @MainActor @Sendable () -> Void
    let onSnapshot: (() -> Void)?
    let isSnapshotCaptureActive: Bool
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("CSV", systemImage: "tablecells")
                    .font(BPTokens.Typography.caption.weight(.medium))
                Text("\(document.rows.dropFirst().count) rows · \(document.columnCount) columns")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
                Spacer()
                if let editingSession {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(editingSession.undoSources.isEmpty)

                    Button(action: onRedo) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(editingSession.redoSources.isEmpty)

                    if editingSession.conflict != nil {
                        Button("Keep Mine", action: onKeepLocalEdit)
                            .buttonStyle(.borderless)
                        Button("Use External", action: onUseExternalEdit)
                            .buttonStyle(.borderless)
                    }
                    DocumentEditActionBar(
                        saveState: editingSession.saveState,
                        onDiscard: onDiscardEditing,
                        onSave: { onSaveEditing() }
                    )
                }
                if let onSnapshot {
                    Button(action: onSnapshot) {
                        Image(systemName: "camera.viewfinder")
                            .font(BPTokens.Typography.body)
                            .foregroundStyle(BPTokens.Color.muted)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .contentShape(Rectangle())
                    .help("Create Preview Snapshot")
                }
            }
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.vertical, BPTokens.Spacing.xs)
            .background(BPTokens.Color.surface)

            Divider()

            ZStack {
                CSVHTMLPreview(
                    html: CSVPreviewAdapter().html(document: document, isDark: colorScheme == .dark),
                    zoom: zoom,
                    previewRevision: previewRevision,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    isFindTarget: isFindTarget,
                    onFindFocus: onFindFocus,
                    onFindMatchCount: onFindMatchCount,
                    onCellChanged: onCellChanged,
                    onSaveEditing: onSaveEditing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)

                if isSnapshotCaptureActive {
                    SnapshotSelectionOverlay(
                        onCancel: onSnapshotCancel,
                        onCapture: onSnapshotCapture
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.clear)
    }
}

private struct CSVHTMLPreview: NSViewRepresentable {
    let html: String
    let zoom: Double
    let previewRevision: Date?
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onCellChanged: @MainActor @Sendable (Int, Int, String) -> Void
    let onSaveEditing: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFindMatchCount: onFindMatchCount,
            onCellChanged: onCellChanged,
            onSaveEditing: onSaveEditing
        )
    }

    func makeNSView(context: Context) -> FindTrackingWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = FindTrackingWKWebView(frame: .zero, configuration: configuration)
        configuration.userContentController.add(context.coordinator, name: "csvEdit")
        webView.onFindFocus = onFindFocus
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.pageZoom = zoom
        context.coordinator.load(
            html: html,
            revision: previewRevision,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: FindTrackingWKWebView, context: Context) {
        webView.onFindFocus = onFindFocus
        webView.pageZoom = zoom
        context.coordinator.onFindMatchCount = onFindMatchCount
        context.coordinator.onCellChanged = onCellChanged
        context.coordinator.onSaveEditing = onSaveEditing
        context.coordinator.updateFind(
            query: findQuery,
            requestID: findRequestID,
            backwards: findBackwards,
            isFindTarget: isFindTarget,
            in: webView
        )

        guard context.coordinator.html != html
                || context.coordinator.previewRevision != previewRevision else { return }
        context.coordinator.load(
            html: html,
            revision: previewRevision,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: FindTrackingWKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "csvEdit")
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var html: String?
        var previewRevision: Date?
        var findQuery = ""
        var findRequestID = -1
        var findBackwards = false
        var isFindTarget = true
        var onFindMatchCount: @MainActor @Sendable (Int) -> Void
        var onCellChanged: @MainActor @Sendable (Int, Int, String) -> Void
        var onSaveEditing: @MainActor @Sendable () -> Void

        init(
            onFindMatchCount: @escaping @MainActor @Sendable (Int) -> Void,
            onCellChanged: @escaping @MainActor @Sendable (Int, Int, String) -> Void,
            onSaveEditing: @escaping @MainActor @Sendable () -> Void
        ) {
            self.onFindMatchCount = onFindMatchCount
            self.onCellChanged = onCellChanged
            self.onSaveEditing = onSaveEditing
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "csvEdit",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == "save" {
                    self.onSaveEditing()
                    return
                }
                guard type == "cellChanged",
                      let row = payload["row"] as? NSNumber,
                      let column = payload["column"] as? NSNumber,
                      let value = payload["value"] as? String else { return }
                self.onCellChanged(row.intValue, column.intValue, value)
            }
        }

        func load(html: String, revision: Date?, in webView: WKWebView) {
            self.html = html
            previewRevision = revision
            webView.loadHTMLString(html, baseURL: nil)
        }

        func updateFind(
            query: String,
            requestID: Int,
            backwards: Bool,
            isFindTarget: Bool,
            in webView: WKWebView
        ) {
            let queryChanged = findQuery != query
            guard findQuery != query
                    || findRequestID != requestID
                    || findBackwards != backwards
                    || self.isFindTarget != isFindTarget else { return }
            findQuery = query
            findRequestID = requestID
            findBackwards = backwards
            self.isFindTarget = isFindTarget
            applyFind(in: webView, updateMatchCount: queryChanged)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFind(in: webView, updateMatchCount: true)
        }

        private func applyFind(in webView: WKWebView, updateMatchCount: Bool) {
            guard isFindTarget else { return }
            if updateMatchCount {
                WebViewFindSupport.countMatches(in: webView, query: findQuery) { [weak self] count in
                    self?.onFindMatchCount(count)
                }
            }
            WebViewFindSupport.find(in: webView, query: findQuery, backwards: findBackwards)
        }
    }
}
