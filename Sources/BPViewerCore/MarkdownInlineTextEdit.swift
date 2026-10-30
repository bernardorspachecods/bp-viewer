extension MarkdownBlockDocument {
    /// Maps an edit of one block's rendered text back onto the Markdown source.
    /// `unitIndex` addresses a list item; paragraphs and headings use nil.
    /// Returns the full new source, or nil when the edit cannot be applied safely.
    public func applyingInlineTextEdit(
        blockID: String,
        unitIndex: Int?,
        originalText: String,
        editedText: String
    ) -> String? {
        guard let block = block(id: blockID), block.supportsVisualEditing else { return nil }
        let bytes = Array(source.utf8)
        guard let unit = InlineEditUnit.range(of: block, unitIndex: unitIndex, bytes: bytes) else { return nil }
        var scanner = InlineTextScanner(bytes: bytes, range: unit)
        let textMap = scanner.scan()
        guard textMap.entries.map(\.character) == Array(originalText),
              !editedText.isEmpty,
              editedText != originalText else { return nil }

        let original = Array(originalText)
        let edited = Array(editedText)
        let shared = min(original.count, edited.count)
        var prefix = 0
        while prefix < shared, original[prefix] == edited[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shared - prefix,
              original[original.count - 1 - suffix] == edited[edited.count - 1 - suffix] {
            suffix += 1
        }

        let rendered = prefix..<(original.count - suffix)
        let inserted = String(edited[prefix..<(edited.count - suffix)])
        guard let span = sourceSpan(for: rendered, in: textMap) else { return nil }
        let replacement = escapedInsertion(inserted, atParagraphStart: block.kind == .paragraph && prefix == 0)
        return String(
            decoding: Array(bytes[..<span.lowerBound]) + Array(replacement.utf8) + Array(bytes[span.upperBound...]),
            as: UTF8.self
        )
    }
}

private struct InlineEntry {
    let character: Character
    let start: Int
    let end: Int
    let isLocked: Bool
}

private struct InlineMarker {
    let start: Int
    let end: Int
    var pairID: Int
    let isOpen: Bool
}

private struct InlineTextMap {
    let entries: [InlineEntry]
    let markers: [InlineMarker]
}

private enum InlineEditUnit {
    static func range(of block: MarkdownEditableBlock, unitIndex: Int?, bytes: [UInt8]) -> Range<Int>? {
        let blockRange = block.sourceRange.startOffset..<block.sourceRange.endOffset
        switch block.kind {
        case .paragraph:
            guard unitIndex == nil else { return nil }
            return trimmed(blockRange, bytes: bytes)
        case .heading:
            guard unitIndex == nil else { return nil }
            return headingContent(blockRange, bytes: bytes)
        case .unorderedList, .orderedList:
            guard let unitIndex else { return nil }
            let items = lines(in: blockRange, bytes: bytes).filter { !isBlank($0, bytes: bytes) }
            let contents = items.map { listItemContent($0, bytes: bytes) }
            guard contents.allSatisfy({ $0 != nil }), contents.indices.contains(unitIndex) else { return nil }
            return contents[unitIndex]
        default:
            return nil
        }
    }

    private static func lines(in range: Range<Int>, bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var lineStart = range.lowerBound
        var index = range.lowerBound
        while index <= range.upperBound {
            if index == range.upperBound || bytes[index] == 10 {
                var lineEnd = index
                if lineEnd > lineStart, bytes[lineEnd - 1] == 13 { lineEnd -= 1 }
                result.append(lineStart..<lineEnd)
                lineStart = index + 1
            }
            index += 1
        }
        return result
    }

    private static func trimmed(_ range: Range<Int>, bytes: [UInt8]) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, isBlankByte(bytes[lower]) { lower += 1 }
        while upper > lower, isBlankByte(bytes[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    private static func headingContent(_ range: Range<Int>, bytes: [UInt8]) -> Range<Int>? {
        let line = String(decoding: bytes[range], as: UTF8.self)
        guard let opening = line.firstMatch(of: #/^\s{0,3}#{1,6}\s+/#) else { return nil }
        var end = line.endIndex
        if let closing = line[opening.range.upperBound...].firstMatch(of: #/\s+#+\s*$/#) {
            end = closing.range.lowerBound
        }
        return offset(opening.range.upperBound, in: line, base: range.lowerBound)
            ..< offset(end, in: line, base: range.lowerBound)
    }

    private static func listItemContent(_ range: Range<Int>, bytes: [UInt8]) -> Range<Int>? {
        let line = String(decoding: bytes[range], as: UTF8.self)
        guard let marker = line.firstMatch(of: #/^\s*([-+*]|\d+[.)])\s+(\[[ xX]\]\s+)?/#) else { return nil }
        var end = line.endIndex
        while end > marker.range.upperBound, line[line.index(before: end)].isWhitespace {
            end = line.index(before: end)
        }
        return offset(marker.range.upperBound, in: line, base: range.lowerBound)
            ..< offset(end, in: line, base: range.lowerBound)
    }

    private static func offset(_ index: String.Index, in text: String, base: Int) -> Int {
        base + text.utf8.distance(from: text.utf8.startIndex, to: index)
    }

    private static func isBlank(_ range: Range<Int>, bytes: [UInt8]) -> Bool {
        bytes[range].allSatisfy(isBlankByte)
    }

    private static func isBlankByte(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13
    }
}

/// Builds one entry per rendered character of a unit, plus the Markdown markers that render to nothing.
private struct InlineTextScanner {
    private struct Cell {
        let character: Character
        let start: Int
        let end: Int
    }

    private let cells: [Cell]
    private let skipped: [Bool]
    private var entries: [InlineEntry] = []
    private var markers: [InlineMarker] = []
    private var openers: [(delimiter: String, markerIndex: Int)] = []
    private var linkCloses: [Int: (parenthesis: Int, pairID: Int)] = [:]
    private var pairCount = 0

    init(bytes: [UInt8], range: Range<Int>) {
        var offset = range.lowerBound
        var cells: [Cell] = []
        for character in String(decoding: bytes[range], as: UTF8.self) {
            let end = offset + character.utf8.count
            cells.append(Cell(character: character, start: offset, end: end))
            offset = end
        }
        self.cells = cells
        self.skipped = Self.skippedBlanks(in: cells)
    }

    mutating func scan() -> InlineTextMap {
        var index = 0
        while index < cells.count {
            if skipped[index] {
                index += 1
            } else if let close = linkCloses[index] {
                markers.append(InlineMarker(
                    start: cells[index].start,
                    end: cells[close.parenthesis].end,
                    pairID: close.pairID,
                    isOpen: false
                ))
                index = close.parenthesis + 1
            } else {
                index = scanToken(at: index)
            }
        }

        for markerIndex in markers.indices where markers[markerIndex].pairID >= 0 {
            let pairID = markers[markerIndex].pairID
            if markers.filter({ $0.pairID == pairID }).count != 2 {
                markers[markerIndex].pairID = -1
            }
        }
        return InlineTextMap(entries: entries, markers: markers)
    }

    private static func skippedBlanks(in cells: [Cell]) -> [Bool] {
        var skipped = Array(repeating: false, count: cells.count)
        var index = 0
        while index < cells.count {
            guard isBlank(cells[index].character) else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd < cells.count, isBlank(cells[runEnd].character) {
                runEnd += 1
            }
            let afterNewline = index > 0 && cells[index - 1].character.isNewline
            let beforeNewline = runEnd < cells.count && cells[runEnd].character.isNewline
            if afterNewline || beforeNewline {
                for position in index..<runEnd {
                    skipped[position] = true
                }
            }
            index = runEnd
        }
        return skipped
    }

    private static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private mutating func scanToken(at index: Int) -> Int {
        if let next = scanEscape(at: index) { return next }
        if let next = scanCode(at: index) { return next }
        if let next = scanLink(at: index) { return next }
        if let next = scanDelimiter(at: index) { return next }
        appendEntry(at: index, isLocked: false)
        return index + 1
    }

    private mutating func scanEscape(at index: Int) -> Int? {
        guard cells[index].character == "\\",
              index + 1 < cells.count,
              isASCIIPunctuation(cells[index + 1].character) else { return nil }
        entries.append(InlineEntry(
            character: cells[index + 1].character,
            start: cells[index].start,
            end: cells[index + 1].end,
            isLocked: false
        ))
        return index + 2
    }

    private mutating func scanCode(at index: Int) -> Int? {
        guard cells[index].character == "`" else { return nil }
        let length = runLength(at: index, of: "`")
        let contentStart = index + length
        guard let closing = closingBackticks(length: length, from: contentStart) else {
            for position in index..<contentStart {
                appendEntry(at: position, isLocked: false)
            }
            return contentStart
        }

        let pairID = nextPairID()
        markers.append(InlineMarker(
            start: cells[index].start,
            end: cells[contentStart - 1].end,
            pairID: pairID,
            isOpen: true
        ))
        for position in contentStart..<closing where !skipped[position] {
            appendEntry(at: position, isLocked: true)
        }
        markers.append(InlineMarker(
            start: cells[closing].start,
            end: cells[closing + length - 1].end,
            pairID: pairID,
            isOpen: false
        ))
        return closing + length
    }

    private func closingBackticks(length: Int, from start: Int) -> Int? {
        var position = start
        while position < cells.count {
            guard cells[position].character == "`" else {
                position += 1
                continue
            }
            let run = runLength(at: position, of: "`")
            if run == length { return position }
            position += run
        }
        return nil
    }

    private mutating func scanLink(at index: Int) -> Int? {
        guard cells[index].character == "[", let close = linkClose(after: index) else { return nil }
        let pairID = nextPairID()
        markers.append(InlineMarker(
            start: cells[index].start,
            end: cells[index].end,
            pairID: pairID,
            isOpen: true
        ))
        linkCloses[close.bracket] = (close.parenthesis, pairID)
        return index + 1
    }

    private func linkClose(after index: Int) -> (bracket: Int, parenthesis: Int)? {
        guard let bracket = cells[(index + 1)...].firstIndex(where: { $0.character == "]" }),
              bracket + 1 < cells.count,
              cells[bracket + 1].character == "(",
              let parenthesis = cells[(bracket + 2)...].firstIndex(where: { $0.character == ")" }) else {
            return nil
        }
        return (bracket, parenthesis)
    }

    private mutating func scanDelimiter(at index: Int) -> Int? {
        let character = cells[index].character
        guard character == "*" || character == "_" || character == "~" else { return nil }
        let length = runLength(at: index, of: character)
        let end = index + length
        let isIntraword = character == "_"
            && index > 0
            && end < cells.count
            && isWordCharacter(cells[index - 1].character)
            && isWordCharacter(cells[end].character)
        let isDelimiter = character == "~" ? length == 2 : length <= 2
        guard isDelimiter, !isIntraword else {
            for position in index..<end {
                appendEntry(at: position, isLocked: false)
            }
            return end
        }

        let delimiter = String(repeating: character, count: length)
        let start = cells[index].start
        let stop = cells[end - 1].end
        let canClose = index > 0 && !cells[index - 1].character.isWhitespace
        let canOpen = end < cells.count && !cells[end].character.isWhitespace
        if canClose, let opener = openers.lastIndex(where: { $0.delimiter == delimiter }) {
            let pairID = nextPairID()
            markers[openers[opener].markerIndex].pairID = pairID
            markers.append(InlineMarker(start: start, end: stop, pairID: pairID, isOpen: false))
            openers.removeSubrange(opener...)
        } else {
            markers.append(InlineMarker(start: start, end: stop, pairID: -1, isOpen: canOpen))
            if canOpen {
                openers.append((delimiter, markers.count - 1))
            }
        }
        return end
    }

    private func runLength(at index: Int, of character: Character) -> Int {
        var end = index
        while end < cells.count, cells[end].character == character {
            end += 1
        }
        return end - index
    }

    private mutating func nextPairID() -> Int {
        pairCount += 1
        return pairCount - 1
    }

    private mutating func appendEntry(at index: Int, isLocked: Bool) {
        let cell = cells[index]
        entries.append(InlineEntry(character: cell.character, start: cell.start, end: cell.end, isLocked: isLocked))
    }
}

/// Source bytes to replace for a rendered range. An empty range is a pure insertion point.
/// A deletion or replacement takes every Markdown pair that touches the span: a pair whose content lies
/// entirely in the range goes whole; a pair that keeps some content may not lose just one of its markers.
private func sourceSpan(for rendered: Range<Int>, in map: InlineTextMap) -> Range<Int>? {
    let entries = map.entries
    let markers = map.markers
    guard rendered.upperBound <= entries.count else { return nil }

    if rendered.isEmpty {
        if rendered.lowerBound > 0, !entries[rendered.lowerBound - 1].isLocked {
            let position = entries[rendered.lowerBound - 1].end
            return position..<position
        }
        if rendered.lowerBound < entries.count, !entries[rendered.lowerBound].isLocked {
            let position = entries[rendered.lowerBound].start
            return position..<position
        }
        return nil
    }

    guard !entries[rendered].contains(where: \.isLocked) else { return nil }
    guard let pairs = markerPairs(in: markers) else { return nil }
    var span = entries[rendered.lowerBound].start..<entries[rendered.upperBound - 1].end
    var removed = Set<Int>()
    var changed = true
    while changed {
        changed = false
        for (index, pair) in pairs.enumerated() where !removed.contains(index) && touches(pair, span) {
            let content = entries.indices.filter { entries[$0].start >= pair.opener.end && entries[$0].end <= pair.closer.start }
            guard content.allSatisfy({ rendered.contains($0) }) else { continue }
            span = min(span.lowerBound, pair.opener.start)..<max(span.upperBound, pair.closer.end)
            removed.insert(index)
            changed = true
        }
    }

    for pair in pairs where touches(pair, span) {
        let markersInside = [pair.opener, pair.closer].filter { isInside($0, span) }.count
        if markersInside == 1 { return nil }
    }
    guard !markers.contains(where: { $0.pairID < 0 && isInside($0, span) }) else { return nil }
    return span
}

private struct MarkerPair {
    let opener: InlineMarker
    let closer: InlineMarker
}

private func markerPairs(in markers: [InlineMarker]) -> [MarkerPair]? {
    var pairs: [MarkerPair] = []
    for pairID in Set(markers.map(\.pairID)).sorted() where pairID >= 0 {
        let pair = markers.filter { $0.pairID == pairID }
        guard pair.count == 2,
              let opener = pair.first(where: \.isOpen),
              let closer = pair.first(where: { !$0.isOpen }) else { return nil }
        pairs.append(MarkerPair(opener: opener, closer: closer))
    }
    return pairs
}

private func touches(_ pair: MarkerPair, _ span: Range<Int>) -> Bool {
    [pair.opener, pair.closer].contains { marker in
        isInside(marker, span) || marker.end == span.lowerBound || marker.start == span.upperBound
    }
}

private func isInside(_ marker: InlineMarker, _ span: Range<Int>) -> Bool {
    marker.start >= span.lowerBound && marker.end <= span.upperBound
}

private func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
}

private func isASCIIPunctuation(_ character: Character) -> Bool {
    guard let value = character.asciiValue else { return false }
    return (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value) || (123...126).contains(value)
}

private let inlineMarkupCharacters: Set<Character> = ["\\", "*", "_", "`", "[", "]", "<", "$", "~", "&"]

private func escapedInsertion(_ text: String, atParagraphStart: Bool) -> String {
    var escaped = ""
    for character in text {
        if character.isNewline {
            escaped += " "
            continue
        }
        if inlineMarkupCharacters.contains(character) {
            escaped += "\\"
        }
        escaped.append(character)
    }
    guard atParagraphStart else { return escaped }
    if let number = escaped.firstMatch(of: #/^\d+[.)]/#) {
        escaped.insert("\\", at: escaped.index(before: number.range.upperBound))
    } else if let first = escaped.first, "#>-+".contains(first) {
        escaped.insert("\\", at: escaped.startIndex)
    }
    return escaped
}
