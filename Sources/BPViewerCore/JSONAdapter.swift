import Foundation

public struct JSONPreviewAdapter: Sendable {
    public init() {}

    public func format(source: String) throws -> String {
        guard let data = source.data(using: .utf8) else {
            throw JSONPreviewError.invalidEncoding
        }

        do {
            var parser = OrderedJSONParser(bytes: Array(data))
            return render(try parser.parse(), indent: 0)
        } catch let error as JSONPreviewError {
            throw error
        } catch let error as OrderedJSONParser.ParseError {
            throw JSONPreviewError.invalidJSON(error.localizedDescription)
        } catch {
            throw JSONPreviewError.invalidJSON(error.localizedDescription)
        }
    }

    public func sourceOffset(
        forFormattedUTF8Offset formattedOffset: Int,
        source: String,
        formattedSource: String
    ) -> Int {
        let sourceBytes = Array(source.utf8)
        let formattedBytes = Array(formattedSource.utf8)
        guard !formattedBytes.isEmpty else { return 0 }

        var sourceIndex = 0
        var offsets = Array(repeating: 0, count: formattedBytes.count + 1)

        for formattedIndex in formattedBytes.indices {
            while sourceIndex < sourceBytes.count, isJSONWhitespace(sourceBytes[sourceIndex]) {
                sourceIndex += 1
            }
            offsets[formattedIndex] = sourceIndex

            let byte = formattedBytes[formattedIndex]
            guard !isJSONWhitespace(byte) else { continue }

            if sourceIndex < sourceBytes.count, sourceBytes[sourceIndex] == byte {
                sourceIndex += 1
            } else if let match = sourceBytes[sourceIndex...].firstIndex(of: byte) {
                sourceIndex = match + 1
            }
        }

        offsets[formattedBytes.count] = sourceIndex
        let clampedOffset = min(max(formattedOffset, 0), formattedBytes.count)
        return offsets[clampedOffset]
    }

    private func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private func render(_ value: OrderedJSONValue, indent: Int) -> String {
        let indentation = String(repeating: "  ", count: indent)
        let childIndentation = String(repeating: "  ", count: indent + 1)

        switch value {
        case let .scalar(raw):
            return raw
        case let .object(entries):
            guard !entries.isEmpty else { return "{}" }
            let lines = entries.enumerated().map { index, entry in
                let suffix = index == entries.count - 1 ? "" : ","
                return "\(childIndentation)\(entry.key) : \(render(entry.value, indent: indent + 1))\(suffix)"
            }
            return "{\n\(lines.joined(separator: "\n"))\n\(indentation)}"
        case let .array(values):
            guard !values.isEmpty else { return "[]" }
            let lines = values.enumerated().map { index, value in
                let suffix = index == values.count - 1 ? "" : ","
                return "\(childIndentation)\(render(value, indent: indent + 1))\(suffix)"
            }
            return "[\n\(lines.joined(separator: "\n"))\n\(indentation)]"
        }
    }
}

private enum OrderedJSONValue {
    case object([(key: String, value: OrderedJSONValue)])
    case array([OrderedJSONValue])
    case scalar(String)
}

