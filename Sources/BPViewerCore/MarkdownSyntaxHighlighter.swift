import Foundation

public enum MarkdownSyntaxTokenKind: Hashable, Sendable {
    case heading
    case emphasis
    case strong
    case strikethrough
    case code
    case linkText
    case linkDestination
    case listMarker
    case quoteMarker
    case thematicBreak
    case html
    case frontMatter
}

public struct MarkdownSyntaxToken: Hashable, Sendable {
    public let kind: MarkdownSyntaxTokenKind
    public let utf8Offset: Int
    public let utf8Length: Int

    public init(kind: MarkdownSyntaxTokenKind, utf8Offset: Int, utf8Length: Int) {
        self.kind = kind
        self.utf8Offset = utf8Offset
        self.utf8Length = utf8Length
    }

    public var utf8End: Int {
        utf8Offset + utf8Length
    }
}

public struct MarkdownSyntaxHighlighter: Sendable {
    public init() {}

    public func tokenize(_ source: String) -> [MarkdownSyntaxToken] {
        let bytes = Array(source.utf8)
        var tokens: [MarkdownSyntaxToken] = []
        let frontMatterEnd = frontMatterEnd(in: bytes)
        var index = 0
        var fencedStart: Int?
        var fenceCharacter: UInt8 = 0
        var fenceLength = 0

        while index < bytes.count {
            let lineStart = index
            let lineBreak = nextLineBreak(after: lineStart, in: bytes)
            let lineEnd = lineBreak > lineStart && bytes[lineBreak - 1] == 13
                ? lineBreak - 1
                : lineBreak
            let nextLine = lineBreak < bytes.count ? lineBreak + 1 : bytes.count

            if let fenceStart = fencedStart {
                if isClosingFence(
                    bytes,
                    start: lineStart,
                    end: lineEnd,
                    character: fenceCharacter,
                    minimumLength: fenceLength
                ) {
                    append(
                        .code,
                        from: fenceStart,
                        to: nextLine,
                        into: &tokens
                    )
                    fencedStart = nil
                    fenceCharacter = 0
                    fenceLength = 0
                }
                index = nextLine
                continue
            }

            if lineStart < frontMatterEnd {
                if lineStart == 0 {
                    append(.frontMatter, from: 0, to: frontMatterEnd, into: &tokens)
                }
                index = nextLine
                continue
            }

            if let fence = fenceInfo(bytes, start: lineStart, end: lineEnd) {
                fencedStart = lineStart
                fenceCharacter = fence.character
                fenceLength = fence.length
                index = nextLine
                continue
            }

            let contentStart = skipWhitespace(bytes, from: lineStart, to: lineEnd)
            if isHeading(bytes, start: contentStart, end: lineEnd) {
                append(.heading, from: lineStart, to: lineEnd, into: &tokens)
            } else if isThematicBreak(bytes, start: contentStart, end: lineEnd) {
                append(.thematicBreak, from: lineStart, to: lineEnd, into: &tokens)
            } else {
                var inlineStart = lineStart
                if let markerEnd = listMarkerEnd(bytes, start: contentStart, end: lineEnd) {
                    append(.listMarker, from: contentStart, to: markerEnd, into: &tokens)
                    inlineStart = markerEnd
                } else if let markerEnd = quoteMarkerEnd(bytes, start: contentStart, end: lineEnd) {
                    append(.quoteMarker, from: contentStart, to: markerEnd, into: &tokens)
                    inlineStart = markerEnd
                }
                appendInlineTokens(bytes, start: inlineStart, end: lineEnd, into: &tokens)
            }

            index = nextLine
        }

        if let fenceStart = fencedStart {
            append(.code, from: fenceStart, to: bytes.count, into: &tokens)
        }

        return tokens
    }

