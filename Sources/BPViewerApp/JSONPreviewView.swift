import AppKit
import BPViewerCore
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

    static func document(source: String, isDark: Bool) -> String {
        let palette = JSONSyntaxColorPalette(isDark: isDark)
        let highlightedSource = highlightedSource(source)

        return """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              :root {
                color-scheme: \(isDark ? "dark" : "light");
                --json-background: \(palette.background);
                --json-foreground: \(palette.foreground);
              }
            </style>
            <style>
              html, body {
                margin: 0;
                min-height: 100%;
                background: var(--json-background);
                color: var(--json-foreground);
              }
              body {
                margin: 0 auto;
                min-height: 100vh;
                max-width: \(SourceEditorLayout.contentMaxWidth + (SourceEditorLayout.horizontalPadding * 2))px;
                padding: 40px 52px;
                box-sizing: border-box;
                color: var(--json-foreground);
                background: var(--json-background);
                font-family: \(SourceEditorLayout.codeFontFamily), Menlo, monospace;
                font-size: \(SourceEditorLayout.codeFontSize)px;
                font-weight: 400;
                line-height: \(SourceEditorLayout.codeLineHeight)px;
              }
              pre {
                margin: 0;
                font: inherit;
                white-space: pre-wrap;
                overflow-wrap: anywhere;
                user-select: text;
              }
              .json-punctuation { color: \(palette.punctuation); }
              .json-key { color: \(palette.key); }
              .json-string { color: \(palette.string); }
              .json-number { color: \(palette.number); }
              .json-boolean, .json-null { color: \(palette.literal); }
              .json-invalid {
                color: \(palette.invalid);
                text-decoration: underline wavy \(palette.invalid);
              }
            </style>
          </head>
          <body>
            <pre data-bp-json>\(highlightedSource)</pre>
          </body>
        </html>
        """
    }

    private static func highlightedSource(_ source: String) -> String {
        let bytes = Array(source.utf8)
        let tokens = JSONSyntaxHighlighter().tokenize(source)
        var html = ""
        var cursor = 0

        for token in tokens where token.utf8Offset >= cursor {
            if token.utf8Offset > cursor {
                html += escapeHTML(String(decoding: bytes[cursor..<token.utf8Offset], as: UTF8.self))
            }
            let end = min(token.utf8End, bytes.count)
            let text = escapeHTML(String(decoding: bytes[token.utf8Offset..<end], as: UTF8.self))
            html += "<span class=\"json-\(cssClass(for: token.kind))\">\(text)</span>"
            cursor = end
        }

        if cursor < bytes.count {
            html += escapeHTML(String(decoding: bytes[cursor...], as: UTF8.self))
        }
        return html
    }

    private static func cssClass(for kind: JSONSyntaxTokenKind) -> String {
        switch kind {
        case .punctuation: "punctuation"
        case .key: "key"
        case .string: "string"
        case .number: "number"
        case .boolean: "boolean"
        case .null: "null"
        case .invalid: "invalid"
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

struct JSONPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let editingSession: MarkdownEditSession?
    let onBeginEditing: (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onKeepLocalEdit: () -> Void
    let onUseExternalEdit: () -> Void
    let onSnapshot: (() -> Void)?
    let isSnapshotCaptureActive: Bool
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    @State private var editorSource: String?

    var body: some View {
        VStack(spacing: 0) {
            if let editingSession {
                JSONEditToolbar(
                    session: editingSession,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onEndEditing: {
                        onEndEditing(editorSource ?? editingSession.currentSource)
                    }
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
                    syntaxHighlightPalette: JSONSyntaxColorPalette(isDark: colorScheme == .dark),
                    onSourceChanged: { text in
                        editorSource = text
                        onSourceChanged(text)
                    },
                    onEndEditing: { text in
                        editorSource = text
                        onSourceChanged(text)
                        onEndEditing(text)
                    }
                )
                .onAppear {
                    editorSource = editingSession.currentSource
                }
                .onChange(of: editingSession.currentSource) { _, newSource in
                    editorSource = newSource
                }
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
                JSONPreviewWebView(
                    source: source,
                    zoom: zoom,
                    isDark: colorScheme == .dark,
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
            Label("JSON Editing", systemImage: "curlybraces")
                .font(BPTokens.Typography.caption.weight(.medium))

            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(session.undoSources.isEmpty)

            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(session.redoSources.isEmpty)

            Spacer()

            Text(session.saveState.label)
                .font(BPTokens.Typography.caption)
                .foregroundStyle(session.saveState == .conflict ? BPTokens.Color.warning : BPTokens.Color.muted)

            Button("Done", action: onEndEditing)
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
    let syntaxHighlightPalette: JSONSyntaxColorPalette
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SourceTextView(
                source: source,
                zoom: zoom,
                cursorUTF8Offset: cursorUTF8Offset,
                monospaced: true,
                syntaxHighlighting: .json(syntaxHighlightPalette),
                markdownShortcutsEnabled: false,
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
    }
}

private struct JSONPreviewWebView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let isDark: Bool
    let onDoubleClick: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, isDark: isDark, onDoubleClick: onDoubleClick)
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
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        webView.underPageBackgroundColor = isDark
            ? NSColor(calibratedWhite: 0.118, alpha: 1)
            : .white
        webView.pageZoom = zoom
        webView.loadHTMLString(
            JSONPreviewJavaScript.document(source: source, isDark: isDark),
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
        let themeChanged = context.coordinator.isDark != isDark
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        webView.underPageBackgroundColor = isDark
            ? NSColor(calibratedWhite: 0.118, alpha: 1)
            : .white
        guard context.coordinator.source != source || themeChanged else { return }
        context.coordinator.source = source
        context.coordinator.isDark = isDark
        webView.loadHTMLString(
            JSONPreviewJavaScript.document(source: source, isDark: isDark),
            baseURL: nil
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var source: String
        var isDark: Bool
        var onDoubleClick: (Int) -> Void

        init(source: String, isDark: Bool, onDoubleClick: @escaping (Int) -> Void) {
            self.source = source
            self.isDark = isDark
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
            Text("This JSON file was also changed outside bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))

            HStack {
                Spacer()
                Button("Use External Version", action: onUseExternal)
                Button("Keep My Changes", action: onKeepLocal)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.sm)
        .background(BPTokens.Color.warning.opacity(0.1))
    }
}
