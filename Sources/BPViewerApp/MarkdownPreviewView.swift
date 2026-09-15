import SwiftUI
import WebKit
import BPViewerCore
import AppKit

private enum MarkdownEditingJavaScript {
    static let source = #"""
    (() => {
      const handler = () => window.webkit?.messageHandlers?.bpViewerMarkdownEdit;
      document.addEventListener('dblclick', (event) => {
        event.preventDefault();
        const block = event.target?.closest?.('[data-bp-block-id]');
        const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
        let renderedTextOffset = null;
        if (block && range) {
          const measuredRange = document.createRange();
          try {
            measuredRange.selectNodeContents(block);
            measuredRange.setEnd(range.startContainer, range.startOffset);
            renderedTextOffset = measuredRange.toString().length;
          } catch (_) {
            renderedTextOffset = null;
          }
        }
        handler()?.postMessage({
          type: 'begin',
          mode: 'markdown',
          text: '',
          blockID: block?.dataset.bpBlockId || null,
          renderedTextOffset
        });
      });
    })();
    """#
}

struct MarkdownPreviewView: View {
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let outline: [MarkdownOutlineEntry]
    let markdownBlocks: [MarkdownEditableBlock]
    let editingSession: MarkdownEditSession?
    let onNavigate: (URL) -> Void
    let onMarkdownTextChanged: @MainActor @Sendable (String) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndMarkdownEditing: () -> Void
    let onKeepLocalMarkdownEdit: () -> Void
    let onUseExternalMarkdownEdit: () -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    @Binding var isOutlineVisible: Bool
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void
    let isSnapshotCaptureActive: Bool
    let onSnapshot: (() -> Void)?
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    @State private var selectedHeadingID: String?
    @State private var outlineRequestID = 0
    @State private var pendingCursorUTF8Offset: Int?

    private var outlineItems: [DocumentOutlineItem] {
        outline.map {
            DocumentOutlineItem(
                id: $0.id,
                title: $0.title,
                level: max($0.level - 1, 0),
                isSelectable: true
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !outlineItems.isEmpty || onSnapshot != nil {
                DocumentOutlineToolbar(
                    isVisible: isOutlineVisible,
                    onToggle: { isOutlineVisible.toggle() },
                    onSnapshot: onSnapshot
                )
            }

            if let editingSession {
                MarkdownEditToolbar(
                    session: editingSession,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onToggleMarkdownMode: onToggleMarkdownMode,
                    onEndEditing: onEndMarkdownEditing
                )
                if let conflict = editingSession.conflict {
                    MarkdownConflictView(
                        conflict: conflict,
                        onKeepLocal: onKeepLocalMarkdownEdit,
                        onUseExternal: onUseExternalMarkdownEdit
                    )
                }
            }

            HStack(spacing: 0) {
                if isOutlineVisible {
                    DocumentOutlineSidebar(
                        entries: outlineItems,
                        selectedID: selectedHeadingID
                    ) { item in
                        selectedHeadingID = item.id
                        outlineRequestID += 1
                    }
                    Divider()
                }

                if let editingSession {
                    MarkdownSourceEditor(
                        source: editingSession.currentSource,
                        zoom: zoom,
                        cursorUTF8Offset: pendingCursorUTF8Offset,
                        onEndEditing: onEndMarkdownEditing,
                        onSourceChanged: onMarkdownTextChanged
                    )
                    if editingSession.mode == .split {
                        Divider()
                        previewSurface
                    }
                } else {
                    previewSurface
                }
            }
        }
        .id(documentID)
    }

    private var previewSurface: some View {
        ZStack {
            MarkdownWebView(
                html: html,
                baseURL: baseURL,
                documentID: documentID,
                previewRevision: previewRevision,
                canBeginEditing: editingSession == nil,
                onNavigate: onNavigate,
                onMarkdownEditEvent: { event in
                    if event.kind == .begin {
                        pendingCursorUTF8Offset = cursorUTF8Offset(for: event)
                    }
                    onMarkdownEditEvent(event)
                },
                zoom: zoom,
                findQuery: findQuery,
                findRequestID: findRequestID,
                findBackwards: findBackwards,
                requestedHeadingID: selectedHeadingID,
                outlineRequestID: outlineRequestID,
                readingPosition: readingPosition,
                onReadingPositionChanged: onReadingPositionChanged
            )
            if isSnapshotCaptureActive {
                SnapshotSelectionOverlay(
                    onCancel: onSnapshotCancel,
                    onCapture: onSnapshotCapture
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cursorUTF8Offset(for event: MarkdownWebEditEvent) -> Int? {
        guard let blockID = event.blockID,
              let renderedTextOffset = event.renderedTextOffset,
              let block = markdownBlocks.first(where: { $0.id == blockID }) else {
            return nil
        }
        return block.sourceRange.startOffset + block.sourceOffset(forRenderedTextOffset: renderedTextOffset)
    }
}

struct MarkdownWebEditEvent {
    enum Kind {
        case begin
        case change
        case end
        case undo
        case redo
    }

    let kind: Kind
    let text: String
    let blockID: String?
    let renderedTextOffset: Int?
}

private struct MarkdownEditToolbar: View {
    let session: MarkdownEditSession
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndEditing: () -> Void

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            Label(
                session.mode == .split ? "Edição dividida" : "Edição Markdown",
                systemImage: session.mode == .split ? "rectangle.split.2x1" : "chevron.left.forwardslash.chevron.right"
            )
            .font(BPTokens.Typography.caption.weight(.medium))

            Button(session.mode == .split ? "Edição Markdown" : "Abrir split view") {
                onToggleMarkdownMode()
            }
            .buttonStyle(.bordered)

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

enum SourceEditorLayout {
    static let contentMaxWidth: CGFloat = 860
    static let horizontalPadding: CGFloat = 52
}

private struct MarkdownSourceEditor: View {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let onEndEditing: () -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SourceTextView(
                    source: source,
                    zoom: zoom,
                    cursorUTF8Offset: cursorUTF8Offset,
                    monospaced: false,
                    syntaxHighlightJSON: false,
                    onSourceChanged: onSourceChanged,
                    onEndEditing: { _ in onEndEditing() }
                )
                .frame(
                    maxWidth: (
                        SourceEditorLayout.contentMaxWidth + (SourceEditorLayout.horizontalPadding * 2)
                    ) * CGFloat(zoom),
                    maxHeight: .infinity
                )
                Spacer(minLength: 0)
            }
            .onExitCommand(perform: onEndEditing)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(BPTokens.Color.canvas)
    }
}

struct SourceTextView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let monospaced: Bool
    let syntaxHighlightJSON: Bool
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void

    private static let bodyLineHeightMultiple: CGFloat = 1.55

    func makeCoordinator() -> Coordinator {
        Coordinator(onSourceChanged: onSourceChanged, onEndEditing: onEndEditing)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownNSTextView()
        textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.onEndEditing(textView.string)
        }
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        if monospaced {
            // JSON syntax requires ASCII quotes; macOS smart quotes would turn
            // a typed delimiter into a Unicode character such as U+201D.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
        }
        textView.usesFindPanel = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.string = source
        applyTypography(to: textView)
        applySyntaxHighlighting(to: textView, source: source)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(
            width: SourceEditorLayout.horizontalPadding * CGFloat(zoom),
            height: 40 * CGFloat(zoom)
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSourceChanged = onSourceChanged
        context.coordinator.onEndEditing = onEndEditing

        if !context.coordinator.didRequestInitialFocus {
            focus(textView, selection: nil) {
                context.coordinator.didRequestInitialFocus = true
            }
        }

        if textView.string != source {
            let selectedRange = textView.selectedRange()
            textView.string = source
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (source as NSString).length),
                length: 0
            ))
        }

        applyTypography(to: textView)
        applySyntaxHighlighting(to: textView, source: source)
        textView.textContainerInset = NSSize(
            width: SourceEditorLayout.horizontalPadding * CGFloat(zoom),
            height: 40 * CGFloat(zoom)
        )

        guard let cursorUTF8Offset,
              context.coordinator.appliedCursorUTF8Offset != cursorUTF8Offset else { return }
        let cursorOffset = utf16Offset(in: source, utf8Offset: cursorUTF8Offset)
        let selection = NSRange(location: cursorOffset, length: 0)
        textView.setSelectedRange(selection)
        focus(textView, selection: selection)
        context.coordinator.appliedCursorUTF8Offset = cursorUTF8Offset
    }

    private func applyTypography(to textView: NSTextView) {
        let bodyFont = monospaced
            ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : NSFont.preferredFont(forTextStyle: .body)
        let font = bodyFont.withSize(bodyFont.pointSize * zoom)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = Self.bodyLineHeightMultiple

        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return }
        let range = NSRange(location: 0, length: textLength)
        textView.textStorage?.addAttribute(.font, value: font, range: range)
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }

    private func applySyntaxHighlighting(to textView: NSTextView, source: String) {
        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return }
        let range = NSRange(location: 0, length: textLength)
        textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        guard syntaxHighlightJSON else { return }

        let colors: [JSONSyntaxTokenKind: NSColor] = [
            .punctuation: .secondaryLabelColor,
            .key: .systemBlue,
            .string: .systemOrange,
            .number: .systemGreen,
            .boolean: .systemPurple,
            .null: .systemPurple,
            .invalid: .systemRed
        ]
        for token in JSONSyntaxHighlighter().tokenize(source) {
            let start = utf16Offset(in: source, utf8Offset: token.utf8Offset)
            let end = utf16Offset(in: source, utf8Offset: token.utf8End)
            guard end > start, let color = colors[token.kind] else { continue }
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(location: start, length: end - start)
            )
        }
    }

    private func focus(
        _ textView: NSTextView,
        selection: NSRange?,
        attempt: Int = 0,
        onFocused: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            guard let window = textView.window else {
                guard attempt < 10 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focus(textView, selection: selection, attempt: attempt + 1, onFocused: onFocused)
                }
                return
            }
            if let selection {
                textView.setSelectedRange(selection)
                textView.scrollRangeToVisible(selection)
            }
            window.makeFirstResponder(textView)
            onFocused?()
        }
    }

    private func utf16Offset(in source: String, utf8Offset: Int) -> Int {
        let bytes = Array(source.utf8)
        let clampedOffset = min(max(utf8Offset, 0), bytes.count)
        let prefix = String(decoding: bytes[..<clampedOffset], as: UTF8.self)
        return prefix.utf16.count
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSourceChanged: @MainActor @Sendable (String) -> Void
        var onEndEditing: @MainActor @Sendable (String) -> Void
        var appliedCursorUTF8Offset: Int?
        var didRequestInitialFocus = false

        init(
            onSourceChanged: @escaping @MainActor @Sendable (String) -> Void,
            onEndEditing: @escaping @MainActor @Sendable (String) -> Void
        ) {
            self.onSourceChanged = onSourceChanged
            self.onEndEditing = onEndEditing
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSourceChanged(textView.string)
        }
    }
}

private final class MarkdownNSTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

private struct MarkdownConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("Este documento também foi alterado fora do bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))
            HStack(spacing: BPTokens.Spacing.sm) {
                conflictColumn(title: "As minhas alterações", source: conflict.localSource)
                conflictColumn(title: "Versão externa", source: conflict.externalSource)
            }
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

    private func conflictColumn(title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
            Text(title)
                .font(BPTokens.Typography.caption.weight(.medium))
            ScrollView {
                Text(source)
                    .font(BPTokens.Typography.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BPTokens.Spacing.xs)
            }
            .frame(maxHeight: 100)
            .background(BPTokens.Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let canBeginEditing: Bool
    let onNavigate: (URL) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let requestedHeadingID: String?
    let outlineRequestID: Int
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownEditingJavaScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "bpViewerMarkdownEdit")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeScroll(in: webView)
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureReadingPosition(in: webView)
        coordinator.removeScrollObservation()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onMarkdownEditEvent = onMarkdownEditEvent
        context.coordinator.onReadingPositionChanged = onReadingPositionChanged
        context.coordinator.canBeginEditing = canBeginEditing
        context.coordinator.observeScroll(in: webView)
        webView.pageZoom = zoom

        if context.coordinator.findRequestID != findRequestID || context.coordinator.findQuery != findQuery {
            context.coordinator.findRequestID = findRequestID
            context.coordinator.findQuery = findQuery
            context.coordinator.findBackwards = findBackwards
            context.coordinator.find(in: webView)
        }

        let documentChanged = context.coordinator.html != html || context.coordinator.baseURL != baseURL
            || context.coordinator.previewRevision != previewRevision
        if documentChanged {
            let isSameDocument = context.coordinator.documentID == documentID
            let currentScrollY = webView.enclosingScrollView.map {
                max(Double($0.contentView.bounds.origin.y), 0)
            }
            let knownPosition = context.coordinator.lastReadingPosition ?? readingPosition
            let currentPosition = currentScrollY.map { scrollY in
                MarkdownReadingPosition(
                    scrollY: scrollY,
                    anchorID: knownPosition?.anchorID,
                    anchorOffset: knownPosition?.anchorOffset ?? 0
                )
            }
            context.coordinator.pendingReadingPosition = isSameDocument
                ? currentPosition ?? knownPosition
                : readingPosition
            context.coordinator.documentID = documentID
            context.coordinator.previewRevision = previewRevision
            context.coordinator.html = html
            context.coordinator.baseURL = baseURL
            context.coordinator.isDocumentLoaded = false
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        if context.coordinator.outlineRequestID != outlineRequestID {
            context.coordinator.outlineRequestID = outlineRequestID
            context.coordinator.pendingHeadingID = requestedHeadingID
            if !documentChanged {
                context.coordinator.scrollToPendingHeading(in: webView)
            }
        }

    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var html: String?
        var baseURL: URL?
        var documentID: String?
        var previewRevision: Date?
        var onNavigate: ((URL) -> Void)?
        var onMarkdownEditEvent: ((MarkdownWebEditEvent) -> Void)?
        var onReadingPositionChanged: ((MarkdownReadingPosition) -> Void)?
        var lastReadingPosition: MarkdownReadingPosition?
        var pendingReadingPosition: MarkdownReadingPosition?
        var findQuery = ""
        var findRequestID = 0
        var findBackwards = false
        var outlineRequestID = 0
        var pendingHeadingID: String?
        var isDocumentLoaded = false
        var canBeginEditing = true
        private var scrollObserver: ObserverToken?
        private var captureWorkItem: DispatchWorkItem?

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver.value)
            }
        }

        func observeScroll(in webView: WKWebView) {
            guard scrollObserver == nil, let scrollView = webView.enclosingScrollView else { return }
            let contentView = scrollView.contentView
            contentView.postsBoundsChangedNotifications = true
            scrollObserver = ObserverToken(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self, weak webView] _ in
                Task { @MainActor [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.scheduleCapture(of: webView)
                }
            })
        }

        func removeScrollObservation() {
            guard let scrollObserver else { return }
            NotificationCenter.default.removeObserver(scrollObserver.value)
            self.scrollObserver = nil
        }

        func scheduleCapture(of webView: WKWebView) {
            captureWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.captureReadingPosition(in: webView)
            }
            captureWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        func captureReadingPosition(in webView: WKWebView) {
            guard isDocumentLoaded else { return }
            webView.evaluateJavaScript(
                """
                (() => {
                    const scrollY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
                    const headings = Array.from(document.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]'));
                    const anchor = headings.find((element) => element.getBoundingClientRect().bottom >= 0) || headings.at(-1);
                    return {
                        scrollY,
                        anchorID: anchor ? anchor.id : null,
                        anchorOffset: anchor ? anchor.getBoundingClientRect().top : 0
                    };
                })()
                """,
                completionHandler: { [weak self] result, _ in
                    guard let self,
                          let payload = result as? [String: Any] else { return }
                    let scrollY = (payload["scrollY"] as? NSNumber)?.doubleValue ?? 0
                    let anchorOffset = (payload["anchorOffset"] as? NSNumber)?.doubleValue ?? 0
                    let position = MarkdownReadingPosition(
                        scrollY: max(scrollY, 0),
                        anchorID: payload["anchorID"] as? String,
                        anchorOffset: anchorOffset
                    )
                    guard self.lastReadingPosition != position else { return }
                    self.lastReadingPosition = position
                    self.onReadingPositionChanged?(position)
                }
            )
        }

        private final class ObserverToken: @unchecked Sendable {
            let value: NSObjectProtocol

            init(_ value: NSObjectProtocol) {
                self.value = value
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentLoaded = true
            if let pendingReadingPosition {
                restoreReadingPosition(pendingReadingPosition, in: webView)
                self.pendingReadingPosition = nil
            }
            scrollToPendingHeading(in: webView)
            find(in: webView)
            scheduleCapture(of: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bpViewerMarkdownEdit",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String,
                  let text = payload["text"] as? String else { return }
            guard type != "begin" || canBeginEditing else { return }

            let kind: MarkdownWebEditEvent.Kind
            switch type {
            case "begin": kind = .begin
            case "change": kind = .change
            case "end": kind = .end
            case "undo": kind = .undo
            case "redo": kind = .redo
            default: return
            }
            onMarkdownEditEvent?(MarkdownWebEditEvent(
                kind: kind,
                text: text,
                blockID: payload["blockID"] as? String,
                renderedTextOffset: (payload["renderedTextOffset"] as? NSNumber)?.intValue
            ))
        }

        func restoreReadingPosition(_ position: MarkdownReadingPosition, in webView: WKWebView) {
            guard let encodedID = try? String(
                data: JSONEncoder().encode(position.anchorID),
                encoding: .utf8
            ),
            let scrollY = String(position.scrollY).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let anchorOffset = String(position.anchorOffset).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return
            }

            let script = """
            (() => {
                const fallback = \(scrollY);
                const anchor = \(encodedID) ? document.getElementById(\(encodedID)) : null;
                if (!anchor) {
                    window.scrollTo(0, fallback);
                    return;
                }
                const desiredTop = window.scrollY + anchor.getBoundingClientRect().top - \(anchorOffset);
                window.scrollTo(0, Math.max(0, desiredTop));
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func scrollToPendingHeading(in webView: WKWebView) {
            guard isDocumentLoaded, let pendingHeadingID,
                  let encodedID = try? String(data: JSONEncoder().encode(pendingHeadingID), encoding: .utf8) else {
                return
            }

            let script = "document.getElementById(\(encodedID))?.scrollIntoView({ block: 'start', behavior: 'smooth' });"
            webView.evaluateJavaScript(script, completionHandler: nil)
            self.pendingHeadingID = nil
        }

        func find(in webView: WKWebView) {
            guard !findQuery.isEmpty else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = findBackwards
            configuration.caseSensitive = false
            configuration.wraps = true
            webView.find(findQuery, configuration: configuration) { _ in }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let requestedURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let currentBaseURL = baseURL

            let resolvedURL: URL
            if requestedURL.scheme == nil,
               let currentBaseURL,
               let relativeURL = URL(string: requestedURL.absoluteString, relativeTo: currentBaseURL)?.absoluteURL {
                resolvedURL = relativeURL
            } else {
                resolvedURL = requestedURL
            }

            let isLocalFileNavigation = resolvedURL.isFileURL
                && !resolvedURL.hasDirectoryPath
                && resolvedURL != webView.url
            let isAppPreviewNavigation = resolvedURL.scheme?.lowercased() == MarkdownPreviewLink.scheme
            guard navigationAction.navigationType == .linkActivated
                    || isLocalFileNavigation
                    || isAppPreviewNavigation else {
                decisionHandler(.allow)
                return
            }

            onNavigate?(resolvedURL)
            decisionHandler(.cancel)
        }
    }
}
