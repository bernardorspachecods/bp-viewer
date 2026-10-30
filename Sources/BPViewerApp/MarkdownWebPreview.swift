import SwiftUI
import WebKit
import BPViewerCore
import AppKit

private enum MarkdownEditingJavaScript {
    static let source = #"""
    (() => {
      const handler = () => window.webkit?.messageHandlers?.bpViewerMarkdownEdit;
      const unitSelector = '[data-bp-block-id][data-bp-editable="true"]';
      const blockedSelector = 'img, math, [data-bp-special-kind]';
      const commitDelay = 350;
      const styleID = 'bp-inline-style';
      const styleSource = `
        [contenteditable="plaintext-only"] {
          cursor: text;
          outline: none;
          border-radius: 4px;
          transition: background-color 120ms ease;
        }
        [contenteditable="plaintext-only"]:hover {
          background: color-mix(in srgb, -apple-system-blue 4%, transparent);
        }
        [contenteditable="plaintext-only"]:focus {
          background: color-mix(in srgb, -apple-system-blue 8%, transparent);
        }
      `;
      let enabled = false;
      let entries = [];
      let pendingEntry = null;
      let commitTimer = null;

      const isTextBlock = (tag) => tag === 'P' || /^H[1-6]$/.test(tag);
      const isList = (tag) => tag === 'UL' || tag === 'OL';
      const isSupported = (element) => !element.matches(blockedSelector) && !element.querySelector(blockedSelector);

      function collectEntries() {
        const collected = [];
        document.querySelectorAll(unitSelector).forEach((block) => {
          if (isTextBlock(block.tagName)) {
            if (isSupported(block)) {
              collected.push({ element: block, blockID: block.dataset.bpBlockId, unitIndex: null });
            }
          } else if (isList(block.tagName)) {
            block.querySelectorAll('li').forEach((item, index) => {
              if (item.querySelector('ul, ol') || !isSupported(item)) return;
              collected.push({ element: item, blockID: block.dataset.bpBlockId, unitIndex: index });
            });
          }
        });
        return collected;
      }

      function unitText(element) {
        const clone = element.cloneNode(true);
        clone.querySelectorAll('ul, ol, input').forEach((node) => node.remove());
        return clone.textContent.replace(/ /g, ' ').trim();
      }

      function textNodes(element) {
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        return nodes;
      }

      function textLength(element) {
        return textNodes(element).reduce((total, node) => total + node.length, 0);
      }

      function entryFor(target) {
        return entries.find((entry) => entry.element.contains(target)) || null;
      }

      function commit(entry) {
        if (!entry.element.isConnected) return;
        const text = unitText(entry.element);
        if (text === entry.baseline) return;
        handler()?.postMessage({
          type: 'inlineChange',
          blockID: entry.blockID,
          unitIndex: entry.unitIndex,
          original: entry.baseline,
          text
        });
        entry.baseline = text;
      }

      function flush() {
        clearTimeout(commitTimer);
        commitTimer = null;
        const entry = pendingEntry;
        pendingEntry = null;
        if (entry) commit(entry);
      }

      function scheduleCommit(entry) {
        pendingEntry = entry;
        clearTimeout(commitTimer);
        commitTimer = setTimeout(flush, commitDelay);
      }

      function setEnabled(on) {
        flush();
        enabled = on;
        entries.forEach((entry) => { entry.element.contentEditable = 'false'; });
        entries = on ? collectEntries() : [];
        entries.forEach((entry) => {
          entry.baseline = unitText(entry.element);
          entry.element.contentEditable = 'plaintext-only';
        });
        const existing = document.getElementById(styleID);
        if (on && !existing) {
          const style = document.createElement('style');
          style.id = styleID;
          style.textContent = styleSource;
          document.head.append(style);
        } else if (!on && existing) {
          existing.remove();
        }
      }

      function placeCaret(element, offset) {
        const range = document.createRange();
        range.selectNodeContents(element);
        range.collapse(false);
        let remaining = Math.max(offset, 0);
        for (const node of textNodes(element)) {
          if (remaining <= node.length) {
            range.setStart(node, remaining);
            range.collapse(true);
            break;
          }
          remaining -= node.length;
        }
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }

      function focusAt(blockID, renderedTextOffset) {
        const candidates = entries.filter((entry) => entry.blockID === blockID);
        if (candidates.length === 0) return;
        const entry = candidates.find((candidate) => textLength(candidate.element) >= renderedTextOffset)
          || candidates[0];
        entry.element.focus();
        placeCaret(entry.element, renderedTextOffset);
      }

      document.addEventListener('dblclick', (event) => {
        if (enabled) return;
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

      document.addEventListener('input', (event) => {
        const entry = entryFor(event.target);
        if (entry) scheduleCommit(entry);
      });

      document.addEventListener('focusout', (event) => {
        if (entryFor(event.target)) flush();
      });

      document.addEventListener('keydown', (event) => {
        if (!enabled) return;
        if (event.key === 'Enter' && !event.isComposing && entryFor(event.target)) {
          event.preventDefault();
          return;
        }
        if (!event.metaKey || event.isComposing) return;
        const key = event.key.toLowerCase();
        if (key === 'z') {
          event.preventDefault();
          flush();
          handler()?.postMessage({ type: event.shiftKey ? 'redo' : 'undo', text: '' });
        } else if (key === 'b' || key === 'i' || key === 'u') {
          event.preventDefault();
        }
      });

      window.bpInline = { setEnabled, focusAt };
    })();
    """#
}

enum MarkdownScrollObservationPolicy {
    static func shouldCapture(previousBounds: CGRect?, currentBounds: CGRect) -> Bool {
        guard let previousBounds else { return false }
        return previousBounds.size == currentBounds.size
            && previousBounds.origin != currentBounds.origin
    }
}

struct MarkdownWebView: NSViewRepresentable {
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
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let requestedHeadingID: String?
    let outlineRequestID: Int
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void
    let isQuickEditEnabled: Bool
    let quickEditFocus: (blockID: String, offset: Int, requestID: Int)?

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

        let webView = FindTrackingWKWebView(frame: .zero, configuration: configuration)
        webView.onFindFocus = onFindFocus
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        configureScrollView(of: webView)
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
        context.coordinator.onFindMatchCount = onFindMatchCount
        (webView as? FindTrackingWKWebView)?.onFindFocus = onFindFocus
        configureScrollView(of: webView)
        context.coordinator.observeScroll(in: webView)
        if abs(webView.pageZoom - zoom) > 0.001 {
            webView.pageZoom = zoom
        }

        if context.coordinator.findRequestID != findRequestID
            || context.coordinator.findQuery != findQuery
            || context.coordinator.isFindTarget != isFindTarget {
            let queryChanged = context.coordinator.findQuery != findQuery
            let targetChanged = context.coordinator.isFindTarget != isFindTarget
            context.coordinator.findRequestID = findRequestID
            context.coordinator.findQuery = findQuery
            context.coordinator.findBackwards = findBackwards
            context.coordinator.isFindTarget = isFindTarget
            context.coordinator.find(
                in: webView,
                updateMatchCount: queryChanged || targetChanged
            )
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

        if context.coordinator.isQuickEditEnabled != isQuickEditEnabled {
            context.coordinator.isQuickEditEnabled = isQuickEditEnabled
            context.coordinator.applyQuickEditState(in: webView)
        }
        context.coordinator.quickEditFocus = quickEditFocus
        context.coordinator.applyQuickEditFocus(in: webView)

    }

    private func configureScrollView(of webView: WKWebView) {
        guard let scrollView = webView.enclosingScrollView else { return }
        scrollView.horizontalScrollElasticity = .none
        scrollView.hasHorizontalScroller = false
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
        var onFindMatchCount: @MainActor @Sendable (Int) -> Void = { _ in }
        var lastReadingPosition: MarkdownReadingPosition?
        var pendingReadingPosition: MarkdownReadingPosition?
        var findQuery = ""
        var findRequestID = 0
        var findBackwards = false
        var isFindTarget = true
        var outlineRequestID = 0
        var pendingHeadingID: String?
        var isDocumentLoaded = false
        var canBeginEditing = true
        var isQuickEditEnabled = false
        var quickEditFocus: (blockID: String, offset: Int, requestID: Int)?
        private var handledQuickEditRequestID: Int?
        private var scrollObserver: ObserverToken?
        private var captureTask: Task<Void, Never>?
        private var boundsObservationTask: Task<Void, Never>?
        private var lastObservedScrollBounds: CGRect?

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver.value)
            }
        }

        func observeScroll(in webView: WKWebView) {
            guard scrollObserver == nil, let scrollView = webView.enclosingScrollView else { return }
            let contentView = scrollView.contentView
            contentView.postsBoundsChangedNotifications = true
            lastObservedScrollBounds = contentView.bounds
            scrollObserver = ObserverToken(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self, weak webView, weak contentView] _ in
                MainActor.assumeIsolated {
                    self?.scheduleBoundsObservation(in: contentView, webView: webView)
                }
            })
        }

        func removeScrollObservation() {
            boundsObservationTask?.cancel()
            boundsObservationTask = nil
            captureTask?.cancel()
            captureTask = nil
            guard let scrollObserver else { return }
            NotificationCenter.default.removeObserver(scrollObserver.value)
            self.scrollObserver = nil
            lastObservedScrollBounds = nil
        }

        func scheduleBoundsObservation(in contentView: NSView?, webView: WKWebView?) {
            guard let contentView, let webView else { return }
            boundsObservationTask?.cancel()
            boundsObservationTask = Task { @MainActor [weak self, weak webView, weak contentView] in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled,
                      let self,
                      let webView,
                      let contentView else { return }
                let currentBounds = contentView.bounds
                let previousBounds = self.lastObservedScrollBounds
                self.lastObservedScrollBounds = currentBounds
                guard MarkdownScrollObservationPolicy.shouldCapture(
                    previousBounds: previousBounds,
                    currentBounds: currentBounds
                ) else { return }
                self.scheduleCapture(of: webView)
            }
        }

        func scheduleCapture(of webView: WKWebView) {
            captureTask?.cancel()
            captureTask = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled,
                      let self,
                      let webView else { return }
                self.captureReadingPosition(in: webView)
            }
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
                    self.publishReadingPosition(
                        scrollY: scrollY,
                        anchorID: payload["anchorID"] as? String,
                        anchorOffset: anchorOffset
                    )
                }
            )
        }

        func publishReadingPosition(
            scrollY: Double,
            anchorID: String?,
            anchorOffset: Double
        ) {
            let position = MarkdownReadingPosition(
                scrollY: max(scrollY, 0),
                anchorID: anchorID,
                anchorOffset: anchorOffset
            )
            guard lastReadingPosition != position else { return }
            lastReadingPosition = position
            onReadingPositionChanged?(position)
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
            find(in: webView, updateMatchCount: true)
            scheduleCapture(of: webView)
            applyQuickEditState(in: webView)
            applyQuickEditFocus(in: webView)
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
            case "inlineChange": kind = .inlineChange
            default: return
            }
            onMarkdownEditEvent?(MarkdownWebEditEvent(
                kind: kind,
                text: text,
                blockID: payload["blockID"] as? String,
                renderedTextOffset: (payload["renderedTextOffset"] as? NSNumber)?.intValue,
                unitIndex: (payload["unitIndex"] as? NSNumber)?.intValue,
                originalText: payload["original"] as? String
            ))
        }

        func applyQuickEditState(in webView: WKWebView) {
            guard isDocumentLoaded else { return }
            webView.evaluateJavaScript(
                "window.bpInline?.setEnabled(\(isQuickEditEnabled))",
                completionHandler: nil
            )
        }

        func applyQuickEditFocus(in webView: WKWebView) {
            guard isDocumentLoaded,
                  let quickEditFocus,
                  quickEditFocus.requestID != handledQuickEditRequestID,
                  let encodedID = try? String(
                    data: JSONEncoder().encode(quickEditFocus.blockID),
                    encoding: .utf8
                  ) else {
                return
            }
            handledQuickEditRequestID = quickEditFocus.requestID
            webView.evaluateJavaScript(
                "window.bpInline?.focusAt(\(encodedID), \(quickEditFocus.offset))",
                completionHandler: nil
            )
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

        func find(in webView: WKWebView, updateMatchCount: Bool) {
            guard isFindTarget else { return }
            if updateMatchCount {
                WebViewFindSupport.countMatches(in: webView, query: findQuery) { [weak self] count in
                    self?.onFindMatchCount(count)
                }
            }
            WebViewFindSupport.find(in: webView, query: findQuery, backwards: findBackwards)
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
