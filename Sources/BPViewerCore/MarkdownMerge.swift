import Foundation

public enum MarkdownMergeResult: Equatable, Sendable {
    case merged(String)
    case conflict(base: String, local: String, external: String, blockIDs: [String])

    public var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }
}

public enum MarkdownThreeWayMerge {
    public static func resolve(base: String, local: String, external: String) -> MarkdownMergeResult {
        if local == base { return .merged(external) }
        if external == base { return .merged(local) }
        if local == external { return .merged(local) }

        let baseDocument = MarkdownBlockDocument(source: base)
        let localDocument = MarkdownBlockDocument(source: local)
        let externalDocument = MarkdownBlockDocument(source: external)

        guard compatibleStructure(baseDocument, localDocument),
              compatibleStructure(baseDocument, externalDocument) else {
            return .conflict(base: base, local: local, external: external, blockIDs: [])
        }

        var replacements: [(MarkdownSourceRange, String)] = []
        var conflicts: [String] = []

        for index in baseDocument.blocks.indices {
            let baseBlock = baseDocument.blocks[index]
            let localSource = localDocument.blocks[index].source
            let externalSource = externalDocument.blocks[index].source

            if localSource == baseBlock.source {
                if externalSource != baseBlock.source {
                    replacements.append((baseBlock.sourceRange, externalSource))
                }
            } else if externalSource == baseBlock.source || localSource == externalSource {
                replacements.append((baseBlock.sourceRange, localSource))
            } else {
                conflicts.append(baseBlock.id)
            }
        }

        guard conflicts.isEmpty else {
            return .conflict(base: base, local: local, external: external, blockIDs: conflicts)
        }

        return .merged(apply(replacements, to: base))
    }

    private static func compatibleStructure(
        _ lhs: MarkdownBlockDocument,
        _ rhs: MarkdownBlockDocument
    ) -> Bool {
        lhs.blocks.count == rhs.blocks.count
            && zip(lhs.blocks, rhs.blocks).allSatisfy { $0.kind == $1.kind }
    }

    private static func apply(
        _ replacements: [(MarkdownSourceRange, String)],
        to source: String
    ) -> String {
        let sorted = replacements.sorted { $0.0.startOffset > $1.0.startOffset }
        var result = source
        for (range, replacement) in sorted {
            let bytes = Array(result.utf8)
            let prefix = String(decoding: bytes[..<range.startOffset], as: UTF8.self)
            let suffix = String(decoding: bytes[range.endOffset...], as: UTF8.self)
            result = prefix + replacement + suffix
        }
        return result
    }
}
