import Foundation
import Markdown

public enum SourceEditingMode: String, Codable, CaseIterable, Hashable, Sendable {
    case markdown
    case split
}

public typealias MarkdownEditingMode = SourceEditingMode

public enum MarkdownBlockKind: String, Codable, Hashable, Sendable {
    case paragraph
    case heading
    case orderedList
    case unorderedList
    case blockquote
    case thematicBreak
    case codeBlock
    case table
    case frontMatter
}

public enum MarkdownSpecialKind: String, Codable, Hashable, Sendable {
    case image
    case math
    case html
    case frontMatter
}

public struct MarkdownSourceRange: Hashable, Sendable {
    public let startOffset: Int
    public let endOffset: Int

    public init(startOffset: Int, endOffset: Int) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct MarkdownSpecialRegion: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: MarkdownSpecialKind
    public let sourceRange: MarkdownSourceRange
    public let source: String

    public init(id: String, kind: MarkdownSpecialKind, sourceRange: MarkdownSourceRange, source: String) {
        self.id = id
        self.kind = kind
        self.sourceRange = sourceRange
        self.source = source
    }
}

public struct MarkdownSpecialEdit: Codable, Hashable, Sendable {
    public let id: String
    public let kind: MarkdownSpecialKind
    public let replacement: String

    public init(id: String, kind: MarkdownSpecialKind, replacement: String) {
        self.id = id
        self.kind = kind
        self.replacement = replacement
    }
}

