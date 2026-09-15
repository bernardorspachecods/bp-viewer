import Foundation

public enum JSONSyntaxTokenKind: Hashable, Sendable {
    case punctuation
    case key
    case string
    case number
    case boolean
    case null
    case invalid
}

public struct JSONSyntaxToken: Hashable, Sendable {
    public let kind: JSONSyntaxTokenKind
    public let utf8Offset: Int
    public let utf8Length: Int

    public init(kind: JSONSyntaxTokenKind, utf8Offset: Int, utf8Length: Int) {
        self.kind = kind
        self.utf8Offset = utf8Offset
        self.utf8Length = utf8Length
    }

    public var utf8End: Int {
        utf8Offset + utf8Length
    }
}

public struct JSONSyntaxHighlighter: Sendable {
    public init() {}

    public func tokenize(_ source: String) -> [JSONSyntaxToken] {
        let bytes = Array(source.utf8)
        var tokens: [JSONSyntaxToken] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if isWhitespace(byte) {
                index += 1
                continue
            }

            if isPunctuation(byte) {
                tokens.append(JSONSyntaxToken(kind: .punctuation, utf8Offset: index, utf8Length: 1))
                index += 1
                continue
            }

            if byte == 34 {
                index = tokenizeString(bytes, from: index, into: &tokens)
                continue
            }

            if byte == 45 || (48...57).contains(byte) {
                let start = index
                index += 1
                while index < bytes.count, isNumberByte(bytes[index]) {
                    index += 1
                }
                tokens.append(JSONSyntaxToken(kind: .number, utf8Offset: start, utf8Length: index - start))
                continue
            }

            if let literal = literal(at: index, in: bytes) {
                tokens.append(JSONSyntaxToken(kind: literal.kind, utf8Offset: index, utf8Length: literal.length))
                index += literal.length
                continue
            }

            tokens.append(JSONSyntaxToken(kind: .invalid, utf8Offset: index, utf8Length: 1))
            index += 1
        }

        return tokens
    }

    private func tokenizeString(
        _ bytes: [UInt8],
        from start: Int,
        into tokens: inout [JSONSyntaxToken]
    ) -> Int {
        var index = start + 1
        var invalidOffsets: [Int] = []
        var isClosed = false

        while index < bytes.count {
            switch bytes[index] {
            case 34:
                index += 1
                isClosed = true
            case 92:
                index += min(2, bytes.count - index)
            default:
                if bytes[index] < 32 {
                    invalidOffsets.append(index)
                }
                index += 1
            }

            if isClosed { break }
        }

        let end = index
        let isKey = isClosed && nextNonWhitespaceByte(after: end, in: bytes) == 58
        let stringKind: JSONSyntaxTokenKind = isKey ? .key : .string
        var segmentStart = start

        for invalidOffset in invalidOffsets {
            if invalidOffset > segmentStart {
                tokens.append(JSONSyntaxToken(
                    kind: stringKind,
                    utf8Offset: segmentStart,
                    utf8Length: invalidOffset - segmentStart
                ))
            }
            tokens.append(JSONSyntaxToken(kind: .invalid, utf8Offset: invalidOffset, utf8Length: 1))
            segmentStart = invalidOffset + 1
        }

        if end > segmentStart {
            tokens.append(JSONSyntaxToken(kind: stringKind, utf8Offset: segmentStart, utf8Length: end - segmentStart))
        }
        return end
    }

    private func literal(at index: Int, in bytes: [UInt8]) -> (kind: JSONSyntaxTokenKind, length: Int)? {
        for (literal, kind) in [("true", JSONSyntaxTokenKind.boolean), ("false", .boolean), ("null", .null)] {
            let literalBytes = Array(literal.utf8)
            let end = index + literalBytes.count
            guard end <= bytes.count, bytes[index..<end].elementsEqual(literalBytes) else { continue }
            return (kind, literalBytes.count)
        }
        return nil
    }

    private func nextNonWhitespaceByte(after index: Int, in bytes: [UInt8]) -> UInt8? {
        var next = index
        while next < bytes.count, isWhitespace(bytes[next]) {
            next += 1
        }
        return next < bytes.count ? bytes[next] : nil
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private func isPunctuation(_ byte: UInt8) -> Bool {
        [91, 93, 123, 125, 58, 44].contains(byte)
    }

    private func isNumberByte(_ byte: UInt8) -> Bool {
        byte == 46 || byte == 43 || byte == 45 || byte == 69 || byte == 101 || (48...57).contains(byte)
    }
}
