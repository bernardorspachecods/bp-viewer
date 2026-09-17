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
    static let lineNumberTrailingPadding: CGFloat = 8
    static let lineMarkerLeadingPadding: CGFloat = 5
    static let lineNumberVerticalPadding: CGFloat = 4
    static let editorFontSize: CGFloat = 13
    static let codeFontFamily = "SFMono-Regular"
    static let codeFontSize: CGFloat = 13
    static let codeLineHeight: CGFloat = 24
    static let lineHeightMultiple: CGFloat = 1.55

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
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
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
        viewWidth: CGFloat,
        verticalOffset: CGFloat
    ) -> CGRect {
        var rect = lineFragmentRect.offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
        rect.origin.x = 0
        rect.origin.y += verticalOffset
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

enum SourceSyntaxHighlighting: Equatable {
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

struct SourceTextView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
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
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void
    let onDoubleClick: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSourceChanged: onSourceChanged,
            onEndEditing: onEndEditing,
            onFindMatchCount: onFindMatchCount
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownNSTextView()
        textView.onFindFocus = onFindFocus
        textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
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
        if monospaced {
            // JSON syntax requires ASCII quotes; macOS smart quotes would turn
            // a typed delimiter into a Unicode character such as U+201D.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
        }
        textView.usesFindPanel = false
        textView.drawsBackground = syntaxHighlighting == nil
        applyBaseColors(to: textView)
        textView.insertionPointColor = .controlAccentColor
        textView.string = source
        let initialSelection = cursorUTF8Offset.map { offset in
            NSRange(
                location: utf16Offset(in: source, utf8Offset: offset),
                length: 0
            )
        }
        if let initialSelection {
            textView.setSelectedRange(initialSelection)
        }
        applyTypography(to: textView)
        applySyntaxHighlighting(to: textView, source: source)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(
            width: textContainerHorizontalInset(zoom: zoom),
            height: SourceEditorLayout.verticalPadding * CGFloat(zoom)
        )
        textView.textContainer?.lineFragmentPadding = 0
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
        if isEditable {
            focus(textView, selection: initialSelection)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
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

        if !context.coordinator.didRequestInitialFocus, isEditable {
            focus(textView, selection: nil) {
                context.coordinator.didRequestInitialFocus = true
            }
        } else if !isEditable {
            context.coordinator.didRequestInitialFocus = true
        }

        applyBaseColors(to: textView)
        scrollView.drawsBackground = syntaxHighlighting == nil
        scrollView.backgroundColor = textView.backgroundColor
        if textView.string != source {
            let selectedRange = textView.selectedRange()
            textView.string = source
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (source as NSString).length),
                length: 0
            ))
        }

        applyTypography(to: textView)
        applySyntaxHighlighting(to: textView, source: source)
        context.coordinator.applyFind(
            in: textView,
            source: source,
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
              context.coordinator.appliedCursorUTF8Offset != cursorUTF8Offset else { return }
        let cursorOffset = utf16Offset(in: source, utf8Offset: cursorUTF8Offset)
        let selection = NSRange(location: cursorOffset, length: 0)
        textView.setSelectedRange(selection)
        focus(textView, selection: selection)
        context.coordinator.appliedCursorUTF8Offset = cursorUTF8Offset
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

    private func applySyntaxHighlighting(to textView: NSTextView, source: String) {
        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return }
        let range = NSRange(location: 0, length: textLength)
        textView.textStorage?.addAttribute(.foregroundColor, value: textView.textColor ?? NSColor.textColor, range: range)
        guard let syntaxHighlighting else { return }

        switch syntaxHighlighting {
        case let .json(palette):
            for token in JSONSyntaxHighlighter().tokenize(source) {
                apply(
                    color: palette.color(for: token.kind),
                    to: token.utf8Offset..<token.utf8End,
                    in: source,
                    textView: textView
                )
            }
        case let .markdown(palette):
            for token in MarkdownSyntaxHighlighter().tokenize(source) {
                apply(
                    color: palette.color(for: token.kind),
                    to: token.utf8Offset..<token.utf8End,
                    in: source,
                    textView: textView
                )
            }
        case let .latex(palette):
            for token in LatexSyntaxHighlighter().tokenize(source) {
                apply(
                    color: palette.color(for: token.kind),
                    to: token.utf8Offset..<token.utf8End,
                    in: source,
                    textView: textView
                )
            }
        }
    }

    private func apply(
        color: String,
        to utf8Range: Range<Int>,
        in source: String,
        textView: NSTextView
    ) {
        let start = utf16Offset(in: source, utf8Offset: utf8Range.lowerBound)
        let end = utf16Offset(in: source, utf8Offset: utf8Range.upperBound)
        guard end > start else { return }
        textView.textStorage?.addAttribute(
            .foregroundColor,
            value: NSColor(hex: color),
            range: NSRange(location: start, length: end - start)
        )
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

    private func utf16Offset(in source: String, utf8Offset: Int) -> Int {
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
        var didRequestInitialFocus = false
        private var findSource = ""
        private var findQuery = ""
        private var findRequestID = -1
        private var findMatches: [TextSearchMatch] = []
        private var currentFindIndex: Int?

        init(
            onSourceChanged: @escaping @MainActor @Sendable (String) -> Void,
            onEndEditing: @escaping @MainActor @Sendable (String) -> Void,
            onFindMatchCount: @escaping @MainActor @Sendable (Int) -> Void
        ) {
            self.onSourceChanged = onSourceChanged
            self.onEndEditing = onEndEditing
            self.onFindMatchCount = onFindMatchCount
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSourceChanged(textView.string)
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
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.layoutManager?.removeTemporaryAttribute(
                .backgroundColor,
                forCharacterRange: fullRange
            )
            findSource = ""
            findQuery = ""
            findRequestID = -1
            findMatches = []
            currentFindIndex = nil
            if notify {
                onFindMatchCount(0)
            }
        }

        private func updateFindHighlights(in textView: NSTextView) {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.layoutManager?.removeTemporaryAttribute(
                .backgroundColor,
                forCharacterRange: fullRange
            )

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
    var onFindFocus: (() -> Void)?
    var onDoubleClick: ((NSEvent) -> Void)?
    var showsLineNumbers = false {
        didSet { needsDisplay = true }
    }
    var lineNumberGutterWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var lineNumberFontSize: CGFloat = 11 {
        didSet { needsDisplay = true }
    }
    var lineNumberOverrides: [Int: Int] = [:] {
        didSet { needsDisplay = true }
    }
    var lineHighlights: [Int: DocumentDiffCellKind] = [:] {
        didSet { needsDisplay = true }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFindFocus?()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        onFindFocus?()
        super.mouseDown(with: event)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawLineHighlights(in: rect)
        drawLineNumberSeparator()
        if showsLineNumbers {
            drawLineNumbers(in: visibleRect)
        }
    }

    private func drawLineNumbers(in rect: NSRect) {
        guard lineNumberGutterWidth > 0 else { return }

        let fragments = lineFragments()
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

    private func lineFragments() -> [LineFragment] {
        guard let layoutManager,
              let textContainer else { return [] }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let sourceFont = font ?? NSFont.systemFont(ofSize: SourceEditorLayout.editorFontSize)
        let glyphRange = NSRange(
            location: 0,
            length: layoutManager.numberOfGlyphs
        )
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
                let physicalLine = SourceEditorLineNumbering.lineNumber(
                    atUTF16Offset: layoutManager.characterIndexForGlyph(at: glyphRange.location),
                    in: string
                )
                let baselineY = SourceEditorLayout.lineBaselineY(
                    lineFragmentRect: rect,
                    glyphLocationY: layoutManager.location(forGlyphAt: glyphRange.location).y
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
        if extraLineRect.height > 0 {
            let configuredLineHeight = fragments.first?.rect.height
                ?? (textStorage?.attribute(
                    .paragraphStyle,
                    at: 0,
                    effectiveRange: nil
                ) as? NSParagraphStyle)?.minimumLineHeight
                ?? SourceEditorLayout.codeLineHeight
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
                physicalLine: SourceEditorLineNumbering.lineCount(in: string),
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

    private func drawLineNumberSeparator() {
        guard showsLineNumbers, lineNumberGutterWidth > 0 else { return }
        let fragments = lineFragments()
        guard let top = fragments.map(\.rect.minY).min(),
              let bottom = fragments.map(\.rect.maxY).max() else { return }
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(
            x: lineNumberGutterWidth,
            y: max(0, top - SourceEditorLayout.lineNumberVerticalPadding)
        ))
        separator.line(to: NSPoint(
            x: lineNumberGutterWidth,
            y: min(bounds.height, bottom + SourceEditorLayout.lineNumberVerticalPadding)
        ))
        separator.lineWidth = 1
        separator.stroke()
    }

    private func drawLineHighlights(in rect: NSRect) {
        guard !lineHighlights.isEmpty else { return }

        for fragment in lineFragments() where fragment.rect.intersects(rect) {
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
            viewWidth: bounds.width,
            verticalOffset: font?.ascender ?? 0
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

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(event)
        }
        super.mouseUp(with: event)
    }
}
