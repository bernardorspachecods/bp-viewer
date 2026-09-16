import Foundation

public struct TextSearchMatch: Equatable, Sendable {
    public let utf16Range: Range<Int>

    public init(utf16Range: Range<Int>) {
        self.utf16Range = utf16Range
    }
}

public enum TextSearch {
    public static func matches(in text: String, query: String) -> [TextSearchMatch] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var matches: [TextSearchMatch] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(
                  of: query,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            let start = range.lowerBound.utf16Offset(in: text)
            let end = range.upperBound.utf16Offset(in: text)
            matches.append(TextSearchMatch(utf16Range: start..<end))

            guard range.upperBound < text.endIndex else { break }
            searchStart = range.upperBound
        }

        return matches
    }

    public static func nextMatchIndex(
        currentIndex: Int?,
        matchCount: Int,
        backwards: Bool
    ) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex else { return backwards ? matchCount - 1 : 0 }

        let normalizedIndex = ((currentIndex % matchCount) + matchCount) % matchCount
        let step = backwards ? -1 : 1
        return (normalizedIndex + step + matchCount) % matchCount
    }
}
