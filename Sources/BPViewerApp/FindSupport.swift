import AppKit
import Foundation
@preconcurrency import PDFKit
import WebKit

@MainActor
enum WebViewFindSupport {
    static func find(in webView: WKWebView, query: String, backwards: Bool) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    static func countMatches(
        in webView: WKWebView,
        query: String,
        onCount: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encodedQuery = try? String(
                  data: JSONEncoder().encode(query),
                  encoding: .utf8
              ) else {
            onCount(0)
            return
        }

        let script = """
        (() => {
            const query = \(encodedQuery);
            const normalize = value => value
                .normalize('NFD')
                .replace(/[\\u0300-\\u036f]/g, '')
                .toLocaleLowerCase();
            const needle = normalize(query);
            const haystack = normalize(document.body?.innerText || '');
            if (!needle) return 0;
            let count = 0;
            let start = 0;
            while (true) {
                const index = haystack.indexOf(needle, start);
                if (index < 0) break;
                count += 1;
                start = index + needle.length;
            }
            return count;
        })();
        """

        webView.evaluateJavaScript(script) { result, _ in
            onCount((result as? NSNumber)?.intValue ?? 0)
        }
    }
}

class FindTrackingWKWebView: WKWebView {
    var onFindFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFindFocus?()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        onFindFocus?()
        super.mouseDown(with: event)
    }
}

class FindTrackingPDFView: PDFView {
    var onFindFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFindFocus?()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        onFindFocus?()
        super.mouseDown(with: event)
    }
}
