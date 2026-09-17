import Foundation

/// Resolves the source location behind a citation rendered in a LaTeX PDF.
///
/// SyncTeX normally points at the citation command in the `.tex` source. The
/// editor can then use the citation key to open the corresponding `.bib`
/// entry instead of leaving the user in the root document.
public enum LatexCitationLookup {
    public static func citationKey(atUTF8Offset offset: Int, in source: String) -> String? {
        let pattern = #"\\[A-Za-z@]*cite[A-Za-z@*]*\s*(?:\[[^\]]*\]\s*)*\{([^{}]*)\}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let sourceNSString = source as NSString
        let range = NSRange(location: 0, length: sourceNSString.length)
        let utf16Offset = utf16Offset(in: source, utf8Offset: offset)
        let matches = expression.matches(in: source, range: range)
        if let match = matches.first(where: {
            utf16Offset >= $0.range.location && utf16Offset <= NSMaxRange($0.range)
        }) {
            return key(
                from: match,
                clickedUTF16Offset: utf16Offset,
                source: sourceNSString
            )
        }

        // SyncTeX often reports Column:-1 for generated text. In that case
        // the offset is the beginning of the line, so resolve a citation
        // anywhere on that line instead of falling back to the root source.
        let lineLocation = min(max(utf16Offset, 0), sourceNSString.length)
        let lineRange = sourceNSString.lineRange(
            for: NSRange(location: lineLocation, length: 0)
        )
        guard let match = matches.first(where: {
            NSIntersectionRange($0.range, lineRange).length > 0
        }) else { return nil }
        return key(from: match, clickedUTF16Offset: utf16Offset, source: sourceNSString)
    }

    public static func bibliographyEntryOffset(for key: String, in source: String) -> Int? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^[ \t]*@[A-Za-z][A-Za-z0-9_-]*\s*[\{\(]\s*"#
            + escapedKey
            + #"\s*[,\)]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let sourceNSString = source as NSString
        let range = NSRange(location: 0, length: sourceNSString.length)
        guard let match = expression.firstMatch(in: source, range: range) else { return nil }
        return sourceNSString.substring(to: match.range.location).utf8.count
    }

    public static func keyInGeneratedBibliography(atLine line: Int, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard line > 0, line <= lines.count else { return nil }
        let pattern = #"\\(?:bibitem(?:\[[^\]]*\])?|entry)\s*\{([^{}]+)\}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        for rawLine in lines.prefix(line).reversed() {
            let text = String(rawLine)
            if text.contains(#"\end{thebibliography}"#) { return nil }
            let range = NSRange(location: 0, length: (text as NSString).length)
            guard let match = expression.firstMatch(in: text, range: range) else { continue }
            return (text as NSString).substring(with: match.range(at: 1))
        }
        return nil
    }

    private static func utf16Offset(in source: String, utf8Offset: Int) -> Int {
        let safeOffset = min(max(utf8Offset, 0), source.utf8.count)
        return String(decoding: source.utf8.prefix(safeOffset), as: UTF8.self).utf16.count
    }

    private static func key(
        from match: NSTextCheckingResult,
        clickedUTF16Offset: Int,
        source: NSString
    ) -> String? {
        let keys = source
            .substring(with: match.range(at: 1))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !keys.isEmpty else { return nil }

        let keyRange = match.range(at: 1)
        guard NSLocationInRange(clickedUTF16Offset, keyRange) else { return keys.first }

        let clickedKeyOffset = clickedUTF16Offset - keyRange.location
        var cursor = 0
        for key in keys {
            let keyEnd = cursor + (key as NSString).length
            if clickedKeyOffset <= keyEnd { return key }
            cursor = keyEnd
            while cursor < keyRange.length,
                  source.substring(
                      with: NSRange(location: keyRange.location + cursor, length: 1)
                  ).first?.isWhitespace == true {
                cursor += 1
            }
        }
        return keys.last
    }

}