    private func appendInlineTokens(
        _ bytes: [UInt8],
        start: Int,
        end: Int,
        into tokens: inout [MarkdownSyntaxToken]
    ) {
        var index = start
        while index < end {
            if bytes[index] == 92 {
                index += min(2, end - index)
                continue
            }

            if bytes[index] == 96 {
                let delimiterLength = runLength(of: 96, in: bytes, from: index, to: end)
                if let closing = closingDelimiter(
                    bytes,
                    delimiter: 96,
                    length: delimiterLength,
                    from: index + delimiterLength,
                    to: end
                ) {
                    append(
                        .code,
                        from: index,
                        to: closing + delimiterLength,
                        into: &tokens
                    )
                    index = closing + delimiterLength
                    continue
                }
            }

            if let link = linkRanges(bytes, from: index, to: end) {
                append(.linkText, from: index, to: link.labelEnd, into: &tokens)
                append(.linkDestination, from: link.labelEnd, to: link.destinationEnd, into: &tokens)
                index = link.destinationEnd
                continue
            }

            if let delimiter = emphasisDelimiter(at: index, in: bytes, to: end),
               let closing = closingDelimiter(
                   bytes,
                   delimiter: delimiter.character,
                   length: delimiter.length,
                   from: index + delimiter.length,
                   to: end
               ) {
                let kind: MarkdownSyntaxTokenKind = switch delimiter.length {
                case 2: .strong
                default: .emphasis
                }
                if delimiter.character == 126 {
                    append(.strikethrough, from: index, to: closing + delimiter.length, into: &tokens)
                } else {
                    append(kind, from: index, to: closing + delimiter.length, into: &tokens)
                }
                index = closing + delimiter.length
                continue
            }

            if bytes[index] == 60,
               let closing = bytes[(index + 1)..<end].firstIndex(of: 62) {
                append(.html, from: index, to: closing + 1, into: &tokens)
                index = closing + 1
                continue
            }

            if isURLStart(bytes, at: index, end: end) {
                var destinationEnd = index
                while destinationEnd < end,
                      !isWhitespace(bytes[destinationEnd]) {
                    destinationEnd += 1
                }
                while destinationEnd > index,
                      isTrailingURLPunctuation(bytes[destinationEnd - 1]) {
                    destinationEnd -= 1
                }
                if destinationEnd > index {
                    append(.linkDestination, from: index, to: destinationEnd, into: &tokens)
                    index = destinationEnd
                    continue
                }
            }

            index += 1
        }
    }

    private func frontMatterEnd(in bytes: [UInt8]) -> Int {
        guard lineText(bytes, start: 0, end: nextLineBreak(after: 0, in: bytes)) == "---" else {
            return 0
        }

        var index = nextLineBreak(after: 0, in: bytes)
        if index < bytes.count { index += 1 }
        while index < bytes.count {
            let lineStart = index
            let lineBreak = nextLineBreak(after: lineStart, in: bytes)
            let lineEnd = lineBreak > lineStart && bytes[lineBreak - 1] == 13
                ? lineBreak - 1
                : lineBreak
            let text = lineText(bytes, start: lineStart, end: lineEnd)
            let nextLine = lineBreak < bytes.count ? lineBreak + 1 : bytes.count
            if text == "---" || text == "..." {
                return nextLine
            }
            index = nextLine
        }
        return 0
    }

    private func fenceInfo(_ bytes: [UInt8], start: Int, end: Int) -> (character: UInt8, length: Int)? {
        let markerStart = skipWhitespace(bytes, from: start, to: end, maximum: 3)
        guard markerStart < end, bytes[markerStart] == 96 || bytes[markerStart] == 126 else { return nil }
        let character = bytes[markerStart]
        let length = runLength(of: character, in: bytes, from: markerStart, to: end)
        return length >= 3 ? (character, length) : nil
    }

    private func isClosingFence(
        _ bytes: [UInt8],
        start: Int,
        end: Int,
        character: UInt8,
        minimumLength: Int
    ) -> Bool {
        let markerStart = skipWhitespace(bytes, from: start, to: end, maximum: 3)
        guard markerStart < end, bytes[markerStart] == character else { return false }
        let length = runLength(of: character, in: bytes, from: markerStart, to: end)
        guard length >= minimumLength else { return false }
        let remainderStart = markerStart + length
        return bytes[remainderStart..<end].allSatisfy(isWhitespace)
    }

