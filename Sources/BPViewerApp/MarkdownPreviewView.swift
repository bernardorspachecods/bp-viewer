import SwiftUI
import WebKit
import BPViewerCore

struct MarkdownPreviewView: View {
    let html: String
    let baseURL: URL
    let documentID: String
    let outline: [MarkdownOutlineEntry]
    let onNavigate: (URL) -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    @Binding var isOutlineVisible: Bool
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void
    @State private var selectedHeadingID: String?
    @State private var outlineRequestID = 0

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
            if !outlineItems.isEmpty {
                DocumentOutlineToolbar(isVisible: isOutlineVisible) {
                    isOutlineVisible.toggle()
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

                MarkdownWebView(
                    html: html,
                    baseURL: baseURL,
                    documentID: documentID,
                    onNavigate: onNavigate,
                    zoom: zoom,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    requestedHeadingID: selectedHeadingID,
                    outlineRequestID: outlineRequestID,
                    readingPosition: readingPosition,
                    onReadingPositionChanged: onReadingPositionChanged
                )
            }
        }
        .id(documentID)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let documentID: String
    let onNavigate: (URL) -> Void
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
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

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
        context.coordinator.onReadingPositionChanged = onReadingPositionChanged
        context.coordinator.observeScroll(in: webView)
        webView.pageZoom = zoom

        if context.coordinator.findRequestID != findRequestID || context.coordinator.findQuery != findQuery {
            context.coordinator.findRequestID = findRequestID
            context.coordinator.findQuery = findQuery
            context.coordinator.findBackwards = findBackwards
            context.coordinator.find(in: webView)
        }

        let documentChanged = context.coordinator.html != html || context.coordinator.baseURL != baseURL
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
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var baseURL: URL?
        var documentID: String?
        var onNavigate: ((URL) -> Void)?
        var onReadingPositionChanged: ((MarkdownReadingPosition) -> Void)?
        var lastReadingPosition: MarkdownReadingPosition?
        var pendingReadingPosition: MarkdownReadingPosition?
        var findQuery = ""
        var findRequestID = 0
        var findBackwards = false
        var outlineRequestID = 0
        var pendingHeadingID: String?
        var isDocumentLoaded = false
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
