import Foundation

public enum MarkdownInlineFormatting: Equatable, Sendable {
    case bold
    case italic
    case code

    fileprivate var delimiter: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .code: "`"
        }
    }
}

public struct MarkdownShortcutResult: Equatable, Sendable {
    public let source: String
    public let selectionUTF16Offset: Int
    public let selectionUTF16Length: Int

    public init(source: String, selectionUTF16Offset: Int, selectionUTF16Length: Int) {
        self.source = source
        self.selectionUTF16Offset = selectionUTF16Offset
        self.selectionUTF16Length = selectionUTF16Length
    }
}

public enum MarkdownShortcutFormatter {
    public static func apply(
        _ formatting: MarkdownInlineFormatting,
        to source: String,
        selectionUTF16Offset: Int,
        selectionUTF16Length: Int
    ) -> MarkdownShortcutResult {
        let input = source as NSString
        let sourceLength = input.length
        let selectionStart = min(max(selectionUTF16Offset, 0), sourceLength)
        let selectionLength = min(max(selectionUTF16Length, 0), sourceLength - selectionStart)
        let selection = input.substring(with: NSRange(location: selectionStart, length: selectionLength))
        let delimiter = formatting.delimiter
        let delimiterLength = delimiter.utf16.count

        if selectionLength > 0,
           selection.hasPrefix(delimiter),
           selection.hasSuffix(delimiter),
           selection.utf16.count >= delimiterLength * 2 {
            let unwrapped = String(selection.dropFirst(delimiter.count).dropLast(delimiter.count))
            return MarkdownShortcutResult(
                source: input.replacingCharacters(
                    in: NSRange(location: selectionStart, length: selectionLength),
                    with: unwrapped
                ),
                selectionUTF16Offset: selectionStart,
                selectionUTF16Length: unwrapped.utf16.count
            )
        }

        if selectionLength > 0,
           selectionStart >= delimiterLength,
           selectionStart + selectionLength + delimiterLength <= sourceLength,
           input.substring(
               with: NSRange(location: selectionStart - delimiterLength, length: delimiterLength)
           ) == delimiter,
           input.substring(
               with: NSRange(location: selectionStart + selectionLength, length: delimiterLength)
           ) == delimiter {
            let replacementRange = NSRange(
                location: selectionStart - delimiterLength,
                length: selectionLength + delimiterLength * 2
            )
            return MarkdownShortcutResult(
                source: input.replacingCharacters(in: replacementRange, with: selection),
                selectionUTF16Offset: selectionStart - delimiterLength,
                selectionUTF16Length: selectionLength
            )
        }

        if selectionLength == 0 {
            let replacement = delimiter + delimiter
            let result = input.replacingCharacters(
                in: NSRange(location: selectionStart, length: 0),
                with: replacement
            )
            return MarkdownShortcutResult(
                source: result,
                selectionUTF16Offset: selectionStart + delimiterLength,
                selectionUTF16Length: 0
            )
        }

        let replacement = delimiter + selection + delimiter
        return MarkdownShortcutResult(
            source: input.replacingCharacters(
                in: NSRange(location: selectionStart, length: selectionLength),
                with: replacement
            ),
            selectionUTF16Offset: selectionStart + delimiterLength,
            selectionUTF16Length: selectionLength
        )
    }
}
