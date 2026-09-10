import Foundation
import Markdown

public struct MarkdownRenderResult: Sendable {
    public let html: String
    public let baseURL: URL
    public let dependencies: [URL]

    public init(html: String, baseURL: URL, dependencies: [URL]) {
        self.html = html
        self.baseURL = baseURL
        self.dependencies = dependencies
    }
}

public protocol MarkdownAdapter: Sendable {
    func render(source: String, baseURL: URL) throws -> MarkdownRenderResult
}

public struct SwiftMarkdownAdapter: MarkdownAdapter {
    public init() {}

    public func render(source: String, baseURL: URL) throws -> MarkdownRenderResult {
        let directoryBaseURL = baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.appendingPathComponent("", isDirectory: true)
        let document = Document(parsing: source)
        var renderer = SafeMarkdownHTMLRenderer(baseURL: directoryBaseURL)
        renderer.visit(document)

        return MarkdownRenderResult(
            html: MarkdownHTMLDocument(body: renderer.html).rendered,
            baseURL: directoryBaseURL,
            dependencies: Array(renderer.dependencies)
        )
    }
}

private struct MarkdownHTMLDocument {
    let body: String

    var rendered: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: file: http: https:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0 auto;
              max-width: 860px;
              padding: 40px 52px 80px;
              color: -apple-system-label;
              background: -apple-system-background;
              font: -apple-system-body;
              line-height: 1.55;
            }
            h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin-top: 1.5em; scroll-margin-top: 24px; }
            h1:first-child { margin-top: 0; }
            a { color: -apple-system-blue; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            code { padding: 0.12em 0.3em; border-radius: 4px; background: color-mix(in srgb, currentColor 10%, transparent); }
            pre { overflow-x: auto; padding: 16px; border-radius: 8px; background: color-mix(in srgb, currentColor 8%, transparent); }
            pre code { padding: 0; background: transparent; }
            blockquote { margin-left: 0; padding-left: 16px; border-left: 3px solid color-mix(in srgb, currentColor 25%, transparent); }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid color-mix(in srgb, currentColor 20%, transparent); padding: 8px 10px; text-align: left; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

private struct SafeMarkdownHTMLRenderer: MarkupWalker {
    let baseURL: URL
    private(set) var html = ""
    private var headingCounts: [String: Int] = [:]
    private let mathRenderer = TeXMathMLRenderer()
    private(set) var dependencies: Set<URL> = []

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    mutating func visitDocument(_ document: Document) {
        descendInto(document)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        html += "<blockquote>"
        descendInto(blockQuote)
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let languageClass = codeBlock.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
        html += "<pre><code\(languageClass)>\(escapeText(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let id = uniqueHeadingID(for: heading.plainText)
        html += "<h\(heading.level) id=\"\(escapeAttribute(id))\">"
        descendInto(heading)
        html += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        html += "<hr />\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        html += "<li>"
        descendInto(listItem)
        html += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        html += "<ol\(start)>"
        descendInto(orderedList)
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        html += "<ul>"
        descendInto(unorderedList)
        html += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if let blockMath = blockMathSource(in: paragraph.plainText) {
            html += "<div class=\"math-block\">\(mathRenderer.render(blockMath, displayMode: true))</div>\n"
            return
        }

        html += "<p>"
        descendInto(paragraph)
        html += "</p>\n"
    }

    mutating func visitTable(_ table: Table) {
        html += "<table>"
        descendInto(table)
        html += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        html += "<thead>"
        descendInto(tableHead)
        html += "</thead>"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        html += "<tbody>"
        descendInto(tableBody)
        html += "</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        html += "<tr>"
        descendInto(tableRow)
        html += "</tr>"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        let tag = tableCell.parent is Table.Head ? "th" : "td"
        html += "<\(tag)>"
        descendInto(tableCell)
        html += "</\(tag)>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        html += "<code>\(escapeText(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        html += "<em>"
        descendInto(emphasis)
        html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        html += "<strong>"
        descendInto(strong)
        html += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        html += "<del>"
        descendInto(strikethrough)
        html += "</del>"
    }

    mutating func visitImage(_ image: Markdown.Image) {
        guard let source = safeURL(image.source) else {
            html += "<span class=\"missing-image\">\(escapeText(image.plainText))</span>"
            return
        }
        var renderedSource = source
        if let resourceURL = localResourceURL(for: source) {
            dependencies.insert(resourceURL)
            if let embeddedSource = embeddedImageSource(for: resourceURL) {
                renderedSource = embeddedSource
            }
        }
        let alt = escapeAttribute(image.plainText)
        html += "<img src=\"\(escapeAttribute(renderedSource))\" alt=\"\(alt)\""
        if let title = image.title, !title.isEmpty {
            html += " title=\"\(escapeAttribute(title))\""
        }
        html += " />"
    }

    mutating func visitLink(_ link: Markdown.Link) {
        guard let destination = safeURL(link.destination) else {
            descendInto(link)
            return
        }
        html += "<a href=\"\(escapeAttribute(destination))\""
        if let title = link.title, !title.isEmpty {
            html += " title=\"\(escapeAttribute(title))\""
        }
        html += ">"
        descendInto(link)
        html += "</a>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        html += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        html += "\n"
    }

    mutating func visitText(_ text: Markdown.Text) {
        html += renderTextWithMath(text.string)
    }

    // Raw HTML is intentionally omitted until the sanitizer policy is expanded and tested.
    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {}
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {}

    private func safeURL(_ rawURL: String?) -> String? {
        guard let rawURL, !rawURL.isEmpty else { return nil }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isNewline || $0.isWhitespace }) else { return nil }

        if let scheme = URL(string: trimmed)?.scheme?.lowercased(),
           ["javascript", "vbscript", "data", "file", "blob"].contains(scheme) {
            return nil
        }
        return trimmed
    }

    private func localResourceURL(for source: String) -> URL? {
        guard URL(string: source)?.scheme == nil else { return nil }
        return baseURL.appendingPathComponent(source).standardizedFileURL
    }

    private func embeddedImageSource(for url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let mimeType = imageMIMEType(for: url.pathExtension) else {
            return nil
        }

        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func imageMIMEType(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "avif": return "image/avif"
        case "bmp": return "image/bmp"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "jpeg", "jpg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func renderTextWithMath(_ value: String) -> String {
        let pattern = #"\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$([^$\n]+)\$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return escapeText(value)
        }

        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        var result = ""
        var cursor = 0

        expression.enumerateMatches(in: value, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            if matchRange.location > cursor {
                result += escapeText(nsValue.substring(with: NSRange(location: cursor, length: matchRange.location - cursor)))
            }

            let displayMode = match.range(at: 1).location != NSNotFound || match.range(at: 2).location != NSNotFound
            let captureIndex = displayMode ? (match.range(at: 1).location != NSNotFound ? 1 : 2) : (match.range(at: 3).location != NSNotFound ? 3 : 4)
            let source = nsValue.substring(with: match.range(at: captureIndex))
            result += mathRenderer.render(source, displayMode: displayMode)
            cursor = matchRange.location + matchRange.length
        }

        if cursor < nsValue.length {
            result += escapeText(nsValue.substring(from: cursor))
        }
        return result
    }

    private func blockMathSource(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
        }
        if trimmed.hasPrefix("\\["), trimmed.hasSuffix("\\]"), trimmed.count >= 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
        }
        return nil
    }

    private mutating func uniqueHeadingID(for value: String) -> String {
        let base = value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let normalizedBase = base.isEmpty ? "section" : base
        let count = headingCounts[normalizedBase, default: 0]
        headingCounts[normalizedBase] = count + 1
        return count == 0 ? normalizedBase : "\(normalizedBase)-\(count + 1)"
    }
}
