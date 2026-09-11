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
                    outlineRequestID: outlineRequestID
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        webView.pageZoom = zoom

        if context.coordinator.findRequestID != findRequestID || context.coordinator.findQuery != findQuery {
            context.coordinator.findRequestID = findRequestID
            context.coordinator.findQuery = findQuery
            context.coordinator.findBackwards = findBackwards
            context.coordinator.find(in: webView)
        }

        let documentChanged = context.coordinator.html != html || context.coordinator.baseURL != baseURL
        if documentChanged {
            if context.coordinator.documentID == documentID {
                context.coordinator.scrollY = webView.enclosingScrollView?.contentView.bounds.origin.y
            } else {
                context.coordinator.scrollY = nil
            }
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
        var scrollY: CGFloat?
        var findQuery = ""
        var findRequestID = 0
        var findBackwards = false
        var outlineRequestID = 0
        var pendingHeadingID: String?
        var isDocumentLoaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let scrollY, let scrollView = webView.enclosingScrollView {
                let clipView = scrollView.contentView
                var origin = clipView.bounds.origin
                origin.y = scrollY
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
                self.scrollY = nil
            }
            isDocumentLoaded = true
            scrollToPendingHeading(in: webView)
            find(in: webView)
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
