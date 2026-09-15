import AppKit
import SwiftUI
import WebKit

private enum JSONPreviewJavaScript {
    static let source = #"""
    (() => {
      const handler = () => window.webkit?.messageHandlers?.bpViewerJSONEdit;
      document.addEventListener('dblclick', (event) => {
        event.preventDefault();

        const pre = document.querySelector('[data-bp-json]');
        const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
        let renderedUTF8Offset = 0;

        if (pre && range && pre.contains(range.startContainer)) {
          const measuredRange = document.createRange();
          try {
            measuredRange.selectNodeContents(pre);
            measuredRange.setEnd(range.startContainer, range.startOffset);
            renderedUTF8Offset = new TextEncoder().encode(measuredRange.toString()).length;
          } catch (_) {
            renderedUTF8Offset = 0;
          }
        }

        handler()?.postMessage({
          type: 'begin',
          renderedUTF8Offset
        });
      });
    })();
    """#

    static func document(source: String) -> String {
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")

        return """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              html, body {
                margin: 0;
                min-height: 100%;
                background: transparent;
              }
              body {
                margin: 0 auto;
                max-width: 860px;
                padding: 40px 52px;
                color: -apple-system-label;
                background: -apple-system-background;
                font: ui-monospace, SFMono-Regular, Menlo, monospace;
                line-height: 1.35;
              }
              pre {
                margin: 0;
                white-space: pre-wrap;
                overflow-wrap: anywhere;
                user-select: text;
              }
            </style>
          </head>
          <body>
            <pre data-bp-json>\(escapedSource)</pre>
          </body>
        </html>
        """
    }
}

struct JSONPreviewView: View {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let editingSession: MarkdownEditSession?
    let onBeginEditing: (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onEndEditing: () -> Void
    let onKeepLocalEdit: () -> Void
    let onUseExternalEdit: () -> Void
    let isSnapshotCaptureActive: Bool
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let editingSession {
                JSONEditToolbar(
                    session: editingSession,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onEndEditing: onEndEditing
                )
                if let conflict = editingSession.conflict {
                    JSONConflictView(
                        conflict: conflict,
                        onKeepLocal: onKeepLocalEdit,
                        onUseExternal: onUseExternalEdit
                    )
                }
                JSONSourceEditor(
                    source: editingSession.currentSource,
                    zoom: zoom,
                    cursorUTF8Offset: cursorUTF8Offset,
                    onSourceChanged: onSourceChanged,
                    onEndEditing: onEndEditing
                )
            } else {
                previewSurface
            }
        }
        .background(BPTokens.Color.canvas)
    }

    private var previewSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Label("JSON", systemImage: "curlybraces")
                    .font(BPTokens.Typography.caption.weight(.medium))
                Spacer()
                Text("Preview formatado")
                    .font(BPTokens.Typography.caption)
                    .foregroundStyle(BPTokens.Color.muted)
            }
            .padding(.horizontal, BPTokens.Spacing.md)
            .padding(.vertical, BPTokens.Spacing.xs)
            .background(BPTokens.Color.surface)

            Divider()

            ZStack {
                JSONPreviewWebView(
                    source: source,
                    zoom: zoom,
                    onDoubleClick: onBeginEditing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BPTokens.Color.canvas)

                if isSnapshotCaptureActive {
                    SnapshotSelectionOverlay(
                        onCancel: onSnapshotCancel,
                        onCapture: onSnapshotCapture
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private struct JSONEditToolbar: View {
    let session: MarkdownEditSession
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onEndEditing: () -> Void

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            Label("Edição JSON", systemImage: "curlybraces")
                .font(BPTokens.Typography.caption.weight(.medium))

            Button(action: onUndo) {
                Label("Desfazer", systemImage: "arrow.uturn.backward")
            }
            .disabled(session.undoSources.isEmpty)

            Button(action: onRedo) {
                Label("Refazer", systemImage: "arrow.uturn.forward")
            }
            .disabled(session.redoSources.isEmpty)

            Spacer()

            Text(session.saveState.label)
                .font(BPTokens.Typography.caption)
                .foregroundStyle(session.saveState == .conflict ? BPTokens.Color.warning : BPTokens.Color.muted)

            Button("Concluir", action: onEndEditing)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }
}

private struct JSONSourceEditor: View {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SourceTextView(
                source: source,
                zoom: zoom,
                cursorUTF8Offset: cursorUTF8Offset,
                monospaced: true,
                onSourceChanged: onSourceChanged,
                onEndEditing: onEndEditing
            )
            .frame(
                maxWidth: (
                    SourceEditorLayout.contentMaxWidth
                        + (SourceEditorLayout.horizontalPadding * 2)
                ) * CGFloat(zoom),
                maxHeight: .infinity
            )
            Spacer(minLength: 0)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
        .onExitCommand(perform: onEndEditing)
    }
}

private struct JSONPreviewWebView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let onDoubleClick: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: JSONPreviewJavaScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(
            context.coordinator,
            name: "bpViewerJSONEdit"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = zoom
        webView.loadHTMLString(
            JSONPreviewJavaScript.document(source: source),
            baseURL: nil
        )
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "bpViewerJSONEdit"
        )
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onDoubleClick = onDoubleClick
        webView.pageZoom = zoom
        guard context.coordinator.source != source else { return }
        context.coordinator.source = source
        webView.loadHTMLString(
            JSONPreviewJavaScript.document(source: source),
            baseURL: nil
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var source: String
        var onDoubleClick: (Int) -> Void

        init(source: String, onDoubleClick: @escaping (Int) -> Void) {
            self.source = source
            self.onDoubleClick = onDoubleClick
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "bpViewerJSONEdit",
                  let payload = message.body as? [String: Any],
                  payload["type"] as? String == "begin",
                  let offset = (payload["renderedUTF8Offset"] as? NSNumber)?.intValue else {
                return
            }
            onDoubleClick(offset)
        }
    }
}

private struct JSONConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("Este ficheiro JSON também foi alterado fora do bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))

            HStack {
                Spacer()
                Button("Usar versão externa", action: onUseExternal)
                Button("Manter as minhas alterações", action: onKeepLocal)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.sm)
        .background(BPTokens.Color.warning.opacity(0.1))
    }
}