private struct OrderedJSONParser {
    struct ParseError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parse() throws -> OrderedJSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw error("carácter inesperado na posição \(index)")
        }
        return value
    }

    private mutating func parseValue() throws -> OrderedJSONValue {
        guard let byte = currentByte else {
            throw error("valor em falta na posição \(index)")
        }

        switch byte {
        case 34:
            return .scalar(try parseString())
        case 91:
            return try parseArray()
        case 123:
            return try parseObject()
        case 45, 48...57:
            return .scalar(try parseNumber())
        case 102:
            try parseLiteral("false")
            return .scalar("false")
        case 110:
            try parseLiteral("null")
            return .scalar("null")
        case 116:
            try parseLiteral("true")
            return .scalar("true")
        default:
            throw error("valor inesperado na posição \(index)")
        }
    }

    private mutating func parseObject() throws -> OrderedJSONValue {
        advance()
        skipWhitespace()
        var entries: [(key: String, value: OrderedJSONValue)] = []

        if consume(125) {
            return .object(entries)
        }

        while true {
            guard currentByte == 34 else {
                throw error("a chave do objeto tem de ser uma string na posição \(index)")
            }
            let key = try parseString()
            skipWhitespace()
            guard consume(58) else {
                throw error("faltam dois pontos depois da chave na posição \(index)")
            }
            skipWhitespace()
            entries.append((key: key, value: try parseValue()))
            skipWhitespace()

            if consume(125) {
                return .object(entries)
            }
            guard consume(44) else {
                throw error("faltam vírgula ou fim do objeto na posição \(index)")
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws -> OrderedJSONValue {
        advance()
        skipWhitespace()
        var values: [OrderedJSONValue] = []

        if consume(93) {
            return .array(values)
        }

        while true {
            values.append(try parseValue())
            skipWhitespace()

            if consume(93) {
                return .array(values)
            }
            guard consume(44) else {
                throw error("faltam vírgula ou fim do array na posição \(index)")
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(34) else {
            throw error("string esperada na posição \(index)")
        }

        while let byte = currentByte {
            switch byte {
            case 34:
                advance()
                return String(decoding: bytes[start..<index], as: UTF8.self)
            case 92:
                advance()
                guard let escape = currentByte else {
                    throw error("escape incompleto na posição \(index)")
                }
                if escape == 117 {
                    advance()
                    for _ in 0..<4 {
                        guard let hex = currentByte, isHexDigit(hex) else {
                            throw error("escape Unicode inválido na posição \(index)")
                        }
                        advance()
                    }
                } else if [34, 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                    advance()
                } else {
                    throw error("escape inválido na posição \(index)")
                }
            case 0...31:
                throw error("carácter de controlo numa string na posição \(index)")
            default:
                advance()
            }
        }

        throw error("string não terminada na posição \(index)")
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        _ = consume(45)

        if consume(48) {
            if let byte = currentByte, byte >= 48 && byte <= 57 {
                throw error("zero à esquerda num número na posição \(index)")
            }
        } else {
            guard consumeDigit(minimum: 1) else {
                throw error("número inválido na posição \(index)")
            }
        }

        if consume(46) {
            guard consumeDigit(minimum: 1) else {
                throw error("faltam dígitos depois do ponto na posição \(index)")
            }
        }

        if let byte = currentByte, byte == 101 || byte == 69 {
            advance()
            _ = consume(43) || consume(45)
            guard consumeDigit(minimum: 1) else {
                throw error("faltam dígitos no expoente na posição \(index)")
            }
        }

        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseLiteral(_ literal: String) throws {
        let literalBytes = Array(literal.utf8)
        guard bytes[index...].starts(with: literalBytes) else {
            throw error("literal inválido na posição \(index)")
        }
        index += literalBytes.count
    }

    private mutating func consumeDigit(minimum: Int) -> Bool {
        let start = index
        while let byte = currentByte, byte >= 48 && byte <= 57 {
            advance()
        }
        return index - start >= minimum
    }

    private func isHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 70)
            || (byte >= 97 && byte <= 102)
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte, byte == 9 || byte == 10 || byte == 13 || byte == 32 {
            advance()
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        advance()
        return true
    }

    private mutating func advance() {
        index += 1
    }

    private var currentByte: UInt8? {
        guard index < bytes.count else { return nil }
        return bytes[index]
    }

    private func error(_ message: String) -> ParseError {
        let positionMarker = " na posição \(index)"
        let location = sourceLocation()
        let localizedMessage = message.replacingOccurrences(
            of: positionMarker,
            with: " na linha \(location.line), carácter \(location.character)"
        )
        return ParseError(message: localizedMessage)
    }

    private func sourceLocation() -> (line: Int, character: Int) {
        let clampedIndex = min(index, bytes.count)
        let prefix = String(decoding: bytes[..<clampedIndex], as: UTF8.self)
        let line = prefix.reduce(into: 1) { result, character in
            if character == "\n" {
                result += 1
            }
        }
        let character = prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0
        return (line, character + 1)
    }
}

public enum JSONPreviewError: LocalizedError, Sendable, Equatable {
    case invalidEncoding
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "O ficheiro JSON não está codificado em UTF-8."
        case let .invalidJSON(details):
            return "JSON inválido: \(details)"
        }
    }
}
