import Foundation

public enum LatexSyntaxTokenKind: Hashable, Sendable {
    case command
    case comment
    case environment
    case argument
    case math
}

public struct LatexSyntaxToken: Hashable, Sendable {
    public let kind: LatexSyntaxTokenKind
    public let utf8Offset: Int
    public let utf8Length: Int

    public init(kind: LatexSyntaxTokenKind, utf8Offset: Int, utf8Length: Int) {
        self.kind = kind
        self.utf8Offset = utf8Offset
        self.utf8Length = utf8Length
    }

    public var utf8End: Int { utf8Offset + utf8Length }
}

public struct LatexSyntaxHighlighter: Sendable {
    public init() {}

    public func tokenize(_ source: String) -> [LatexSyntaxToken] {
        let bytes = Array(source.utf8)
        var tokens: [LatexSyntaxToken] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37 { // %
                let start = index
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { index += 1 }
                append(.comment, start, index, into: &tokens)
                continue
            }

            if bytes[index] == 36 { // $
                let start = index
                let delimiterLength = index + 1 < bytes.count && bytes[index + 1] == 36 ? 2 : 1
                index += 1
                if delimiterLength == 2 { index += 1 }
                while index < bytes.count {
                    guard bytes[index] == 36 else {
                        index += 1
                        continue
                    }
                    let closingLength = index + 1 < bytes.count && bytes[index + 1] == 36 ? 2 : 1
                    index += closingLength
                    break
                }
                append(.math, start, index, into: &tokens)
                continue
            }

            if bytes[index] == 92 { // \
                let start = index
                index += 1
                while index < bytes.count, isLetter(bytes[index]) { index += 1 }
                if index == start + 1, index < bytes.count { index += 1 }
                let command = String(decoding: bytes[(start + 1)..<index], as: UTF8.self)
                append(command == "begin" || command == "end" ? .environment : .command,
                       start, index, into: &tokens)
                continue
            }

            if bytes[index] == 123 || bytes[index] == 91 { // { or [
                let opening = bytes[index]
                let closing: UInt8 = opening == 123 ? 125 : 93
                let start = index
                index += 1
                var depth = 1
                while index < bytes.count, depth > 0 {
                    if bytes[index] == opening { depth += 1 }
                    if bytes[index] == closing { depth -= 1 }
                    index += 1
                }
                append(.argument, start, index, into: &tokens)
                continue
            }

            index += 1
        }
        return tokens
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 64
    }

    private func append(
        _ kind: LatexSyntaxTokenKind,
        _ start: Int,
        _ end: Int,
        into tokens: inout [LatexSyntaxToken]
    ) {
        guard end > start else { return }
        tokens.append(LatexSyntaxToken(kind: kind, utf8Offset: start, utf8Length: end - start))
    }
}

public struct LatexSyntaxColorPalette: Equatable, Sendable {
    public let background: String
    public let foreground: String
    public let command: String
    public let comment: String
    public let environment: String
    public let argument: String
    public let math: String

    public init(
        background: String,
        foreground: String,
        command: String,
        comment: String,
        environment: String,
        argument: String,
        math: String
    ) {
        self.background = background
        self.foreground = foreground
        self.command = command
        self.comment = comment
        self.environment = environment
        self.argument = argument
        self.math = math
    }

    public init(isDark: Bool) { self = isDark ? .dark : .light }

    public static let light = Self(
        background: "#FFFFFF", foreground: "#1F1F1F", command: "#7A3E9D",
        comment: "#6A737D", environment: "#005CC5", argument: "#22863A", math: "#A31515"
    )

    public static let dark = Self(
        background: "#1E1E1E", foreground: "#F5F5F5", command: "#C586C0",
        comment: "#6A9955", environment: "#569CD6", argument: "#4EC9B0", math: "#CE9178"
    )

    public func color(for kind: LatexSyntaxTokenKind) -> String {
        switch kind {
        case .command: command
        case .comment: comment
        case .environment: environment
        case .argument: argument
        case .math: math
        }
    }
}
