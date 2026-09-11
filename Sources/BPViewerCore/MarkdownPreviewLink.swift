import Foundation

/// URL bridge used by the Markdown preview for explicit local-file navigation.
///
/// A local file URL is not used directly in the generated HTML because a
/// document loaded with `WKWebView.loadHTMLString` may expose the link in the
/// context menu without producing a navigation action for the relative file
/// destination. The app-owned URL makes that navigation explicit while the
/// actual file path remains in a query item.
public enum MarkdownPreviewLink {
    public static let scheme = "bpviewer"
    public static let host = "open-local-file"

    public static func url(for fileURL: URL) -> URL? {
        guard fileURL.isFileURL else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.standardizedFileURL.path)
        ]
        components.fragment = fileURL.fragment
        return components.url
    }

    public static func fileURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}