    private func isHeading(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
        guard start < end, bytes[start] == 35 else { return false }
        let count = runLength(of: 35, in: bytes, from: start, to: end)
        guard (1...6).contains(count) else { return false }
        return start + count == end || isWhitespace(bytes[start + count])
    }

    private func isThematicBreak(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
        guard start < end else { return false }
        let characters = bytes[start..<end].filter { !isWhitespace($0) }
        guard characters.count >= 3, let first = characters.first else { return false }
        guard first == 45 || first == 42 || first == 95 else { return false }
        return characters.allSatisfy { $0 == first }
    }

    private func listMarkerEnd(_ bytes: [UInt8], start: Int, end: Int) -> Int? {
        guard start < end else { return nil }
        if (bytes[start] == 45 || bytes[start] == 42 || bytes[start] == 43),
           start + 1 < end,
           isWhitespace(bytes[start + 1]) {
            return start + 1
        }

        var index = start
        while index < end, (48...57).contains(bytes[index]) { index += 1 }
        guard index > start, index < end, bytes[index] == 46,
              index + 1 < end, isWhitespace(bytes[index + 1]) else { return nil }
        return index + 1
    }

    private func quoteMarkerEnd(_ bytes: [UInt8], start: Int, end: Int) -> Int? {
        guard start < end, bytes[start] == 62 else { return nil }
        return start + 1 < end && isWhitespace(bytes[start + 1]) ? start + 2 : start + 1
    }

    private func linkRanges(_ bytes: [UInt8], from start: Int, to end: Int) -> (labelEnd: Int, destinationEnd: Int)? {
        let bracketStart = bytes[start] == 33 ? start + 1 : start
        guard bracketStart < end, bytes[bracketStart] == 91 else { return nil }
        guard let labelClosing = closingCharacter(93, in: bytes, from: bracketStart + 1, to: end) else { return nil }
        let destinationStart = labelClosing + 1
        guard destinationStart < end, bytes[destinationStart] == 40,
              let destinationClosing = closingCharacter(41, in: bytes, from: destinationStart + 1, to: end) else {
            return nil
        }
        return (labelClosing + 1, destinationClosing + 1)
    }

    private func emphasisDelimiter(at index: Int, in bytes: [UInt8], to end: Int) -> (character: UInt8, length: Int)? {
        guard index < end else { return nil }
        let character = bytes[index]
        guard character == 42 || character == 95 || character == 126 else { return nil }
        let length = runLength(of: character, in: bytes, from: index, to: end)
        guard character == 126 ? length >= 2 : length >= 1 else { return nil }
        if character == 95,
           index > 0,
           !isWhitespace(bytes[index - 1]),
           index + length < end,
           !isWhitespace(bytes[index + length]) {
            return nil
        }
        return (character, character == 126 ? 2 : min(length, 2))
    }

