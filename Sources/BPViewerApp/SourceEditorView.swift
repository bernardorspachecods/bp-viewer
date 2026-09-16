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

struct SourceTextView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let cursorUTF8Offset: Int?
    let monospaced: Bool
    let syntaxHighlightPalette: JSONSyntaxColorPalette?
    let onSourceChanged: @MainActor @Sendable (String) -> Void
    let onEndEditing: @MainActor @Sendable (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSourceChanged: onSourceChanged, onEndEditing: onEndEditing)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownNSTextView()
        textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.onEndEditing(textView.string)
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
        textView.usesFindPanel = true
        textView.drawsBackground = syntaxHighlightPalette == nil
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
        scrollView.drawsBackground = syntaxHighlightPalette == nil
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

        if !context.coordinator.didRequestInitialFocus {
            focus(textView, selection: nil) {
                context.coordinator.didRequestInitialFocus = true
            }
        }

        applyBaseColors(to: textView)
        scrollView.drawsBackground = syntaxHighlightPalette == nil
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
        guard let syntaxHighlightPalette else { return }

        for token in JSONSyntaxHighlighter().tokenize(source) {
            let start = utf16Offset(in: source, utf8Offset: token.utf8Offset)
            let end = utf16Offset(in: source, utf8Offset: token.utf8End)
            guard end > start else { continue }
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor(jsonHex: syntaxHighlightPalette.color(for: token.kind)),
                range: NSRange(location: start, length: end - start)
            )
        }
    }

    private func applyBaseColors(to textView: NSTextView) {
        guard let syntaxHighlightPalette else {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
            return
        }
        textView.backgroundColor = .clear
        textView.textColor = NSColor(jsonHex: syntaxHighlightPalette.foreground)
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
        var appliedCursorUTF8Offset: Int?
        var didRequestInitialFocus = false

        init(
            onSourceChanged: @escaping @MainActor @Sendable (String) -> Void,
            onEndEditing: @escaping @MainActor @Sendable (String) -> Void
        ) {
            self.onSourceChanged = onSourceChanged
            self.onEndEditing = onEndEditing
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSourceChanged(textView.string)
        }
    }
}

private extension NSColor {
    convenience init(jsonHex hex: String) {
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

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
