import SwiftUI
import WebKit
import BPViewerCore

struct MarkdownPreviewView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let documentID: String
    let onNavigate: (URL) -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool

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

        guard context.coordinator.html != html || context.coordinator.baseURL != baseURL else { return }
        if context.coordinator.documentID == documentID {
            context.coordinator.scrollY = webView.enclosingScrollView?.contentView.bounds.origin.y
        } else {
            context.coordinator.scrollY = nil
        }
        context.coordinator.documentID = documentID
        context.coordinator.html = html
        context.coordinator.baseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let scrollY, let scrollView = webView.enclosingScrollView {
                let clipView = scrollView.contentView
                var origin = clipView.bounds.origin
                origin.y = scrollY
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
                self.scrollY = nil
            }
            find(in: webView)
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
