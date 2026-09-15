import Foundation
import Markdown

public struct MarkdownOutlineEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let level: Int

    public init(id: String, title: String, level: Int) {
        self.id = id
        self.title = title
        self.level = level
    }
}

public struct MarkdownRenderResult: Sendable {
    public let html: String
    public let baseURL: URL
    public let dependencies: [URL]
    public let outline: [MarkdownOutlineEntry]
    public let blocks: [MarkdownEditableBlock]

    public init(
        html: String,
        baseURL: URL,
        dependencies: [URL],
        outline: [MarkdownOutlineEntry] = [],
        blocks: [MarkdownEditableBlock] = []
    ) {
        self.html = html
        self.baseURL = baseURL
        self.dependencies = dependencies
        self.outline = outline
        self.blocks = blocks
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
        let blockDocument = MarkdownBlockDocument(source: source)
        let parsingSource = maskedFrontMatterSource(source, region: blockDocument.specialRegions.first { $0.kind == .frontMatter })
        let document = Document(parsing: parsingSource)
        var renderer = SafeMarkdownHTMLRenderer(
            baseURL: directoryBaseURL,
            source: source,
            editableBlocks: blockDocument.blocks,
            specialRegions: blockDocument.specialRegions
        )
        renderer.visit(document)

        return MarkdownRenderResult(
            html: MarkdownHTMLDocument(body: renderer.html).rendered,
            baseURL: directoryBaseURL,
            dependencies: Array(renderer.dependencies),
            outline: renderer.outline,
            blocks: blockDocument.blocks
        )
    }