    private func closingDelimiter(
        _ bytes: [UInt8],
        delimiter: UInt8,
        length: Int,
        from start: Int,
        to end: Int
    ) -> Int? {
        var index = start
        while index + length <= end {
            if bytes[index] == 92 {
                index += min(2, end - index)
                continue
            }
            if bytes[index..<(index + length)].allSatisfy({ $0 == delimiter }) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func closingCharacter(_ character: UInt8, in bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        var index = start
        while index < end {
            if bytes[index] == 92 {
                index += min(2, end - index)
                continue
            }
            if bytes[index] == character { return index }
            index += 1
        }
        return nil
    }

    private func isURLStart(_ bytes: [UInt8], at index: Int, end: Int) -> Bool {
        let http = Array("http://".utf8)
        let https = Array("https://".utf8)
        return starts(with: http, in: bytes, at: index, end: end)
            || starts(with: https, in: bytes, at: index, end: end)
    }

    private func starts(with prefix: [UInt8], in bytes: [UInt8], at index: Int, end: Int) -> Bool {
        index + prefix.count <= end && bytes[index..<(index + prefix.count)].elementsEqual(prefix)
    }

    private func isTrailingURLPunctuation(_ byte: UInt8) -> Bool {
        [44, 46, 59, 58, 33, 63].contains(byte)
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private func skipWhitespace(_ bytes: [UInt8], from start: Int, to end: Int, maximum: Int? = nil) -> Int {
        var index = start
        var count = 0
        while index < end, isWhitespace(bytes[index]), maximum.map({ count < $0 }) ?? true {
            index += 1
            count += 1
        }
        return index
    }

    private func runLength(of character: UInt8, in bytes: [UInt8], from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, bytes[index] == character { index += 1 }
        return index - start
    }

    private func nextLineBreak(after start: Int, in bytes: [UInt8]) -> Int {
        bytes[start...].firstIndex(of: 10) ?? bytes.count
    }

    private func lineText(_ bytes: [UInt8], start: Int, end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func append(
        _ kind: MarkdownSyntaxTokenKind,
        from start: Int,
        to end: Int,
        into tokens: inout [MarkdownSyntaxToken]
    ) {
        guard end > start else { return }
        tokens.append(MarkdownSyntaxToken(kind: kind, utf8Offset: start, utf8Length: end - start))
    }
}

public struct MarkdownSyntaxColorPalette: Equatable, Sendable {
    public let background: String
    public let foreground: String
    public let heading: String
    public let emphasis: String
    public let strong: String
    public let strikethrough: String
    public let code: String
    public let linkText: String
    public let linkDestination: String
    public let listMarker: String
    public let quoteMarker: String
    public let thematicBreak: String
    public let html: String
    public let frontMatter: String

    public init(isDark: Bool) {
        self = isDark ? .dark : .light
    }

    public static let light = Self(
        background: "#FFFFFF",
        foreground: "#1F1F1F",
        heading: "#005CC5",
        emphasis: "#005CC5",
        strong: "#005CC5",
        strikethrough: "#A31515",
        code: "#005CC5",
        linkText: "#005CC5",
        linkDestination: "#A31515",
        listMarker: "#6A737D",
        quoteMarker: "#6A737D",
        thematicBreak: "#6A737D",
        html: "#22863A",
        frontMatter: "#6F42C1"
    )

    public static let dark = Self(
        background: "#1E1E1E",
        foreground: "#F5F5F5",
        heading: "#569CD6",
        emphasis: "#569CD6",
        strong: "#569CD6",
        strikethrough: "#CE9178",
        code: "#9CDCFE",
        linkText: "#4FC1FF",
        linkDestination: "#CE9178",
        listMarker: "#808080",
        quoteMarker: "#808080",
        thematicBreak: "#808080",
        html: "#4EC9B0",
        frontMatter: "#C586C0"
    )

    public func color(for kind: MarkdownSyntaxTokenKind) -> String {
        switch kind {
        case .heading: heading
        case .emphasis: emphasis
        case .strong: strong
        case .strikethrough: strikethrough
        case .code: code
        case .linkText: linkText
        case .linkDestination: linkDestination
        case .listMarker: listMarker
        case .quoteMarker: quoteMarker
        case .thematicBreak: thematicBreak
        case .html: html
        case .frontMatter: frontMatter
        }
    }

    private init(
        background: String,
        foreground: String,
        heading: String,
        emphasis: String,
        strong: String,
        strikethrough: String,
        code: String,
        linkText: String,
        linkDestination: String,
        listMarker: String,
        quoteMarker: String,
        thematicBreak: String,
        html: String,
        frontMatter: String
    ) {
        self.background = background
        self.foreground = foreground
        self.heading = heading
        self.emphasis = emphasis
        self.strong = strong
        self.strikethrough = strikethrough
        self.code = code
        self.linkText = linkText
        self.linkDestination = linkDestination
        self.listMarker = listMarker
        self.quoteMarker = quoteMarker
        self.thematicBreak = thematicBreak
        self.html = html
        self.frontMatter = frontMatter
    }
}