public struct MarkdownEditableBlock: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: MarkdownBlockKind
    public let sourceRange: MarkdownSourceRange
    public let source: String
    public let headingLevel: Int?

    public init(
        id: String,
        kind: MarkdownBlockKind,
        sourceRange: MarkdownSourceRange,
        source: String,
        headingLevel: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceRange = sourceRange
        self.source = source
        self.headingLevel = headingLevel
    }

    public var visualText: String {
        switch kind {
        case .heading:
            return source.replacingOccurrences(
                of: #"^\s{0,3}#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
        case .unorderedList:
            return source
                .split(whereSeparator: \.isNewline)
                .map { $0.replacingOccurrences(of: #"^\s{0,3}[-+*]\s+"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        case .orderedList:
            return source
                .split(whereSeparator: \.isNewline)
                .map { $0.replacingOccurrences(of: #"^\s{0,3}\d+[.)]\s+"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        case .blockquote:
            return source
                .split(whereSeparator: \.isNewline)
                .map { $0.replacingOccurrences(of: #"^\s{0,3}>\s?"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        case .thematicBreak:
            return ""
        case .codeBlock:
            let lines = source.components(separatedBy: .newlines)
            guard lines.count >= 2 else { return source }
            return lines.dropFirst().dropLast().joined(separator: "\n")
        case .table:
            return source
        case .frontMatter:
            return source
        case .paragraph:
            return source
        }
    }

    public var supportsVisualEditing: Bool {
        if kind == .codeBlock || kind == .table { return true }
        if kind == .frontMatter { return false }
        let text = visualText
        return kind != .thematicBreak
            && !text.contains("![")
            && !text.contains("$$")
            && !text.contains("<")
    }

    public func sourceOffset(forRenderedTextOffset offset: Int) -> Int {
        let renderedText = renderedTextForCursor
        let rawCharacters = Array(source)
        let renderedCharacters = Array(renderedText)
        guard !rawCharacters.isEmpty, !renderedCharacters.isEmpty else { return 0 }

        var rawIndex = 0
        var matchingRawIndexes: [Int] = []
        for renderedCharacter in renderedCharacters {
            while rawIndex < rawCharacters.count, rawCharacters[rawIndex] != renderedCharacter {
                rawIndex += 1
            }
            guard rawIndex < rawCharacters.count else { break }
            matchingRawIndexes.append(rawIndex)
            rawIndex += 1
        }

        guard let firstMatch = matchingRawIndexes.first else { return 0 }
        let clampedOffset = max(offset, 0)
        let rawCharacterOffset: Int
        if clampedOffset < matchingRawIndexes.count {
            rawCharacterOffset = matchingRawIndexes[clampedOffset]
        } else {
            rawCharacterOffset = (matchingRawIndexes.last ?? firstMatch) + 1
        }
        let sourceIndex = source.index(
            source.startIndex,
            offsetBy: min(rawCharacterOffset, source.count)
        )
        return source.utf8.distance(from: source.utf8.startIndex, to: sourceIndex)
    }

    private var renderedTextForCursor: String {
        var text = visualText
        text = text.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]+\)"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        return text.replacingOccurrences(
            of: #"(\*\*|__|~~|`|\*|_)"#,
            with: "",
            options: .regularExpression
        )
    }
}

public struct MarkdownVisualEntry: Codable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let kind: MarkdownBlockKind?

    public init(id: String, text: String, kind: MarkdownBlockKind? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

public struct MarkdownVisualInsertion: Codable, Hashable, Sendable {
    public let afterID: String?
    public let kind: MarkdownBlockKind

    public init(afterID: String? = nil, kind: MarkdownBlockKind) {
        self.afterID = afterID
        self.kind = kind
    }
}

public struct MarkdownBlockDocument: Sendable, Equatable {
    public let source: String
    public let blocks: [MarkdownEditableBlock]
    public let specialRegions: [MarkdownSpecialRegion]

    public init(source: String) {
        self.source = source
        self.blocks = MarkdownBlockScanner(source: source).scan()
        self.specialRegions = MarkdownSpecialScanner(source: source).scan()
    }

    public func block(id: String) -> MarkdownEditableBlock? {
        blocks.first { $0.id == id }
    }

    public func replacingBlock(id: String, withSource replacement: String) -> MarkdownBlockDocument {
        guard let block = block(id: id) else { return self }
        return replacing(block, with: replacement)
    }

    public func replacingBlock(id: String, withVisualText text: String) -> MarkdownBlockDocument {
        replacingBlock(id: id, withVisualText: text, kind: nil)
    }

    public func replacingBlock(
        id: String,
        withVisualText text: String,
        kind desiredKind: MarkdownBlockKind?
    ) -> MarkdownBlockDocument {
        guard let block = block(id: id) else { return self }
        let replacement: String
        switch desiredKind ?? block.kind {
        case .heading:
            replacement = headingSource(for: block, text: text)
        case .unorderedList:
            replacement = listSource(for: block, text: text, ordered: false)
        case .orderedList:
            replacement = listSource(for: block, text: text, ordered: true)
        case .blockquote:
            replacement = quoteSource(for: text)
        case .thematicBreak:
            replacement = "---"
        case .codeBlock:
            replacement = fencedCodeSource(for: block, text: text)
        case .table:
            replacement = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .frontMatter:
            replacement = text
        case .paragraph:
            replacement = text
        }
        return replacing(block, with: replacement)
    }

    public func replacingVisualEntries(
        _ entries: [MarkdownVisualEntry],
        insertions: [MarkdownVisualInsertion] = []
    ) -> MarkdownBlockDocument {
        let updated = entries.reduce(self) { document, entry in
            guard let block = document.block(id: entry.id), block.supportsVisualEditing else {
                return document
            }
            return document.replacingBlock(id: entry.id, withVisualText: entry.text, kind: entry.kind)
        }
        return insertions.reduce(updated) { document, insertion in
            document.insertingVisualBlock(insertion)
        }
    }

    public func insertingVisualBlock(_ insertion: MarkdownVisualInsertion) -> MarkdownBlockDocument {
        let sourceToInsert: String
        switch insertion.kind {
        case .thematicBreak:
            sourceToInsert = "---"
        default:
            return self
        }

        if let afterID = insertion.afterID,
           let blockIndex = blocks.firstIndex(where: { $0.id == afterID }) {
            let nextBlock = blocks.dropFirst(blockIndex + 1).first
            if nextBlock?.kind == insertion.kind {
                return self
            }
            let offset = blocks[blockIndex].sourceRange.endOffset
            let bytes = Array(source.utf8)
            let prefix = String(decoding: bytes[..<offset], as: UTF8.self)
            let suffix = String(decoding: bytes[offset...], as: UTF8.self)
            return MarkdownBlockDocument(source: prefix + "\n\n" + sourceToInsert + suffix)
        }

        if blocks.first?.kind == insertion.kind {
            return self
        }
        return MarkdownBlockDocument(source: sourceToInsert + (source.isEmpty ? "" : "\n\n" + source))
    }

    public func replacingSpecialEdits(_ edits: [MarkdownSpecialEdit]) -> MarkdownBlockDocument {
        edits.reduce(self) { document, edit in
            document.replacingSpecialRegion(id: edit.id, kind: edit.kind, withSource: edit.replacement)
        }
    }

    public func replacingSpecialRegion(
        id: String,
        kind: MarkdownSpecialKind,
        withSource replacement: String
    ) -> MarkdownBlockDocument {
        guard let region = specialRegions.first(where: { $0.id == id && $0.kind == kind }) else { return self }
        let bytes = Array(source.utf8)
        let prefix = String(decoding: bytes[..<region.sourceRange.startOffset], as: UTF8.self)
        let suffix = String(decoding: bytes[region.sourceRange.endOffset...], as: UTF8.self)
        return MarkdownBlockDocument(source: prefix + replacement + suffix)
    }

    private func replacing(_ block: MarkdownEditableBlock, with replacement: String) -> MarkdownBlockDocument {
        let bytes = Array(source.utf8)
        let prefix = String(decoding: bytes[..<block.sourceRange.startOffset], as: UTF8.self)
        let suffix = String(decoding: bytes[block.sourceRange.endOffset...], as: UTF8.self)
        return MarkdownBlockDocument(source: prefix + replacement + suffix)
    }

    private func headingSource(for block: MarkdownEditableBlock, text: String) -> String {
        let prefix = block.source.firstMatch(of: #/^\s{0,3}#{1,6}\s+/#)?.output ?? Substring("# ")
        return String(prefix) + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func listSource(for block: MarkdownEditableBlock, text: String, ordered: Bool) -> String {
        let originalLines = block.source.split(whereSeparator: \.isNewline).map(String.init)
        let sourceMarkers = originalLines.compactMap { line -> String? in
            listMarker(in: line, ordered: ordered)
        }
        let fallback = ordered ? "1. " : "- "
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.enumerated().map { index, line in
            let marker = index < sourceMarkers.count ? sourceMarkers[index] : fallback
            return marker + line.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    private func listMarker(in line: String, ordered: Bool) -> String? {
        if ordered {
            return line.firstMatch(of: #/^\s{0,3}\d+[.)]\s+/#).map { String($0.output) }
        }
        return line.firstMatch(of: #/^\s{0,3}[-+*]\s+/#).map { String($0.output) }
    }

    private func quoteSource(for text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { "> " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    private func fencedCodeSource(for block: MarkdownEditableBlock, text: String) -> String {
        let lines = block.source.components(separatedBy: .newlines)
        guard lines.count >= 2,
              let opening = lines.first,
              let closing = lines.last,
              isFenceLine(closing, matching: opening) else {
            return text
        }

        let newline = block.source.contains("\r\n") ? "\r\n" : "\n"
        return ([opening] + text.components(separatedBy: .newlines) + [closing]).joined(separator: newline)
    }

    private func isFenceLine(_ line: String, matching opening: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let openingTrimmed = opening.trimmingCharacters(in: .whitespaces)
        guard let character = openingTrimmed.first,
              (character == "`" || character == "~") else { return false }
        let length = openingTrimmed.prefix { $0 == character }.count
        let closingPrefix = String(repeating: character, count: length)
        return trimmed.hasPrefix(closingPrefix)
            && trimmed.dropFirst(length).allSatisfy { $0 == character || $0.isWhitespace }
    }
}

private struct MarkdownSpecialScanner {
    let source: String

    func scan() -> [MarkdownSpecialRegion] {
        (imageRegions() + mathRegions() + inlineMathRegions() + htmlRegions() + inlineHTMLRegions() + frontMatterRegions())
            .sorted { $0.sourceRange.startOffset < $1.sourceRange.startOffset }
    }

    private func imageRegions() -> [MarkdownSpecialRegion] {
        var result: [MarkdownSpecialRegion] = []
        var cursor = source.startIndex

        while cursor < source.endIndex {
            guard let marker = source.range(of: "![", range: cursor..<source.endIndex),
                  let destinationStart = source.range(of: "](", range: marker.upperBound..<source.endIndex),
                  let closing = source.range(of: ")", range: destinationStart.upperBound..<source.endIndex) else {
                break
            }

            let range = MarkdownSourceRange(
                startOffset: utf8Offset(of: marker.lowerBound),
                endOffset: utf8Offset(of: closing.upperBound)
            )
            result.append(
                MarkdownSpecialRegion(
                    id: "markdown-special-image-\(range.startOffset)",
                    kind: .image,
                    sourceRange: range,
                    source: String(source[marker.lowerBound..<closing.upperBound])
                )
            )
            cursor = closing.upperBound
        }

        return result
    }

    private func utf8Offset(of index: String.Index) -> Int {
        source.utf8.distance(from: source.utf8.startIndex, to: index)
    }

    private func mathRegions() -> [MarkdownSpecialRegion] {
        let lines = sourceLines()
        var result: [MarkdownSpecialRegion] = []
        var index = 0
        while index < lines.count {
            let opening = lines[index].text.trimmingCharacters(in: .whitespaces)
            guard opening == "$$" || opening == "\\[" else {
                index += 1
                continue
            }
            guard let closing = lines[(index + 1)...].first(where: {
                let value = $0.text.trimmingCharacters(in: .whitespaces)
                return value == (opening == "$$" ? "$$" : "\\]")
            }) else {
                index += 1
                continue
            }
            let range = MarkdownSourceRange(startOffset: lines[index].start, endOffset: closing.contentEnd)
            result.append(region(kind: .math, range: range, idPrefix: "math"))
            index = lines.firstIndex(where: { $0.start == closing.start }).map { $0 + 1 } ?? lines.count
        }
        return result
    }

    private func htmlRegions() -> [MarkdownSpecialRegion] {
        let lines = sourceLines()
        var result: [MarkdownSpecialRegion] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<"), trimmed.contains(">") else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < lines.count,
                  !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  lines[index].text.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
                index += 1
            }
            let range = MarkdownSourceRange(startOffset: lines[start].start, endOffset: lines[index - 1].contentEnd)
            result.append(region(kind: .html, range: range, idPrefix: "html"))
        }
        return result
    }

    private func inlineMathRegions() -> [MarkdownSpecialRegion] {
        regions(matching: #"\$([^$\n]+)\$|\\\(([^)]+)\\\)"#, kind: .math, idPrefix: "math")
    }

    private func inlineHTMLRegions() -> [MarkdownSpecialRegion] {
        regions(matching: #"</?[A-Za-z][^>]*>"#, kind: .html, idPrefix: "html")
    }

    private func regions(
        matching pattern: String,
        kind: MarkdownSpecialKind,
        idPrefix: String
    ) -> [MarkdownSpecialRegion] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(location: 0, length: (source as NSString).length)
        return expression.matches(in: source, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            let sourceRange = MarkdownSourceRange(
                startOffset: utf8Offset(of: range.lowerBound),
                endOffset: utf8Offset(of: range.upperBound)
            )
            return region(kind: kind, range: sourceRange, idPrefix: idPrefix)
        }
    }

    private func frontMatterRegions() -> [MarkdownSpecialRegion] {
        let lines = sourceLines()
        guard let first = lines.first,
              first.text.trimmingCharacters(in: .whitespaces) == "---",
              let closing = lines.dropFirst().first(where: {
                  let value = $0.text.trimmingCharacters(in: .whitespaces)
                  return value == "---" || value == "..."
              }) else { return [] }
        let range = MarkdownSourceRange(startOffset: first.start, endOffset: closing.contentEnd)
        return [region(kind: .frontMatter, range: range, idPrefix: "front-matter")]
    }

    private func region(
        kind: MarkdownSpecialKind,
        range: MarkdownSourceRange,
        idPrefix: String
    ) -> MarkdownSpecialRegion {
        let bytes = Array(source.utf8)
        return MarkdownSpecialRegion(
            id: "markdown-special-\(idPrefix)-\(range.startOffset)",
            kind: kind,
            sourceRange: range,
            source: String(decoding: bytes[range.startOffset..<range.endOffset], as: UTF8.self)
        )
    }

    private struct SourceLine {
        let start: Int
        let contentEnd: Int
        let text: String
    }

    private func sourceLines() -> [SourceLine] {
        let bytes = Array(source.utf8)
        var lines: [SourceLine] = []
        var start = 0
        var index = 0
        while index <= bytes.count {
            if index == bytes.count || bytes[index] == 10 {
                let rawEnd = index
                let contentEnd = rawEnd > start && bytes[rawEnd - 1] == 13 ? rawEnd - 1 : rawEnd
                lines.append(SourceLine(
                    start: start,
                    contentEnd: contentEnd,
                    text: String(decoding: bytes[start..<contentEnd], as: UTF8.self)
                ))
                start = index + 1
            }
            index += 1
        }
        if lines.last?.start == bytes.count + 1 { lines.removeLast() }
        return lines
    }
}

private struct MarkdownBlockScanner {
    let source: String

    func scan() -> [MarkdownEditableBlock] {
        let lines = sourceLines()
        var result: [MarkdownEditableBlock] = []
        var index = 0

        while index < lines.count {
            guard !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                index += 1
                continue
            }

            let start = index
            let kind: MarkdownBlockKind
            let detectedHeadingLevel: Int?

            if index == 0, let end = frontMatterEnd(from: index, lines: lines) {
                kind = .frontMatter
                detectedHeadingLevel = nil
                index = end
            } else if let level = self.headingLevel(in: lines[index].text) {
                kind = .heading
                detectedHeadingLevel = level
                index += 1
            } else if let fence = fencedCodeStart(in: lines[index].text) {
                kind = .codeBlock
                detectedHeadingLevel = nil
                index = consumeFencedCode(from: index, lines: lines, fence: fence)
            } else if isTableStart(at: index, lines: lines) {
                kind = .table
                detectedHeadingLevel = nil
                index = consumeTable(from: index, lines: lines)
            } else if isThematicBreak(lines[index].text) {
                kind = .thematicBreak
                detectedHeadingLevel = nil
                index += 1
            } else if isBlockQuoteLine(lines[index].text) {
                kind = .blockquote
                detectedHeadingLevel = nil
                index = consumeBlockQuote(from: index, lines: lines)
            } else if isListLine(lines[index].text, ordered: true) {
                kind = .orderedList
                detectedHeadingLevel = nil
                index = consumeList(from: index, lines: lines, ordered: true)
            } else if isListLine(lines[index].text, ordered: false) {
                kind = .unorderedList
                detectedHeadingLevel = nil
                index = consumeList(from: index, lines: lines, ordered: false)
            } else {
                kind = .paragraph
                detectedHeadingLevel = nil
                index += 1
                while index < lines.count,
                      !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      self.headingLevel(in: lines[index].text) == nil,
                      self.fencedCodeStart(in: lines[index].text) == nil,
                      !self.isTableStart(at: index, lines: lines),
                      !isThematicBreak(lines[index].text),
                      !isBlockQuoteLine(lines[index].text),
                      !isListLine(lines[index].text, ordered: true),
                      !isListLine(lines[index].text, ordered: false) {
                    index += 1
                }
            }

            let first = lines[start]
            let last = lines[index - 1]
            let range = MarkdownSourceRange(startOffset: first.start, endOffset: last.contentEnd)
            let blockSource = substring(range)
            result.append(
                MarkdownEditableBlock(
                    id: "markdown-block-\(result.count + 1)",
                    kind: kind,
                    sourceRange: range,
                    source: blockSource,
                    headingLevel: detectedHeadingLevel
                )
            )
        }

        return result
    }

    private func sourceLines() -> [SourceLine] {
        let bytes = Array(source.utf8)
        var lines: [SourceLine] = []
        var start = 0
        var index = 0

        while index <= bytes.count {
            if index == bytes.count || bytes[index] == 10 {
                let rawEnd = index
                let contentEnd = rawEnd > start && bytes[rawEnd - 1] == 13 ? rawEnd - 1 : rawEnd
                let text = String(decoding: bytes[start..<contentEnd], as: UTF8.self)
                lines.append(SourceLine(start: start, contentEnd: contentEnd, text: text))
                start = index + 1
            }
            index += 1
        }

        if lines.last?.start == bytes.count + 1 {
            lines.removeLast()
        }
        return lines
    }

    private func substring(_ range: MarkdownSourceRange) -> String {
        let bytes = Array(source.utf8)
        return String(decoding: bytes[range.startOffset..<range.endOffset], as: UTF8.self)
    }

    private func headingLevel(in line: String) -> Int? {
        guard let match = line.firstMatch(of: #/^\s{0,3}(#{1,6})(?:\s+|$)/#) else { return nil }
        return match.output.1.count
    }

    private func isListLine(_ line: String, ordered: Bool) -> Bool {
        let pattern = ordered
            ? #/^\s{0,3}\d+[.)]\s+/#
            : #/^\s{0,3}[-+*]\s+/#
        return line.firstMatch(of: pattern) != nil
    }

    private func isThematicBreak(_ line: String) -> Bool {
        line.firstMatch(of: #/^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$/#) != nil
    }

    private func fencedCodeStart(in line: String) -> (character: Character, length: Int)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let character = trimmed.first, character == "`" || character == "~" else { return nil }
        let length = trimmed.prefix { $0 == character }.count
        return length >= 3 ? (character, length) : nil
    }

    private func consumeFencedCode(
        from start: Int,
        lines: [SourceLine],
        fence: (character: Character, length: Int)
    ) -> Int {
        var index = start + 1
        while index < lines.count {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            let prefix = String(repeating: fence.character, count: fence.length)
            if trimmed.hasPrefix(prefix),
               trimmed.dropFirst(fence.length).allSatisfy({ $0 == fence.character || $0.isWhitespace }) {
                return index + 1
            }
            index += 1
        }
        return index
    }

    private func isTableStart(at index: Int, lines: [SourceLine]) -> Bool {
        guard index + 1 < lines.count,
              isTableRow(lines[index].text),
              isTableDelimiter(lines[index + 1].text) else { return false }
        return true
    }

    private func consumeTable(from start: Int, lines: [SourceLine]) -> Int {
        var index = start + 2
        while index < lines.count,
              !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isTableRow(lines[index].text) {
            index += 1
        }
        return index
    }

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cells = tableCells(in: trimmed)
        return cells.count >= 1 && cells.contains { !$0.isEmpty }
    }

    private func frontMatterEnd(from start: Int, lines: [SourceLine]) -> Int? {
        guard lines[start].text.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var index = start + 1
        while index < lines.count {
            let value = lines[index].text.trimmingCharacters(in: .whitespaces)
            if value == "---" || value == "..." { return index + 1 }
            index += 1
        }
        return nil
    }

    private func isTableDelimiter(_ line: String) -> Bool {
        let cells = tableCells(in: line.trimmingCharacters(in: .whitespaces))
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            var characters = Array(value)
            if characters.first == ":" { characters.removeFirst() }
            if characters.last == ":" { characters.removeLast() }
            return characters.count >= 3 && characters.allSatisfy { $0 == "-" }
        }
    }

    private func tableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private func isBlockQuoteLine(_ line: String) -> Bool {
        line.firstMatch(of: #/^\s{0,3}>/#) != nil
    }

    private func consumeBlockQuote(from start: Int, lines: [SourceLine]) -> Int {
        var index = start
        while index < lines.count, isBlockQuoteLine(lines[index].text) {
            index += 1
        }
        return index
    }

    private func consumeList(from start: Int, lines: [SourceLine], ordered: Bool) -> Int {
        var index = start
        while index < lines.count {
            let text = lines[index].text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            if index == start || isListLine(text, ordered: ordered) || text.first == " " || text.first == "\t" {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private struct SourceLine {
        let start: Int
        let contentEnd: Int
        let text: String
    }
}

private extension Substring {
    var isNewline: Bool { first == "\n" || first == "\r" }
}