    private func maskedFrontMatterSource(_ source: String, region: MarkdownSpecialRegion?) -> String {
        guard let region else { return source }
        var bytes = Array(source.utf8)
        for index in region.sourceRange.startOffset..<region.sourceRange.endOffset {
            if bytes[index] != 10 && bytes[index] != 13 { bytes[index] = 32 }
        }
        return String(decoding: bytes, as: UTF8.self)
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
            [data-bp-block-id] { transition: background-color 120ms ease, outline-color 120ms ease; }
            [data-bp-block-id].bp-editing {
              outline: 2px solid color-mix(in srgb, -apple-system-blue 38%, transparent);
              outline-offset: 5px;
              border-radius: 5px;
              background: color-mix(in srgb, -apple-system-blue 6%, transparent);
            }
            body.bp-document-editing { caret-color: -apple-system-blue; }
            body.bp-document-editing [data-bp-editable="true"] { cursor: text; }
            body.bp-raw-mode > *:not(#bp-raw-editor) { display: none !important; }
            #bp-raw-editor {
              display: block;
              box-sizing: border-box;
              width: 100%;
              min-height: calc(100vh - 80px);
              resize: none;
              border: 0;
              outline: 0;
              padding: 0;
              color: inherit;
              background: transparent;
              font: ui-monospace, SFMono-Regular, Menlo, monospace;
              line-height: 1.55;
              white-space: pre-wrap;
            }
            .bp-special-editor {
              position: fixed;
              z-index: 20;
              top: 16px;
              right: 16px;
              display: grid;
              gap: 8px;
              min-width: 280px;
              padding: 12px;
              border: 1px solid color-mix(in srgb, currentColor 20%, transparent);
              border-radius: 8px;
              background: -apple-system-control-background;
              box-shadow: 0 8px 28px color-mix(in srgb, black 25%, transparent);
              font: -apple-system-caption1;
            }
            .bp-special-editor label { display: grid; gap: 3px; }
            .bp-special-editor input { box-sizing: border-box; width: 100%; }
            .bp-special-editor span { display: flex; justify-content: flex-end; gap: 6px; }
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
            .bp-special-placeholder { cursor: pointer; border: 1px dashed color-mix(in srgb, currentColor 28%, transparent); border-radius: 6px; padding: 10px; color: -apple-system-secondary-label; white-space: pre-wrap; }
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
    let source: String
    let editableBlocks: [MarkdownEditableBlock]
    let specialRegions: [MarkdownSpecialRegion]
    private(set) var html = ""
    private var headingCounts: [String: Int] = [:]
    private let mathRenderer = TeXMathMLRenderer()
    private(set) var dependencies: Set<URL> = []
    private(set) var outline: [MarkdownOutlineEntry] = []

    init(
        baseURL: URL,
        source: String,
        editableBlocks: [MarkdownEditableBlock],
        specialRegions: [MarkdownSpecialRegion]
    ) {
        self.baseURL = baseURL
        self.source = source
        self.editableBlocks = editableBlocks
        self.specialRegions = specialRegions
    }

    mutating func visitDocument(_ document: Document) {
        if let frontMatter = specialRegions.first(where: { $0.kind == .frontMatter }) {
            html += "<pre class=\"bp-special-placeholder\"\(specialAttribute(for: frontMatter))>Front matter\n\(escapeText(frontMatter.source))</pre>\n"
        }
        descendInto(document)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        html += "<blockquote\(editableAttribute(for: blockQuote))>"
        descendInto(blockQuote)
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let languageClass = codeBlock.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
        html += "<pre\(editableAttribute(for: codeBlock))><code\(languageClass)>\(escapeText(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let id = uniqueHeadingID(for: heading.plainText)
        outline.append(
            MarkdownOutlineEntry(
                id: id,
                title: heading.plainText,
                level: heading.level
            )
        )
        let blockAttribute = editableAttribute(for: heading)
        html += "<h\(heading.level) id=\"\(escapeAttribute(id))\"\(blockAttribute)>"
        descendInto(heading)
        html += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        html += "<hr\(editableAttribute(for: thematicBreak)) />\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        html += "<li>"
        if let checkbox = listItem.checkbox {
            let checkedAttribute: String
            switch checkbox {
            case .checked:
                checkedAttribute = " checked"
            case .unchecked:
                checkedAttribute = ""
            }
            html += "<input type=\"checkbox\" data-bp-task-checkbox=\"true\"\(checkedAttribute) disabled /> "
        }
        descendInto(listItem)
        html += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        html += "<ol\(start)\(editableAttribute(for: orderedList))>"
        descendInto(orderedList)
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        html += "<ul\(editableAttribute(for: unorderedList))>"
        descendInto(unorderedList)
        html += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if let blockMath = blockMathSource(in: paragraph.plainText) {
            html += "<div class=\"math-block\"\(editableAttribute(for: paragraph))\(specialAttribute(for: paragraph, kind: .math))>\(mathRenderer.render(blockMath, displayMode: true))</div>\n"
            return
        }

        html += "<p\(editableAttribute(for: paragraph))>"
        descendInto(paragraph)
        html += "</p>\n"
    }

    mutating func visitTable(_ table: Table) {
        html += "<table\(editableAttribute(for: table))>"
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
            html += "<span class=\"missing-image\"\(specialAttribute(for: image, kind: .image))>\(escapeText(image.plainText))</span>"
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
        let markdownSourceAttribute = image.source.map {
            " data-bp-markdown-image-source=\"\(escapeAttribute($0))\""
        } ?? ""
        html += "<img\(specialAttribute(for: image, kind: .image))\(markdownSourceAttribute) src=\"\(escapeAttribute(renderedSource))\" alt=\"\(alt)\""
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
        let renderedDestination = localPreviewLinkDestination(for: destination) ?? destination
        html += "<a href=\"\(escapeAttribute(renderedDestination))\" data-bp-markdown-href=\"\(escapeAttribute(destination))\""
        if let title = link.title, !title.isEmpty {
            html += " title=\"\(escapeAttribute(title))\""
        }
        html += ">"
        descendInto(link)
        html += "</a>"
    }

    private func localPreviewLinkDestination(for source: String) -> String? {
        guard !source.hasPrefix("#"),
              let sourceURL = URL(string: source),
              sourceURL.scheme == nil,
              let resolvedURL = URL(string: source, relativeTo: baseURL)?.absoluteURL,
              let previewURL = MarkdownPreviewLink.url(for: resolvedURL) else {
            return nil
        }

        return previewURL.absoluteString
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        html += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        html += "\n"
    }

    mutating func visitText(_ text: Markdown.Text) {
        let offset = text.range.map { sourceOffset(for: $0.lowerBound) } ?? 0
        html += renderTextWithMath(text.string, sourceOffset: offset)
    }

    // Raw HTML is intentionally omitted until the sanitizer policy is expanded and tested.
    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        guard let range = htmlBlock.range,
              let region = specialRegions.first(where: {
                  $0.kind == .html && $0.sourceRange.startOffset == sourceOffset(for: range.lowerBound)
              }) else { return }
        html += "<pre class=\"bp-special-placeholder\"\(specialAttribute(for: region))>HTML raw\n\(escapeText(region.source))</pre>\n"
    }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        let attribute = inlineHTML.range.flatMap { range in
            specialRegions.first(where: {
                $0.kind == .html && $0.sourceRange.startOffset == sourceOffset(for: range.lowerBound)
            })
        }.map(specialAttribute(for:)) ?? ""
        html += "<span class=\"bp-special-placeholder\"\(attribute)>HTML raw</span>"
    }

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

    private func editableAttribute(for markup: Markup) -> String {
        guard markup.parent is Document,
              let range = markup.range,
              let block = editableBlocks.first(where: {
                  $0.sourceRange.startOffset == sourceOffset(for: range.lowerBound)
              }) else {
            return ""
        }
        let supportAttribute = block.supportsVisualEditing ? "true" : "false"
        return " data-bp-block-id=\"\(escapeAttribute(block.id))\" data-bp-editable=\"\(supportAttribute)\""
    }

    private func specialAttribute(for markup: Markup, kind: MarkdownSpecialKind) -> String {
        guard let range = markup.range,
              let region = specialRegions.first(where: {
                  $0.kind == kind && $0.sourceRange.startOffset == sourceOffset(for: range.lowerBound)
              }) else {
            return ""
        }
        return " data-bp-special-kind=\"\(kind.rawValue)\" data-bp-special-id=\"\(escapeAttribute(region.id))\" data-bp-special-source=\"\(escapeAttribute(region.source))\""
    }

    private func specialAttribute(for region: MarkdownSpecialRegion) -> String {
        " data-bp-special-kind=\"\(region.kind.rawValue)\" data-bp-special-id=\"\(escapeAttribute(region.id))\" data-bp-special-source=\"\(escapeAttribute(region.source))\""
    }

    private func sourceOffset(for location: SourceLocation) -> Int {
        let bytes = Array(source.utf8)
        var line = 1
        var lineStart = 0
        var index = 0
        while index < bytes.count, line < location.line {
            if bytes[index] == 10 {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return min(lineStart + max(location.column - 1, 0), bytes.count)
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

    private func renderTextWithMath(_ value: String, sourceOffset: Int) -> String {
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
            let relativePrefix = nsValue.substring(to: matchRange.location)
            let matchOffset = sourceOffset + relativePrefix.utf8.count
            let attribute = specialRegions.first(where: {
                $0.kind == .math && $0.sourceRange.startOffset == matchOffset
            }).map(specialAttribute(for:)) ?? ""
            result += "<span class=\"math-inline bp-special-placeholder\"\(attribute)>\(mathRenderer.render(source, displayMode: displayMode))</span>"
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
