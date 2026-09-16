import AppKit
import BPViewerCore

/// Builds the shared vertical coordinate map used by both sides of a diff.
/// The input is a logical diff row; the output contains the source and line
/// metadata needed by the two source views. All height decisions use the same
/// AppKit text metrics as `SourceTextView`.
struct DocumentDiffLayout {
    let referenceSource: String
    let referenceLineNumberOverrides: [Int: Int]
    let referenceLineHighlights: [Int: DocumentDiffCellKind]
    let referenceLineSpacingBefore: [Int: CGFloat]
    let editedLineSpacingBefore: [Int: CGFloat]

    init(
        diff: DocumentDiff,
        panelWidth: CGFloat,
        zoom: Double,
        monospaced: Bool
    ) {
        referenceSource = diff.rows
            .map { $0.left?.text ?? "" }
            .joined(separator: "\n")
        referenceLineNumberOverrides = Dictionary(
            uniqueKeysWithValues: diff.rows.enumerated().compactMap { index, row in
                guard let left = row.left else { return nil }
                return (index + 1, left.lineNumber)
            }
        )
        referenceLineHighlights = Dictionary(
            uniqueKeysWithValues: diff.rows.enumerated().compactMap { index, row in
                guard let left = row.left,
                      left.kind != .unchanged else { return nil }
                return (index + 1, left.kind)
            }
        )

        var rowHeights: [Int: CGFloat] = [:]
        var referenceLineHeights: [Int: CGFloat] = [:]
        var editedLineHeights: [Int: CGFloat] = [:]

        for (index, row) in diff.rows.enumerated() {
            let referenceHeight = SourceEditorLayout.measuredLineHeight(
                for: row.left?.text,
                panelWidth: panelWidth,
                zoom: zoom,
                monospaced: monospaced
            )
            let editedHeight = SourceEditorLayout.measuredLineHeight(
                for: row.right?.text,
                panelWidth: panelWidth,
                zoom: zoom,
                monospaced: monospaced
            )
            referenceLineHeights[index + 1] = referenceHeight
            if let right = row.right {
                editedLineHeights[right.lineNumber] = editedHeight
            }
            rowHeights[row.id] = max(referenceHeight, editedHeight)
        }

        var referenceSpacing: [Int: CGFloat] = [:]
        var editedSpacing: [Int: CGFloat] = [:]
        var pendingReferenceSpacing: CGFloat = 0
        var pendingEditedSpacing: CGFloat = 0
        let minimumRowHeight = SourceEditorLayout.codeLineHeight * zoom

        for (index, row) in diff.rows.enumerated() {
            let referenceLine = index + 1
            referenceSpacing[referenceLine] = pendingReferenceSpacing
            pendingReferenceSpacing = 0

            if let right = row.right {
                editedSpacing[right.lineNumber] = pendingEditedSpacing
                pendingEditedSpacing = 0
            }

            let rowHeight = max(
                minimumRowHeight,
                rowHeights[row.id] ?? minimumRowHeight
            )
            let referenceHeight = max(
                minimumRowHeight,
                referenceLineHeights[referenceLine] ?? minimumRowHeight
            )
            let editedHeight = row.right.map {
                max(
                    minimumRowHeight,
                    editedLineHeights[$0.lineNumber] ?? minimumRowHeight
                )
            } ?? 0

            pendingReferenceSpacing += max(0, rowHeight - referenceHeight)
            pendingEditedSpacing += max(0, rowHeight - editedHeight)
        }

        referenceLineSpacingBefore = referenceSpacing
        editedLineSpacingBefore = editedSpacing
    }
}
