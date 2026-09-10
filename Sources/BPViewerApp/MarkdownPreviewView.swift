import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let html: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.html != html || context.coordinator.baseURL != baseURL else { return }
        context.coordinator.html = html
        context.coordinator.baseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var html: String?
        var baseURL: URL?
    }
}
