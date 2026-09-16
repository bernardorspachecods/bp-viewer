import AppKit
import BPViewerCore
import SwiftUI

enum SourceEditorLayout {
    static let contentMaxWidth: CGFloat = 860
    static let horizontalPadding: CGFloat = 52
    static let codeFontFamily = "SFMono-Regular"
    static let codeFontSize: CGFloat = 13
    static let codeLineHeight: CGFloat = 24
    static let lineHeightMultiple: CGFloat = 1.55
}

enum SourceSyntaxHighlighting: Equatable {
    case json(JSONSyntaxColorPalette)
    case markdown(MarkdownSyntaxColorPalette)

    var background: String {
        switch self {
        case let .json(palette): palette.background
        case let .markdown(palette): palette.background
        }
    }

    var foreground: String {
        switch self {
        case let .json(palette): palette.foreground
        case let .markdown(palette): palette.foreground
        }
    }
}

struct SourceTextView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
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
        textView.isRichText = false
        textView.isEditable = true
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
        applyTypography(to: textView)
        applySyntaxHighlighting(to: textView, source: source)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(
            width: SourceEditorLayout.horizontalPadding * CGFloat(zoom),
            height: 40 * CGFloat(zoom)
        )
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
        scrollView.drawsBackground = syntaxHighlighting == nil
        scrollView.backgroundColor = textView.backgroundColor
        scrollView.documentView = textView
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSourceChanged = onSourceChanged
        context.coordinator.onEndEditing = onEndEditing
        context.coordinator.onFindMatchCount = onFindMatchCount

        if !context.coordinator.didRequestInitialFocus {
            focus(textView, selection: nil) {
                context.coordinator.didRequestInitialFocus = true
            }
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
            width: SourceEditorLayout.horizontalPadding * CGFloat(zoom),
            height: 40 * CGFloat(zoom)
        )

        guard let cursorUTF8Offset,
              context.coordinator.appliedCursorUTF8Offset != cursorUTF8Offset else { return }
        let cursorOffset = utf16Offset(in: source, utf8Offset: cursorUTF8Offset)
        let selection = NSRange(location: cursorOffset, length: 0)
        textView.setSelectedRange(selection)
        focus(textView, selection: selection)
        context.coordinator.appliedCursorUTF8Offset = cursorUTF8Offset
    }

    private func applyTypography(to textView: NSTextView) {
        let bodyFont = monospaced
            ? (NSFont(
                name: SourceEditorLayout.codeFontFamily,
                size: SourceEditorLayout.codeFontSize
            ) ?? NSFont.monospacedSystemFont(ofSize: SourceEditorLayout.codeFontSize, weight: .regular))
            : NSFont.preferredFont(forTextStyle: .body)
        let font = bodyFont.withSize(bodyFont.pointSize * zoom)
        let paragraphStyle = NSMutableParagraphStyle()
        if monospaced {
            let lineHeight = SourceEditorLayout.codeLineHeight * zoom
            paragraphStyle.minimumLineHeight = lineHeight
            paragraphStyle.maximumLineHeight = lineHeight
        } else {
            paragraphStyle.lineHeightMultiple = SourceEditorLayout.lineHeightMultiple
        }

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
    var onEscape: (() -> Void)?
    var onMarkdownShortcut: ((MarkdownInlineFormatting) -> Void)?
    var onFindFocus: (() -> Void)?

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
}
