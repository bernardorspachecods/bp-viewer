import AppKit
import BPViewerCore
import SwiftUI

enum SourceEditorLineNumbering {
    static func lineCount(in source: String) -> Int {
        source.utf16.reduce(into: 1) { count, codeUnit in
            if codeUnit == 10 {
                count += 1
            }
        }
    }

    static func lineNumber(atUTF16Offset offset: Int, in source: String) -> Int {
        let sourceNSString = source as NSString
        let clampedOffset = min(max(offset, 0), sourceNSString.length)
        let prefix = sourceNSString.substring(to: clampedOffset)
        return lineCount(in: prefix)
    }
}

enum SourceEditorLayout {
    static let contentMaxWidth: CGFloat = 860
    static let horizontalPadding: CGFloat = 52
    static let verticalPadding: CGFloat = 40
    static let lineNumberGutterWidth: CGFloat = 44
    static let lineNumberFontSize: CGFloat = 11
    static let lineNumberTrailingPadding: CGFloat = 12
    static let lineMarkerLeadingPadding: CGFloat = 5
    static let lineNumberVerticalPadding: CGFloat = 4
    static let editorFontSize: CGFloat = 13
    static let codeFontFamily = "SFMono-Regular"
    static let codeFontSize: CGFloat = 13
    static let codeLineHeight: CGFloat = 18

    static func editorFont(monospaced: Bool, zoom: Double) -> NSFont {
        let baseFont = monospaced
            ? (NSFont(
                name: codeFontFamily,
                size: codeFontSize
            ) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular))
            : NSFont.systemFont(ofSize: editorFontSize)
        return baseFont.withSize(baseFont.pointSize * zoom)
    }

    static func editorParagraphStyle(zoom: Double) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let lineHeight = codeLineHeight * zoom
        paragraphStyle.lineHeightMultiple = 1
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.paragraphSpacingBefore = 0
        return paragraphStyle
    }

    static func lineBaselineY(
        lineFragmentRect: CGRect,
        glyphLocationY: CGFloat
    ) -> CGFloat {
        lineFragmentRect.minY + glyphLocationY
    }

    static func extraLineBaselineOffset(
        lineHeight: CGFloat,
        defaultBaselineOffset: CGFloat,
        defaultLineHeight: CGFloat
    ) -> CGFloat {
        defaultBaselineOffset + max(0, lineHeight - defaultLineHeight)
    }

    static func normalizedLineHeight(
        extraLineHeight: CGFloat,
        configuredLineHeight: CGFloat
    ) -> CGFloat {
        max(extraLineHeight, configuredLineHeight)
    }

    static func lineHeightForExtraFragment(
        textStorageLength: Int,
        paragraphStyleMinimumLineHeight: CGFloat?,
        fallback: CGFloat
    ) -> CGFloat {
        guard textStorageLength > 0 else { return fallback }
        return paragraphStyleMinimumLineHeight ?? fallback
    }

    static func normalizedExtraLineRect(
        extraLineRect: CGRect,
        previousLineMaxY: CGFloat?,
        configuredLineHeight: CGFloat
    ) -> CGRect {
        var rect = extraLineRect
        if let previousLineMaxY {
            rect.origin.y = max(rect.origin.y, previousLineMaxY)
        }
        rect.size.height = normalizedLineHeight(
            extraLineHeight: extraLineRect.height,
            configuredLineHeight: configuredLineHeight
        )
        return rect
    }

    static func lineHighlightRect(
        lineFragmentRect: CGRect,
        textContainerOrigin: CGPoint,
        viewWidth: CGFloat
    ) -> CGRect {
        var rect = lineFragmentRect.offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
        rect.origin.x = 0
        rect.size.width = viewWidth
        return rect
    }

    static func textContainerWidth(panelWidth: CGFloat, zoom: Double) -> CGFloat {
        max(1, panelWidth - (horizontalPadding * 2 * zoom))
    }

    static func measuredLineHeight(
        for text: String?,
        panelWidth: CGFloat,
        zoom: Double,
        monospaced: Bool
    ) -> CGFloat {
        let minimum = codeLineHeight * zoom
        guard let text, !text.isEmpty else { return minimum }

        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: textContainerWidth(panelWidth: panelWidth, zoom: zoom),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)

        let range = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: editorFont(monospaced: monospaced, zoom: zoom), range: range)
        storage.addAttribute(
            .paragraphStyle,
            value: editorParagraphStyle(zoom: zoom),
            range: range
        )
        layoutManager.ensureLayout(for: textContainer)

        return max(minimum, ceil(layoutManager.usedRect(for: textContainer).height))
    }
}

enum SourceEditorFindSelectionPolicy {
    static func shouldSelectMatch(query: String, matchCount: Int) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matchCount > 0
    }
}

enum SourceSyntaxHighlighting: Equatable, Sendable {
    case json(JSONSyntaxColorPalette)
    case markdown(MarkdownSyntaxColorPalette)
    case latex(LatexSyntaxColorPalette)

    var background: String {
        switch self {
        case let .json(palette): palette.background
        case let .markdown(palette): palette.background
        case let .latex(palette): palette.background
        }
    }

    var foreground: String {
        switch self {
        case let .json(palette): palette.foreground
        case let .markdown(palette): palette.foreground
        case let .latex(palette): palette.foreground
        }
    }
}

private struct SourceSyntaxToken: Sendable {
    let color: String
    let utf8Offset: Int
    let utf8End: Int
}

// This tokenizer is deliberately outside SourceTextView. The view and its
// coordinator are MainActor-isolated, but the tokenization itself is pure and
// must remain safe to run on the utility queue.
private enum SourceSyntaxTokenizer {
    static func tokens(
        in source: String,
        for syntaxHighlighting: SourceSyntaxHighlighting
    ) -> [SourceSyntaxToken] {
        switch syntaxHighlighting {
        case let .json(palette):
            return JSONSyntaxHighlighter().tokenize(source).map {
                SourceSyntaxToken(
                    color: palette.color(for: $0.kind),
                    utf8Offset: $0.utf8Offset,
                    utf8End: $0.utf8End
                )
            }
        case let .markdown(palette):
            return MarkdownSyntaxHighlighter().tokenize(source).map {
                SourceSyntaxToken(
                    color: palette.color(for: $0.kind),
                    utf8Offset: $0.utf8Offset,
                    utf8End: $0.utf8End
                )
            }
        case let .latex(palette):
            return LatexSyntaxHighlighter().tokenize(source).map {
                SourceSyntaxToken(
                    color: palette.color(for: $0.kind),
                    utf8Offset: $0.utf8Offset,
                    utf8End: $0.utf8End
                )
            }
        }
    }
}

struct SourceSyntaxHighlightingRequest: Equatable, Sendable {
    let source: String
    let syntaxHighlighting: SourceSyntaxHighlighting?
}

struct SourceSyntaxHighlightingGate: Equatable, Sendable {
    private(set) var scheduled: SourceSyntaxHighlightingRequest?
    private(set) var applied: SourceSyntaxHighlightingRequest?

    init() {
        scheduled = nil
        applied = nil
    }

