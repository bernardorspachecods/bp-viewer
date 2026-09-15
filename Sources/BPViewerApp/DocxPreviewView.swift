import AppKit
import QuickLookUI
import SwiftUI

/// Displays Word documents through the macOS renderer so that Word layout,
/// pagination, images, tables, headers, footers and styles remain intact.
struct DocxPreviewView: View {
    let url: URL
    let zoom: Double
    let previewRevision: Date?

    var body: some View {
        DocxQuickLookPreview(
            url: url,
            zoom: zoom,
            previewRevision: previewRevision
        )
        .background(BPTokens.Color.canvas)
    }
}

private struct DocxQuickLookPreview: NSViewRepresentable {
    let url: URL
    let zoom: Double
    let previewRevision: Date?

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, revision: previewRevision)
    }

    func makeNSView(context: Context) -> DocxQuickLookContainer {
        let view = DocxQuickLookContainer()
        view.setPreview(url: url, zoom: zoom)
        return view
    }

    func updateNSView(_ view: DocxQuickLookContainer, context: Context) {
        view.setZoom(zoom)

        guard context.coordinator.url != url || context.coordinator.revision != previewRevision else {
            return
        }

        context.coordinator.url = url
        context.coordinator.revision = previewRevision
        view.setPreview(url: url, zoom: zoom)
    }

    static func dismantleNSView(_ view: DocxQuickLookContainer, coordinator: Coordinator) {
        view.closePreview()
    }

    @MainActor
    final class Coordinator {
        var url: URL
        var revision: Date?

        init(url: URL, revision: Date?) {
            self.url = url
            self.revision = revision
        }
    }
}

private final class DocxQuickLookContainer: NSView {
    private let scrollView = NSScrollView()
    private let previewView = QLPreviewView(frame: .zero, style: .normal)!
    private var previewURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        previewView.frame = scrollView.contentView.bounds
    }

    func setPreview(url: URL, zoom: Double) {
        setZoom(zoom)
        guard previewURL != url else {
            previewView.refreshPreviewItem()
            return
        }

        previewURL = url
        previewView.previewItem = url as NSURL
    }

    func setZoom(_ zoom: Double) {
        let normalizedZoom = min(max(CGFloat(zoom), 0.7), 2.0)
        guard abs(scrollView.magnification - normalizedZoom) > 0.001 else { return }
        scrollView.magnification = normalizedZoom
    }

    func closePreview() {
        previewView.close()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = PreviewCanvasStyle.backgroundColor.cgColor

        scrollView.drawsBackground = true
        scrollView.backgroundColor = PreviewCanvasStyle.backgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.7
        scrollView.maxMagnification = 2.0
        scrollView.magnification = 1.0
        scrollView.autoresizingMask = [.width, .height]

        previewView.shouldCloseWithWindow = false
        previewView.autoresizingMask = [.width, .height]
        previewView.frame = scrollView.contentView.bounds
        scrollView.documentView = previewView
        addSubview(scrollView)
    }
}