    mutating func shouldSchedule(_ request: SourceSyntaxHighlightingRequest) -> Bool {
        if applied == request || scheduled == request {
            return false
        }
        scheduled = request
        return true
    }

    mutating func markApplied(_ request: SourceSyntaxHighlightingRequest) {
        scheduled = nil
        applied = request
    }
}

struct SourceTextView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    var cursorRequestID: Int = 0
    let isEditable: Bool
    let lineNumbers: Bool
    let lineNumberOverrides: [Int: Int]
    let lineHighlights: [Int: DocumentDiffCellKind]
    let lineSpacingBefore: [Int: CGFloat]
    let monospaced: Bool
    let syntaxHighlighting: SourceSyntaxHighlighting?
    let markdownShortcutsEnabled: Bool
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    var defersSourceChangeUpdates = false
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onDoubleClick: ((Int) -> Void)?
    var onScrollViewReady: (@MainActor (NSScrollView) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSourceChanged: onSourceChanged,
            onEndEditing: onEndEditing,
            onFindMatchCount: onFindMatchCount,
            defersSourceChangeUpdates: defersSourceChangeUpdates
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownNSTextView()
        textView.fixedEditorParagraphStyle = SourceEditorLayout.editorParagraphStyle(zoom: zoom)
        textView.onFindFocus = onFindFocus
        textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.flushPendingSourceChange()
            coordinator?.onEndEditing(textView.string)
        }
        textView.onMarkdownShortcut = { [weak textView] formatting in
            guard markdownShortcutsEnabled, let textView else { return }
            applyMarkdownShortcut(formatting, to: textView, onSourceChanged: onSourceChanged)
        }
        textView.onDoubleClick = { [weak textView] event in
            guard let textView else { return }
            let point = textView.convert(event.locationInWindow, from: nil)
            let utf16Offset = textView.characterIndexForInsertion(at: point)
            onDoubleClick?(Self.utf8Offset(in: textView.string, utf16Offset: utf16Offset))
        }
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.markdownAutoListContinuationEnabled = markdownShortcutsEnabled && isEditable
        textView.isAutomaticSpellingCorrectionEnabled = isEditable
        textView.isAutomaticTextCompletionEnabled = isEditable
        textView.usesMarkdownInlineCompletion = markdownShortcutsEnabled
            && isEditable
            && MarkdownInlineCompletionProvider.usesCustomCompletion()
        textView.inlinePredictionType = isEditable && !textView.usesMarkdownInlineCompletion ? .yes : .no
        if monospaced {
            // JSON syntax requires ASCII quotes; macOS smart quotes would turn
            // a typed delimiter into a Unicode character such as U+201D.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
        }
        textView.usesFindPanel = false
        textView.drawsBackground = syntaxHighlighting == nil
        applyBaseColors(to: textView)
        context.coordinator.appliedBaseColors = syntaxHighlighting
        context.coordinator.hasAppliedBaseColors = true
        textView.insertionPointColor = .controlAccentColor
        textView.string = source
        let initialSelection = cursorUTF8Offset.map { offset in
            NSRange(
                location: Self.utf16Offset(in: source, utf8Offset: offset),
                length: 0
            )
        }
        if let initialSelection {
            textView.setSelectedRange(initialSelection)
        }
        applyTypography(to: textView)
        context.coordinator.appliedZoom = zoom
        context.coordinator.appliedMonospaced = monospaced
        context.coordinator.appliedLineSpacingBefore = lineSpacingBefore
        context.coordinator.requiresTypographyRefresh = false
        context.coordinator.requiresSyntaxRefresh = true
        context.coordinator.requiresInitialSyntaxRefresh = true
        context.coordinator.lastModelSource = source
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(
            width: textContainerHorizontalInset(zoom: zoom),
            height: SourceEditorLayout.verticalPadding * CGFloat(zoom)
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.showsLineNumbers = lineNumbers
        textView.lineNumberGutterWidth = SourceEditorLayout.lineNumberGutterWidth * CGFloat(zoom)
        textView.lineNumberFontSize = SourceEditorLayout.lineNumberFontSize * CGFloat(zoom)
        textView.lineNumberOverrides = lineNumberOverrides
        textView.lineHighlights = lineHighlights
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = syntaxHighlighting == nil
        scrollView.backgroundColor = textView.backgroundColor
        scrollView.documentView = textView
        context.coordinator.appliedCursorUTF8Offset = cursorUTF8Offset
        context.coordinator.appliedCursorRequestID = cursorRequestID
        context.coordinator.scheduleInitialSyntaxRefresh(
            in: textView,
            source: source,
            syntaxHighlighting: syntaxHighlighting
        )
        if isEditable {
            focus(textView, selection: initialSelection)
        }
        onScrollViewReady?(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        textView.fixedEditorParagraphStyle = SourceEditorLayout.editorParagraphStyle(zoom: zoom)
        context.coordinator.onSourceChanged = onSourceChanged
        context.coordinator.onEndEditing = onEndEditing
        context.coordinator.onFindMatchCount = onFindMatchCount

        textView.lineHighlights = lineHighlights
        textView.onDoubleClick = { [weak textView] event in
            guard let textView else { return }
            let point = textView.convert(event.locationInWindow, from: nil)
            let utf16Offset = textView.characterIndexForInsertion(at: point)
            onDoubleClick?(Self.utf8Offset(in: textView.string, utf16Offset: utf16Offset))
        }

        textView.showsLineNumbers = lineNumbers
        textView.lineNumberGutterWidth = SourceEditorLayout.lineNumberGutterWidth * CGFloat(zoom)
        textView.lineNumberFontSize = SourceEditorLayout.lineNumberFontSize * CGFloat(zoom)
        textView.lineNumberOverrides = lineNumberOverrides
        textView.isEditable = isEditable
        textView.markdownAutoListContinuationEnabled = markdownShortcutsEnabled && isEditable
        textView.isAutomaticSpellingCorrectionEnabled = isEditable
        textView.isAutomaticTextCompletionEnabled = isEditable
        textView.usesMarkdownInlineCompletion = markdownShortcutsEnabled
            && isEditable
            && MarkdownInlineCompletionProvider.usesCustomCompletion()
        textView.inlinePredictionType = isEditable && !textView.usesMarkdownInlineCompletion ? .yes : .no
        if !textView.usesMarkdownInlineCompletion {
            context.coordinator.cancelInlineCompletion(for: textView)
        }

        if !context.coordinator.didRequestInitialFocus, isEditable {
            focus(textView, selection: nil) {
                context.coordinator.didRequestInitialFocus = true
            }
        } else if !isEditable {
            context.coordinator.didRequestInitialFocus = true
        }

        if !context.coordinator.hasAppliedBaseColors
            || context.coordinator.appliedBaseColors != syntaxHighlighting {
            applyBaseColors(to: textView)
            context.coordinator.appliedBaseColors = syntaxHighlighting
            context.coordinator.hasAppliedBaseColors = true
        }
        scrollView.drawsBackground = syntaxHighlighting == nil
        scrollView.backgroundColor = textView.backgroundColor
        let sourceChanged = textView.string != source
        let modelSourceChanged = context.coordinator.lastModelSource != source
        let hasLocalEditorChange = isEditable && sourceChanged && !modelSourceChanged
        if sourceChanged && !hasLocalEditorChange {
            let selectedRange = textView.selectedRange()
            let restoredSelection = Self.replaceSourcePreservingUnchangedAttributes(
                source,
                in: textView,
                selection: selectedRange
            )
            textView.setSelectedRange(restoredSelection)
            textView.invalidateLineNumberCache()
            context.coordinator.requiresTypographyRefresh = true
        }
        context.coordinator.lastModelSource = source

        let effectiveSource = textView.string

        let typographyChanged = context.coordinator.appliedZoom != zoom
            || context.coordinator.appliedMonospaced != monospaced
            || context.coordinator.appliedLineSpacingBefore != lineSpacingBefore
        if typographyChanged || context.coordinator.requiresTypographyRefresh {
            applyTypography(to: textView)
            context.coordinator.appliedZoom = zoom
            context.coordinator.appliedMonospaced = monospaced
            context.coordinator.appliedLineSpacingBefore = lineSpacingBefore
            context.coordinator.requiresTypographyRefresh = false
        }

        let syntaxChanged = context.coordinator.syntaxHighlightingGate.applied.map {
            $0.syntaxHighlighting != syntaxHighlighting
        } ?? false
        if sourceChanged
            || context.coordinator.requiresSyntaxRefresh
            || context.coordinator.requiresInitialSyntaxRefresh
            || syntaxChanged {
            if !syntaxChanged {
                context.coordinator.scheduleSyntaxHighlighting(
                    in: textView,
                    source: effectiveSource,
                    syntaxHighlighting: syntaxHighlighting,
                    delay: context.coordinator.requiresInitialSyntaxRefresh || !isEditable
                        || modelSourceChanged
                        ? .zero
                        : .milliseconds(300)
                )
            } else {
                Self.applySyntaxHighlighting(
                    to: textView,
                    source: effectiveSource,
                    syntaxHighlighting: syntaxHighlighting
                )
                context.coordinator.syntaxHighlightingGate.markApplied(
                    SourceSyntaxHighlightingRequest(
                        source: effectiveSource,
                        syntaxHighlighting: syntaxHighlighting
                    )
                )
                context.coordinator.requiresSyntaxRefresh = false
                context.coordinator.requiresInitialSyntaxRefresh = false
            }
        }
        context.coordinator.applyFind(
            in: textView,
            source: effectiveSource,
            query: findQuery,
            requestID: findRequestID,
            backwards: findBackwards,
            isFindTarget: isFindTarget
        )
        textView.textContainerInset = NSSize(
            width: textContainerHorizontalInset(zoom: zoom),
            height: SourceEditorLayout.verticalPadding * CGFloat(zoom)
        )
        textView.textContainer?.lineFragmentPadding = 0

        guard let cursorUTF8Offset,
              context.coordinator.appliedCursorUTF8Offset != cursorUTF8Offset
                || context.coordinator.appliedCursorRequestID != cursorRequestID else { return }
        let cursorOffset = Self.utf16Offset(in: effectiveSource, utf8Offset: cursorUTF8Offset)
        let selection = NSRange(location: cursorOffset, length: 0)
        textView.setSelectedRange(selection)
        focus(textView, selection: selection)
        context.coordinator.appliedCursorUTF8Offset = cursorUTF8Offset
        context.coordinator.appliedCursorRequestID = cursorRequestID
    }

    private func applyTypography(to textView: NSTextView) {
        let font = SourceEditorLayout.editorFont(monospaced: monospaced, zoom: zoom)
        let paragraphStyle = SourceEditorLayout.editorParagraphStyle(zoom: zoom)

        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textView.textColor ?? NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return }
        let range = NSRange(location: 0, length: textLength)
        textView.textStorage?.addAttribute(.font, value: font, range: range)
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        applyLineSpacingBefore(
            to: textView,
            paragraphStyle: paragraphStyle
        )
    }

    private func applyLineSpacingBefore(
        to textView: NSTextView,
        paragraphStyle: NSParagraphStyle
    ) {
        guard !lineSpacingBefore.isEmpty else { return }

        let source = textView.string as NSString
        var lineStart = 0
        var lineNumber = 1
        for position in 0...source.length {
            let isEnd = position == source.length
            let isNewline = !isEnd && source.character(at: position) == 10
            guard isEnd || isNewline else { continue }

            let length = position - lineStart + (isNewline ? 1 : 0)
            guard length > 0 else {
                lineStart = position + 1
                lineNumber += 1
                continue
            }

            let style = (paragraphStyle.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            style.paragraphSpacingBefore = lineSpacingBefore[lineNumber] ?? 0
            textView.textStorage?.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: lineStart, length: length)
            )
            lineStart = position + 1
            lineNumber += 1
        }
    }

    private static func utf8Offset(in source: String, utf16Offset: Int) -> Int {
        let sourceNSString = source as NSString
        let clampedOffset = min(max(utf16Offset, 0), sourceNSString.length)
        return sourceNSString.substring(to: clampedOffset).utf8.count
    }

    private func textContainerHorizontalInset(zoom: Double) -> CGFloat {
        // The gutter occupies the leading part of the editor's existing
        // padding. Keeping the text origin stable avoids shifting documents
        // when numbering is toggled and keeps the gutter inside the document.
        SourceEditorLayout.horizontalPadding * CGFloat(zoom)
    }

    private static func applySyntaxHighlighting(
        to textView: NSTextView,
        source: String,
        syntaxHighlighting: SourceSyntaxHighlighting?
    ) {
        applySyntaxHighlighting(
            to: textView,
            source: source,
            syntaxHighlighting: syntaxHighlighting,
            tokens: syntaxHighlighting.map {
                SourceSyntaxTokenizer.tokens(in: source, for: $0)
            } ?? []
        )
    }

    private static func replaceSourcePreservingUnchangedAttributes(
        _ source: String,
        in textView: NSTextView,
        selection: NSRange
    ) -> NSRange {
        guard let textStorage = textView.textStorage else {
            textView.string = source
            return NSRange(
                location: min(selection.location, (source as NSString).length),
                length: 0
            )
        }

        let currentSource = textView.string as NSString
        let replacementSource = source as NSString
        let currentLength = currentSource.length
        let replacementLength = replacementSource.length
        let sharedLength = min(currentLength, replacementLength)
        var commonPrefixLength = 0

        while commonPrefixLength < sharedLength,
              currentSource.character(at: commonPrefixLength)
                == replacementSource.character(at: commonPrefixLength) {
            commonPrefixLength += 1
        }

        // Keep the edit range on UTF-16 scalar boundaries so an undo that
        // touches emoji does not leave half of a surrogate pair behind.
        if commonPrefixLength > 0,
           commonPrefixLength < currentLength,
           isLowSurrogate(currentSource.character(at: commonPrefixLength)) {
            commonPrefixLength -= 1
        }

        var commonSuffixLength = 0
        while commonSuffixLength < currentLength - commonPrefixLength,
              commonSuffixLength < replacementLength - commonPrefixLength,
              currentSource.character(at: currentLength - commonSuffixLength - 1)
                == replacementSource.character(at: replacementLength - commonSuffixLength - 1) {
            commonSuffixLength += 1
        }

        if commonSuffixLength > 0 {
            let currentSuffixStart = currentLength - commonSuffixLength
            let replacementSuffixStart = replacementLength - commonSuffixLength
            if (currentSuffixStart < currentLength
                && isLowSurrogate(currentSource.character(at: currentSuffixStart)))
                || (replacementSuffixStart < replacementLength
                    && isLowSurrogate(replacementSource.character(at: replacementSuffixStart))) {
                commonSuffixLength -= 1
            }
        }

        let currentRange = NSRange(
            location: commonPrefixLength,
            length: currentLength - commonPrefixLength - commonSuffixLength
        )
        let replacementRange = NSRange(
            location: commonPrefixLength,
            length: replacementLength - commonPrefixLength - commonSuffixLength
        )
        guard currentRange.length > 0 || replacementRange.length > 0 else { return selection }

        let currentEnd = NSMaxRange(currentRange)
        let replacementEnd = NSMaxRange(replacementRange)
        let lengthDelta = replacementRange.length - currentRange.length

        func mappedOffset(_ offset: Int) -> Int {
            if currentRange.length == 0 {
                if offset < currentRange.location { return offset }
                if offset == currentRange.location {
                    return selection.length == 0 ? replacementEnd : currentRange.location
                }
                return offset + lengthDelta
            }
            if offset <= currentRange.location { return offset }
            if offset >= currentEnd { return offset + lengthDelta }
            return replacementEnd
        }

        let selectionStart = mappedOffset(selection.location)
        let selectionEnd = mappedOffset(NSMaxRange(selection))
        let updatedSelection = NSRange(
            location: min(selectionStart, selectionEnd),
            length: abs(selectionEnd - selectionStart)
        )

        textStorage.replaceCharacters(
            in: currentRange,
            with: replacementSource.substring(with: replacementRange)
        )
        return updatedSelection
    }

    private static func isLowSurrogate(_ codeUnit: unichar) -> Bool {
        (0xDC00...0xDFFF).contains(codeUnit)
    }

    private static func applySyntaxHighlighting(
        to textView: NSTextView,
        source: String,
        syntaxHighlighting: SourceSyntaxHighlighting?,
        tokens: [SourceSyntaxToken]
    ) {
        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return }
        let range = NSRange(location: 0, length: textLength)
        guard let textStorage = textView.textStorage else { return }
        let utf16Offsets = Self.utf16Offsets(in: source)
        let foregroundColor = syntaxHighlighting.map {
            NSColor(hex: $0.foreground)
        } ?? textView.textColor ?? NSColor.textColor
        textStorage.beginEditing()
        textStorage.addAttribute(
            .foregroundColor,
            value: foregroundColor,
            range: range
        )
        for token in tokens {
            let start = utf16Offsets[min(max(token.utf8Offset, 0), utf16Offsets.count - 1)]
            let end = utf16Offsets[min(max(token.utf8End, 0), utf16Offsets.count - 1)]
            guard end > start else { continue }
            textStorage.addAttribute(
                .foregroundColor,
                value: NSColor(hex: token.color),
                range: NSRange(location: start, length: end - start)
            )
        }
        textStorage.endEditing()
    }

    private static func utf16Offsets(in source: String) -> [Int] {
        var offsets = Array(repeating: 0, count: source.utf8.count + 1)
        var utf8Offset = 0
        var utf16Offset = 0

        for scalar in source.unicodeScalars {
            let utf8Length = scalar.utf8.count
            let utf16Length = scalar.utf16.count
            for offset in utf8Offset..<(utf8Offset + utf8Length) {
                offsets[offset] = utf16Offset
            }
            utf8Offset += utf8Length
            utf16Offset += utf16Length
            offsets[utf8Offset] = utf16Offset
        }
        return offsets
    }

    private func applyBaseColors(to textView: NSTextView) {
        guard let syntaxHighlighting else {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
            return
        }
        textView.backgroundColor = .clear
        textView.textColor = NSColor(hex: syntaxHighlighting.foreground)
    }

    private func applyMarkdownShortcut(
        _ formatting: MarkdownInlineFormatting,
        to textView: NSTextView,
        onSourceChanged: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let source = textView.string
        let selection = textView.selectedRange()
        let result = MarkdownShortcutFormatter.apply(
            formatting,
            to: source,
            selectionUTF16Offset: selection.location,
            selectionUTF16Length: selection.length
        )
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard textView.shouldChangeText(in: fullRange, replacementString: result.source) else { return }
        textView.replaceCharacters(in: fullRange, with: result.source)
        textView.setSelectedRange(NSRange(
            location: result.selectionUTF16Offset,
            length: result.selectionUTF16Length
        ))
        textView.didChangeText()
        onSourceChanged(result.source)
    }

    private func focus(
        _ textView: NSTextView,
        selection: NSRange?,
        attempt: Int = 0,
        onFocused: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            guard let window = textView.window else {
                guard attempt < 10 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focus(textView, selection: selection, attempt: attempt + 1, onFocused: onFocused)
                }
                return
            }
            if let selection {
                textView.setSelectedRange(selection)
                textView.scrollRangeToVisible(selection)
            }
            window.makeFirstResponder(textView)
            onFocused?()
        }
    }

    private static func utf16Offset(in source: String, utf8Offset: Int) -> Int {
        let bytes = Array(source.utf8)
        let clampedOffset = min(max(utf8Offset, 0), bytes.count)
        let prefix = String(decoding: bytes[..<clampedOffset], as: UTF8.self)
        return prefix.utf16.count
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSourceChanged: @MainActor @Sendable (String) -> Void
        var onEndEditing: @MainActor @Sendable (String) -> Void
        var onFindMatchCount: @MainActor @Sendable (Int) -> Void
        var appliedCursorUTF8Offset: Int?
        var appliedCursorRequestID = 0
        var didRequestInitialFocus = false
        var appliedZoom: Double?
        var appliedMonospaced: Bool?
        var appliedLineSpacingBefore: [Int: CGFloat] = [:]
        var appliedBaseColors: SourceSyntaxHighlighting?
        var hasAppliedBaseColors = false
        var syntaxHighlightingGate = SourceSyntaxHighlightingGate()
        let defersSourceChangeUpdates: Bool
        var requiresTypographyRefresh = true
        var requiresSyntaxRefresh = true
        var requiresInitialSyntaxRefresh = true
        var lastModelSource: String?
        private var syntaxHighlightTask: Task<Void, Never>?
        private var sourceChangeTask: Task<Void, Never>?
        private var inlineCompletionTask: Task<Void, Never>?
        private var inlineCompletionGeneration = 0
        private var pendingSource: String?
        private var syntaxHighlightGeneration = 0
        private var findSource = ""
        private var findQuery = ""
        private var findRequestID = -1
        private var findMatches: [TextSearchMatch] = []
        private var currentFindIndex: Int?
        private var hasFindHighlights = false

        init(
            onSourceChanged: @escaping @MainActor @Sendable (String) -> Void,
            onEndEditing: @escaping @MainActor @Sendable (String) -> Void,
            onFindMatchCount: @escaping @MainActor @Sendable (Int) -> Void,
            defersSourceChangeUpdates: Bool
        ) {
            self.onSourceChanged = onSourceChanged
            self.onEndEditing = onEndEditing
            self.onFindMatchCount = onFindMatchCount
            self.defersSourceChangeUpdates = defersSourceChangeUpdates
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            requiresSyntaxRefresh = true
            if let markdownTextView = textView as? MarkdownNSTextView {
                scheduleInlineCompletion(for: markdownTextView)
            }
            let source = textView.string
            guard defersSourceChangeUpdates else {
                onSourceChanged(source)
                return
            }

            // NSTextView already owns the live draft. Coalesce model updates so
            // each keystroke can return to AppKit without synchronously
            // rebuilding the observed SwiftUI workspace.
            pendingSource = source
            sourceChangeTask?.cancel()
            sourceChangeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                self?.flushPendingSourceChange()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownNSTextView else { return }
            if let completion = textView.inlineCompletion,
               completion.wordRange.location + completion.wordRange.length
                != textView.selectedRange().location {
                cancelInlineCompletion(for: textView)
            }
        }

        fileprivate func cancelInlineCompletion(for textView: MarkdownNSTextView) {
            inlineCompletionTask?.cancel()
            inlineCompletionTask = nil
            inlineCompletionGeneration += 1
            textView.inlineCompletion = nil
        }

        private func scheduleInlineCompletion(for textView: MarkdownNSTextView) {
            let suppressNextCompletion = textView.suppressInlineCompletionAfterAcceptance
            textView.suppressInlineCompletionAfterAcceptance = false
            cancelInlineCompletion(for: textView)
            guard !suppressNextCompletion,
                  textView.usesMarkdownInlineCompletion,
                  textView.isEditable,
                  textView.selectedRange().length == 0 else { return }

            let source = textView.string
            let caret = textView.selectedRange().location
            guard MarkdownInlineCompletionProvider.eligibleWord(
                in: source,
                caretUTF16Offset: caret
            ) != nil else { return }

            let generation = inlineCompletionGeneration
            inlineCompletionTask = Task { @MainActor [weak self, weak textView] in
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      let textView,
                      self.inlineCompletionGeneration == generation,
                      textView.string == source,
                      textView.selectedRange() == NSRange(location: caret, length: 0) else { return }

                let completion = await MarkdownInlineCompletionProvider.completion(
                    in: source,
                    caretUTF16Offset: caret
                )
                guard !Task.isCancelled,
                      self.inlineCompletionGeneration == generation,
                      textView.string == source,
                      textView.selectedRange() == NSRange(location: caret, length: 0) else { return }
                textView.inlineCompletion = completion
                self.inlineCompletionTask = nil
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            flushPendingSourceChange()
        }

        func flushPendingSourceChange() {
            guard let pendingSource else { return }
            self.pendingSource = nil
            sourceChangeTask?.cancel()
            sourceChangeTask = nil
            onSourceChanged(pendingSource)
        }

        func scheduleSyntaxHighlighting(
            in textView: NSTextView,
            source: String,
            syntaxHighlighting: SourceSyntaxHighlighting?,
            delay: Duration = .milliseconds(120)
        ) {
            let request = SourceSyntaxHighlightingRequest(
                source: source,
                syntaxHighlighting: syntaxHighlighting
            )
            guard syntaxHighlightingGate.shouldSchedule(request) else {
                if syntaxHighlightingGate.applied == request {
                    requiresSyntaxRefresh = false
                }
                return
            }
            syntaxHighlightTask?.cancel()
            syntaxHighlightGeneration += 1
            let generation = syntaxHighlightGeneration
            syntaxHighlightTask = Task { @MainActor [weak self, weak textView] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled,
                      let self,
                      let textView,
                      self.syntaxHighlightGeneration == generation else { return }

                let tokens = await Task.detached(priority: .utility) {
                    syntaxHighlighting.map {
                        SourceSyntaxTokenizer.tokens(in: request.source, for: $0)
                    } ?? []
                }.value
                guard !Task.isCancelled,
                      self.syntaxHighlightGeneration == generation,
                      textView.string == source else { return }
                SourceTextView.applySyntaxHighlighting(
                    to: textView,
                    source: request.source,
                    syntaxHighlighting: syntaxHighlighting,
                    tokens: tokens
                )
                self.syntaxHighlightTask = nil
                self.syntaxHighlightingGate.markApplied(request)
                self.requiresSyntaxRefresh = false
            }
        }

        func scheduleInitialSyntaxRefresh(
            in textView: NSTextView,
            source: String,
            syntaxHighlighting: SourceSyntaxHighlighting?
        ) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.requiresInitialSyntaxRefresh,
                      textView.string == source else { return }

                self.requiresInitialSyntaxRefresh = false
                self.scheduleSyntaxHighlighting(
                    in: textView,
                    source: source,
                    syntaxHighlighting: syntaxHighlighting,
                    delay: .zero
                )
            }
        }

        func applyFind(
            in textView: NSTextView,
            source: String,
            query: String,
            requestID: Int,
            backwards: Bool,
            isFindTarget: Bool
        ) {
            guard isFindTarget else {
                clearFind(in: textView, notify: false)
                return
            }

            let sourceChanged = findSource != source
            let queryChanged = findQuery != query
            let requestChanged = findRequestID != requestID
            guard sourceChanged || queryChanged || requestChanged else { return }

            findSource = source
            findQuery = query
            findRequestID = requestID

            if sourceChanged || queryChanged {
                findMatches = TextSearch.matches(in: source, query: query)
                currentFindIndex = TextSearch.nextMatchIndex(
                    currentIndex: nil,
                    matchCount: findMatches.count,
                    backwards: backwards
                )
            } else {
                currentFindIndex = TextSearch.nextMatchIndex(
                    currentIndex: currentFindIndex,
                    matchCount: findMatches.count,
                    backwards: backwards
                )
            }

            onFindMatchCount(findMatches.count)
            updateFindHighlights(in: textView)
        }

        private func clearFind(in textView: NSTextView, notify: Bool) {
            if hasFindHighlights {
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                textView.layoutManager?.removeTemporaryAttribute(
                    .backgroundColor,
                    forCharacterRange: fullRange
                )
            }
            findSource = ""
            findQuery = ""
            findRequestID = -1
            findMatches = []
            currentFindIndex = nil
            hasFindHighlights = false
            if notify {
                onFindMatchCount(0)
            }
        }

        private func updateFindHighlights(in textView: NSTextView) {
            if hasFindHighlights {
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                textView.layoutManager?.removeTemporaryAttribute(
                    .backgroundColor,
                    forCharacterRange: fullRange
                )
            }

            for match in findMatches {
                let range = NSRange(
                    location: match.utf16Range.lowerBound,
                    length: match.utf16Range.count
                )
                textView.layoutManager?.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.22),
                    forCharacterRange: range
                )
            }
            hasFindHighlights = !findMatches.isEmpty

            guard SourceEditorFindSelectionPolicy.shouldSelectMatch(
                query: findQuery,
                matchCount: findMatches.count
            ) else {
                return
            }

            guard let currentFindIndex,
                  findMatches.indices.contains(currentFindIndex) else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                return
            }

            let match = findMatches[currentFindIndex]
            let range = NSRange(
                location: match.utf16Range.lowerBound,
                length: match.utf16Range.count
            )
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private final class MarkdownNSTextView: NSTextView {
    private struct LineFragment {
        let physicalLine: Int
        let rect: NSRect
        let baselineY: CGFloat
    }

    var onEscape: (() -> Void)?
    var onMarkdownShortcut: ((MarkdownInlineFormatting) -> Void)?
    var markdownAutoListContinuationEnabled = false
    var onFindFocus: (() -> Void)?
    var onDoubleClick: ((NSEvent) -> Void)?
    var usesMarkdownInlineCompletion = false
    var suppressInlineCompletionAfterAcceptance = false
    var inlineCompletion: MarkdownInlineCompletion? {
        didSet {
            guard oldValue != inlineCompletion else { return }
            needsDisplay = true
        }
    }
    var fixedEditorParagraphStyle: NSParagraphStyle? {
        didSet {
            guard let fixedEditorParagraphStyle else { return }
            if let oldValue,
               oldValue.minimumLineHeight == fixedEditorParagraphStyle.minimumLineHeight,
               oldValue.maximumLineHeight == fixedEditorParagraphStyle.maximumLineHeight,
               oldValue.lineHeightMultiple == fixedEditorParagraphStyle.lineHeightMultiple,
               oldValue.lineSpacing == fixedEditorParagraphStyle.lineSpacing,
               oldValue.paragraphSpacing == fixedEditorParagraphStyle.paragraphSpacing,
               oldValue.paragraphSpacingBefore == fixedEditorParagraphStyle.paragraphSpacingBefore {
                return
            }
            defaultParagraphStyle = fixedEditorParagraphStyle
            var attributes = typingAttributes
            attributes[.paragraphStyle] = fixedEditorParagraphStyle
            typingAttributes = attributes
        }
    }
    var showsLineNumbers = false {
        didSet {
            guard oldValue != showsLineNumbers else { return }
            needsDisplay = true
        }
    }
    var lineNumberGutterWidth: CGFloat = 0 {
        didSet {
            guard oldValue != lineNumberGutterWidth else { return }
            needsDisplay = true
        }
    }
    var lineNumberFontSize: CGFloat = 11 {
        didSet {
            guard oldValue != lineNumberFontSize else { return }
            needsDisplay = true
        }
    }
    var lineNumberOverrides: [Int: Int] = [:] {
        didSet {
            guard oldValue != lineNumberOverrides else { return }
            needsDisplay = true
        }
    }
    var lineHighlights: [Int: DocumentDiffCellKind] = [:] {
        didSet {
            guard oldValue != lineHighlights else { return }
            needsDisplay = true
        }
    }

    private var cachedLineStarts: [Int]?
    private var pendingLineStartEdit: (range: NSRange, replacement: String)?
    private var pendingParagraphStyleEdit: (range: NSRange, replacement: String)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFindFocus?()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        inlineCompletion = nil
        onFindFocus?()
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInlineCompletion()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let fragments = lineFragments(in: visibleRect)
        drawLineHighlights(in: rect, fragments: fragments)
        drawLineNumberSeparator()
        if showsLineNumbers {
            drawLineNumbers(in: rect, fragments: fragments)
        }
    }

    private func drawLineNumbers(in rect: NSRect, fragments: [LineFragment]) {
        guard lineNumberGutterWidth > 0 else { return }

        var drawnPhysicalLines = Set<Int>()

        for fragment in fragments {
            guard fragment.rect.intersects(rect),
                  drawnPhysicalLines.insert(fragment.physicalLine).inserted else {
                continue
            }
            drawLineNumber(
                lineNumber: lineNumber(forPhysicalLine: fragment.physicalLine),
                kind: lineHighlights[fragment.physicalLine],
                baselineY: fragment.baselineY
            )
        }
    }

    func invalidateLineNumberCache() {
        cachedLineStarts = nil
        pendingLineStartEdit = nil
    }

    override func shouldChangeText(
        in affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        let shouldChange = super.shouldChangeText(
            in: affectedCharRange,
            replacementString: replacementString
        )
        if shouldChange, cachedLineStarts != nil {
            pendingLineStartEdit = (
                affectedCharRange,
                replacementString ?? ""
            )
        }
        if shouldChange {
            pendingParagraphStyleEdit = (
                affectedCharRange,
                replacementString ?? ""
            )
        }
        return shouldChange
    }

    override func didChangeText() {
        super.didChangeText()
        if let edit = pendingParagraphStyleEdit {
            normalizeEditedParagraphs(edit)
        }
        pendingParagraphStyleEdit = nil
        guard let edit = pendingLineStartEdit,
              let starts = cachedLineStarts else {
            invalidateLineNumberCache()
            needsDisplay = true
            return
        }
        pendingLineStartEdit = nil
        cachedLineStarts = updatedLineStarts(
            starts,
            replacing: edit.range,
            with: edit.replacement
        )
        // NSTextView may invalidate only the edited glyph area. The gutter is
        // drawn in drawBackground, so explicitly refresh it with each edit.
        needsDisplay = true
    }

    private func normalizeEditedParagraphs(_ edit: (range: NSRange, replacement: String)) {
        guard let fixedEditorParagraphStyle,
              let textStorage,
              textStorage.length > 0 else {
            if let fixedEditorParagraphStyle {
                var attributes = typingAttributes
                attributes[.paragraphStyle] = fixedEditorParagraphStyle
                typingAttributes = attributes
            }
            return
        }

        let source = string as NSString
        let start = min(max(edit.range.location, 0), source.length)
        let insertedLength = (edit.replacement as NSString).length
        let caret = min(start + insertedLength, source.length)
        let changedLength = min(insertedLength, source.length - start)
        let changedRange = source.paragraphRange(for: NSRange(
            location: start,
            length: changedLength
        ))
        let caretRange = source.paragraphRange(for: NSRange(location: caret, length: 0))
        let paragraphRanges = [changedRange, caretRange].filter { $0.length > 0 }

        textStorage.beginEditing()
        for range in paragraphRanges {
            let currentStyle = textStorage.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
            let needsNormalization = currentStyle.map {
                $0.minimumLineHeight != fixedEditorParagraphStyle.minimumLineHeight
                    || $0.maximumLineHeight != fixedEditorParagraphStyle.maximumLineHeight
                    || $0.lineHeightMultiple != fixedEditorParagraphStyle.lineHeightMultiple
                    || $0.lineSpacing != 0
                    || $0.paragraphSpacing != 0
            } ?? true
            guard needsNormalization else { continue }

            let normalizedStyle = (fixedEditorParagraphStyle.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            normalizedStyle.paragraphSpacingBefore = currentStyle?.paragraphSpacingBefore ?? 0
            textStorage.addAttribute(.paragraphStyle, value: normalizedStyle, range: range)
        }
        textStorage.endEditing()

        var attributes = typingAttributes
        attributes[.paragraphStyle] = fixedEditorParagraphStyle
        typingAttributes = attributes
    }

    private func updatedLineStarts(
        _ starts: [Int],
        replacing range: NSRange,
        with replacement: String
    ) -> [Int] {
        let replacementString = replacement as NSString
        let delta = replacementString.length - range.length
        let end = NSMaxRange(range)
        var updated = starts.filter { start in
            if start <= range.location { return true }
            if start < end { return false }
            if start == end, range.length == 0 { return true }
            return true
        }.map { start in
            let followsReplacedText = range.length == 0
                ? start > end
                : start >= end
            return followsReplacedText ? start + delta : start
        }

        if replacementString.length > 0 {
            for offset in 0..<replacementString.length
            where replacementString.character(at: offset) == 10 {
                updated.append(range.location + offset + 1)
            }
        }
        updated.sort()
        var unique: [Int] = []
        unique.reserveCapacity(updated.count)
        for start in updated where unique.last != start {
            unique.append(start)
        }
        return unique
    }

    private func lineFragments(in requestedRect: NSRect) -> [LineFragment] {
        guard let layoutManager,
              let textContainer else { return [] }

        let origin = textContainerOrigin
        let textContainerRect = requestedRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: textContainerRect,
            in: textContainer
        )
        layoutManager.ensureLayout(forGlyphRange: glyphRange)
        let sourceFont = font ?? NSFont.systemFont(ofSize: SourceEditorLayout.editorFontSize)
        var fragments: [LineFragment] = []

        // Both the gutter and the diff background consume this exact list.
        // In particular, a logical line can produce several visual fragments
        // when it wraps, while the gutter still draws its number only once.
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
                [weak self] lineFragmentRect, _, _, glyphRange, _ in
                guard let self,
                      glyphRange.location < layoutManager.numberOfGlyphs else { return }

                let rect = lineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
                let physicalLine = lineNumber(
                    atUTF16Offset: layoutManager.characterIndexForGlyph(at: glyphRange.location)
                )
                // A glyph's vertical location can vary with the text on the
                // line (for example, fallback glyphs or marked text). Use the
                // font's baseline within the fixed-height line fragment so
                // line numbers stay aligned when a blank line gets content.
                let baselineY = rect.minY + SourceEditorLayout.extraLineBaselineOffset(
                    lineHeight: rect.height,
                    defaultBaselineOffset: layoutManager.defaultBaselineOffset(for: sourceFont),
                    defaultLineHeight: layoutManager.defaultLineHeight(for: sourceFont)
                )
                fragments.append(LineFragment(
                    physicalLine: physicalLine,
                    rect: rect,
                    baselineY: baselineY
                ))
            }
        }

        let extraLineRect = layoutManager.extraLineFragmentRect.offsetBy(
            dx: origin.x,
            dy: origin.y
        )
        if extraLineRect.height > 0 && extraLineRect.intersects(requestedRect) {
            let paragraphStyleMinimumLineHeight: CGFloat?
            if let textStorage, textStorage.length > 0 {
                paragraphStyleMinimumLineHeight = (textStorage.attribute(
                    .paragraphStyle,
                    at: 0,
                    effectiveRange: nil
                ) as? NSParagraphStyle)?.minimumLineHeight
            } else {
                paragraphStyleMinimumLineHeight = nil
            }
            let configuredLineHeight = fragments.first?.rect.height
                ?? SourceEditorLayout.lineHeightForExtraFragment(
                    textStorageLength: textStorage?.length ?? 0,
                    paragraphStyleMinimumLineHeight: paragraphStyleMinimumLineHeight,
                    fallback: SourceEditorLayout.codeLineHeight
                )
            let normalizedExtraLineRect = SourceEditorLayout.normalizedExtraLineRect(
                extraLineRect: extraLineRect,
                previousLineMaxY: fragments.last?.rect.maxY,
                configuredLineHeight: configuredLineHeight
            )
            let extraLineBaselineOffset = SourceEditorLayout.extraLineBaselineOffset(
                lineHeight: normalizedExtraLineRect.height,
                defaultBaselineOffset: layoutManager.defaultBaselineOffset(for: sourceFont),
                defaultLineHeight: layoutManager.defaultLineHeight(for: sourceFont)
            )
            fragments.append(LineFragment(
                physicalLine: lineNumber(atUTF16Offset: (string as NSString).length),
                rect: normalizedExtraLineRect,
                baselineY: normalizedExtraLineRect.minY + extraLineBaselineOffset
            ))
        }

        return fragments
    }

    private func drawLineNumber(
        lineNumber: Int?,
        kind: DocumentDiffCellKind?,
        baselineY: CGFloat
    ) {
        let font = NSFont.monospacedSystemFont(ofSize: lineNumberFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let point: NSPoint
        if let lineNumber {
            let label = String(lineNumber) as NSString
            let width = label.size(withAttributes: attributes).width
            point = NSPoint(
                x: lineNumberGutterWidth - width - SourceEditorLayout.lineNumberTrailingPadding,
                y: baselineY
            )
            label.draw(with: NSRect(origin: point, size: .zero), options: [], attributes: attributes)
        } else {
            point = NSPoint(
                x: SourceEditorLayout.lineMarkerLeadingPadding,
                y: baselineY
            )
        }

        let marker: String
        let markerColor: NSColor
        switch kind {
        case .added:
            marker = "+"
            markerColor = .systemGreen
        case .removed:
            marker = "−"
            markerColor = .systemRed
        case .unchanged, .none:
            return
        }
        (marker as NSString).draw(
            with: NSRect(
                x: SourceEditorLayout.lineMarkerLeadingPadding,
                y: point.y,
                width: 0,
                height: 0
            ),
            options: [],
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: lineNumberFontSize, weight: .semibold),
                .foregroundColor: markerColor
            ]
        )
    }

    private func lineNumber(forPhysicalLine physicalLine: Int) -> Int? {
        lineNumberOverrides.isEmpty
            ? physicalLine
            : lineNumberOverrides[physicalLine]
    }

    private func lineNumber(atUTF16Offset offset: Int) -> Int {
        let starts: [Int]
        if let cachedLineStarts {
            starts = cachedLineStarts
        } else {
            let source = string as NSString
            var computed = [0]
            computed.reserveCapacity(max(1, source.length / 32))
            for position in 0..<source.length where source.character(at: position) == 10 {
                computed.append(position + 1)
            }
            cachedLineStarts = computed
            starts = computed
        }

        let clampedOffset = min(max(offset, 0), (string as NSString).length)
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= clampedOffset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(lower, 1)
    }

    private func drawLineNumberSeparator() {
        guard showsLineNumbers, lineNumberGutterWidth > 0 else { return }
        NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(
            x: lineNumberGutterWidth,
            y: visibleRect.minY
        ))
        separator.line(to: NSPoint(
            x: lineNumberGutterWidth,
            y: visibleRect.maxY
        ))
        separator.lineWidth = 0.5
        separator.stroke()
    }

    private func drawLineHighlights(in rect: NSRect, fragments: [LineFragment]) {
        guard !lineHighlights.isEmpty else { return }

        for fragment in fragments where fragment.rect.intersects(rect) {
            drawLineHighlight(
                for: lineHighlights[fragment.physicalLine],
                lineRect: fragment.rect
            )
        }
    }

    private func drawLineHighlight(
        for kind: DocumentDiffCellKind?,
        lineRect: NSRect
    ) {
        guard let kind,
              let color = lineHighlightColor(for: kind) else { return }

        let backgroundRect = SourceEditorLayout.lineHighlightRect(
            lineFragmentRect: lineRect,
            textContainerOrigin: .zero,
            viewWidth: bounds.width
        )
        color.setFill()
        backgroundRect.fill()
    }

    private func lineHighlightColor(for kind: DocumentDiffCellKind) -> NSColor? {
        switch kind {
        case .added:
            NSColor.systemGreen.withAlphaComponent(0.2)
        case .removed:
            NSColor.systemRed.withAlphaComponent(0.2)
        case .unchanged:
            nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if usesMarkdownInlineCompletion,
           isEditable,
           modifiers.isEmpty,
           event.keyCode == 48,
           acceptInlineCompletion(appendSpace: false) {
            return
        }
        if usesMarkdownInlineCompletion,
           isEditable,
           modifiers.isEmpty,
           event.characters == " ",
           acceptInlineCompletion(appendSpace: true) {
            return
        }
        if markdownAutoListContinuationEnabled,
           isEditable,
           (event.keyCode == 36 || event.keyCode == 76),
           modifiers.intersection([.command, .option, .control, .shift]).isEmpty,
           !hasMarkedText(),
           selectedRange().length == 0,
           continueMarkdownListIfNeeded() {
            return
        }
        if modifiers.contains(.command),
           !modifiers.contains(.option),
           !modifiers.contains(.control),
           let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "b":
                if let onMarkdownShortcut {
                    onMarkdownShortcut(.bold)
                    return
                }
            case "i":
                if let onMarkdownShortcut {
                    onMarkdownShortcut(.italic)
                    return
                }
            case "k":
                if let onMarkdownShortcut {
                    onMarkdownShortcut(.code)
                    return
                }
            default:
                break
            }
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    private func drawInlineCompletion() {
        guard usesMarkdownInlineCompletion,
              let inlineCompletion,
              inlineCompletion.wordRange.location + inlineCompletion.wordRange.length
                == selectedRange().location,
              !inlineCompletion.suffix.isEmpty,
              let window else { return }

        let screenRect = firstRect(
            forCharacterRange: NSRange(location: selectedRange().location, length: 0),
            actualRange: nil
        )
        guard !screenRect.isEmpty else { return }
        let caretRect = convert(window.convertFromScreen(screenRect), from: nil)
        let ghost = NSAttributedString(
            string: inlineCompletion.suffix,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: SourceEditorLayout.editorFontSize),
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55)
            ]
        )
        ghost.draw(at: NSPoint(x: caretRect.minX, y: caretRect.minY))
    }

    @discardableResult
    private func acceptInlineCompletion(appendSpace: Bool) -> Bool {
        guard let inlineCompletion,
              selectedRange().length == 0,
              selectedRange().location == inlineCompletion.wordRange.location
                + inlineCompletion.wordRange.length,
              ((string as NSString).substring(with: inlineCompletion.wordRange)
                == inlineCompletion.prefix) else { return false }

        let insertion = inlineCompletion.suffix + (appendSpace ? " " : "")
        let range = NSRange(location: selectedRange().location, length: 0)
        guard shouldChangeText(in: range, replacementString: insertion) else { return false }
        self.inlineCompletion = nil
        suppressInlineCompletionAfterAcceptance = !appendSpace
        replaceCharacters(in: range, with: insertion)
        setSelectedRange(NSRange(location: range.location + (insertion as NSString).length, length: 0))
        didChangeText()
        return true
    }

    private func continueMarkdownListIfNeeded() -> Bool {
        let source = string as NSString
        let selection = selectedRange()
        let caret = min(max(selection.location, 0), source.length)

        var lineStart = caret
        while lineStart > 0, source.character(at: lineStart - 1) != 10 {
            lineStart -= 1
        }
        var lineEnd = caret
        while lineEnd < source.length, source.character(at: lineEnd) != 10 {
            lineEnd += 1
        }

        let line = source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart)) as NSString
        var markerStart = 0
        while markerStart < line.length, isHorizontalWhitespace(line.character(at: markerStart)) {
            markerStart += 1
        }
        guard markerStart < line.length else { return false }

        let firstMarkerCharacter = line.character(at: markerStart)
        var markerEnd: Int
        let continuedMarker: String
        if isMarkdownBulletMarker(firstMarkerCharacter) {
            markerEnd = markerStart + 1
            continuedMarker = line.substring(with: NSRange(location: markerStart, length: 1))
        } else {
            var digitsEnd = markerStart
            while digitsEnd < line.length,
                  (48...57).contains(line.character(at: digitsEnd)) {
                digitsEnd += 1
            }
            let digitCount = digitsEnd - markerStart
            guard (1...9).contains(digitCount),
                  digitsEnd < line.length,
                  line.character(at: digitsEnd) == 46 || line.character(at: digitsEnd) == 41,
                  let number = Int(line.substring(with: NSRange(
                    location: markerStart,
                    length: digitCount
                  ))) else { return false }
            let (nextNumber, overflow) = number.addingReportingOverflow(1)
            guard !overflow, nextNumber <= 999_999_999 else { return false }
            let nextNumberText = String(nextNumber)
            let leadingZeroes = String(repeating: "0", count: max(0, digitCount - nextNumberText.count))
            let punctuation = line.substring(with: NSRange(location: digitsEnd, length: 1))
            continuedMarker = leadingZeroes + nextNumberText + punctuation
            markerEnd = digitsEnd + 1
        }

        guard markerEnd < line.length, isHorizontalWhitespace(line.character(at: markerEnd)) else {
            return false
        }
        let whitespaceStart = markerEnd
        while markerEnd < line.length, isHorizontalWhitespace(line.character(at: markerEnd)) {
            markerEnd += 1
        }
        guard caret >= lineStart + markerEnd else { return false }

        let indentation = line.substring(to: markerStart)
        let markerWhitespace = line.substring(with: NSRange(
            location: whitespaceStart,
            length: markerEnd - whitespaceStart
        ))
        let markerPrefix = indentation + continuedMarker + markerWhitespace
        let itemText = line.substring(from: markerEnd)
        if itemText.trimmingCharacters(in: .whitespaces).isEmpty {
            let emptyItemRange = NSRange(location: lineStart, length: line.length)
            guard shouldChangeText(in: emptyItemRange, replacementString: "") else { return true }
            replaceCharacters(in: emptyItemRange, with: "")
            setSelectedRange(NSRange(location: lineStart, length: 0))
        } else {
            let insertion = "\n" + markerPrefix
            guard shouldChangeText(in: selection, replacementString: insertion) else { return true }
            replaceCharacters(in: selection, with: insertion)
            setSelectedRange(NSRange(location: caret + (insertion as NSString).length, length: 0))
        }
        didChangeText()
        return true
    }

    private func isMarkdownBulletMarker(_ character: unichar) -> Bool {
        character == 45 || character == 42 || character == 43
    }

    private func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(event)
        }
        super.mouseUp(with: event)
    }
}
