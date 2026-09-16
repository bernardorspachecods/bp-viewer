import AppKit
import BPViewerCore
@preconcurrency import PDFKit
import SwiftUI

struct SnapshotArtifactStore {
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        directoryURL = supportDirectory.appendingPathComponent("bp-viewer/snapshots", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(_ image: NSImage, id: String) throws -> URL {
        let bitmap = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
            ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        guard let bitmap,
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotStoreError.encodingFailed
        }

        let url = directoryURL.appendingPathComponent(id).appendingPathExtension("png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    func load(from url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum SnapshotStoreError: Error {
        case encodingFailed
    }
}

@MainActor
final class SnapshotWindowManager: NSObject, NSWindowDelegate {
    private var windows: [String: NSPanel] = [:]
    private let onUserClose: (String) -> Void
    private var suppressCloseCallbacks = false

    init(onUserClose: @escaping (String) -> Void) {
        self.onUserClose = onUserClose
    }

    func open(record: SnapshotRecord, image: NSImage, above parent: NSWindow?) {
        if let window = windows[record.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let imageSize = image.size
        let imageWidth = max(imageSize.width, 1)
        let imageHeight = max(imageSize.height, 1)
        let scale = max(
            min(1, min(720 / imageWidth, 620 / imageHeight)),
            max(180 / imageWidth, 120 / imageHeight)
        )
        let contentSize = NSSize(
            width: imageWidth * scale,
            height: imageHeight * scale
        )
        let panel = SnapshotPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = record.title
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.styleMask.insert(.resizable)
        panel.contentAspectRatio = NSSize(width: imageWidth, height: imageHeight)
        panel.contentMinSize = NSSize(width: 180, height: 120)
        panel.minSize = NSSize(width: 180, height: 120)

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        panel.contentView = NSView()
        panel.contentView?.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(imageView)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        windows[record.id] = panel
        if let parent {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func closeAllPreservingRecords() {
        suppressCloseCallbacks = true
        windows.values.forEach { $0.close() }
        windows.removeAll()
        suppressCloseCallbacks = false
    }

    func prepareForTermination() {
        suppressCloseCallbacks = true
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let entry = windows.first(where: { $0.value === panel }) else {
            return
        }
        windows.removeValue(forKey: entry.key)
        if !suppressCloseCallbacks {
            onUserClose(entry.key)
        }
    }
}

@MainActor
final class SnapshotPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command], event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct SnapshotSelectionOverlay: NSViewRepresentable {
    let onCancel: () -> Void
    let onCapture: (NSImage) -> Void

    func makeNSView(context: Context) -> SnapshotSelectionNSView {
        SnapshotSelectionNSView(onCancel: onCancel, onCapture: onCapture)
    }

    func updateNSView(_ nsView: SnapshotSelectionNSView, context: Context) {
        nsView.onCancel = onCancel
        nsView.onCapture = onCapture
    }
}

@MainActor
final class SnapshotSelectionNSView: NSView {
    var onCancel: () -> Void
    var onCapture: (NSImage) -> Void

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var sourceScrollView: NSScrollView?
    private var initialScrollOrigin: CGPoint = .zero
    private var initialDocumentPoint: CGPoint?
    private var sampledScrollOrigins: [CGPoint] = []
    private var autoScrollTimer: Timer?
    private var lastWindowPoint: NSPoint?

    init(onCancel: @escaping () -> Void, onCapture: @escaping (NSImage) -> Void) {
        self.onCancel = onCancel
        self.onCapture = onCapture
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("SnapshotSelectionNSView does not support NSCoder")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selection = selectionRect, !selection.isEmpty else { return }
        NSGraphicsContext.current?.compositingOperation = .clear
        selection.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        lastWindowPoint = event.locationInWindow
        sourceScrollView = scrollView(containing: event.locationInWindow)
        initialScrollOrigin = sourceScrollView?.contentView.bounds.origin ?? .zero
        initialDocumentPoint = sourceScrollView?.documentView.map { documentView in
            documentView.convert(point, from: self)
        }
        sampledScrollOrigins = [initialScrollOrigin]
        startAutoScrollTimer()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        lastWindowPoint = event.locationInWindow
        autoScrollIfNeeded()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        lastWindowPoint = event.locationInWindow
        stopAutoScrollTimer()
        captureSelection()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func startAutoScrollTimer() {
        stopAutoScrollTimer()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoScrollIfNeeded()
            }
        }
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func autoScrollIfNeeded() {
        guard let sourceScrollView,
              let lastWindowPoint,
              let clipView = sourceScrollView.contentView as NSClipView? else { return }

        let scrollFrame = sourceScrollView.convert(sourceScrollView.bounds, to: nil)
        let edge: CGFloat = 42
        var origin = clipView.bounds.origin
        let speed: CGFloat = 18

        if lastWindowPoint.y < scrollFrame.minY + edge {
            origin.y -= speed
        } else if lastWindowPoint.y > scrollFrame.maxY - edge {
            origin.y += speed
        } else {
            return
        }

        if let documentView = clipView.documentView {
            let documentBounds = documentView.bounds
            let maximumY = max(documentBounds.minY, documentBounds.maxY - clipView.bounds.height)
            origin.y = min(max(origin.y, documentBounds.minY), maximumY)
        }

        guard origin != clipView.bounds.origin else { return }
        clipView.setBoundsOrigin(origin)
        sourceScrollView.reflectScrolledClipView(clipView)
        sampledScrollOrigins.append(origin)
        needsDisplay = true
    }

    private func scrollView(containing windowPoint: NSPoint) -> NSScrollView? {
        guard let contentView = window?.contentView else { return nil }
        var candidates: [(NSScrollView, CGFloat)] = []

        func visit(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                let frame = scrollView.convert(scrollView.bounds, to: nil)
                if frame.contains(windowPoint) {
                    candidates.append((scrollView, frame.width * frame.height))
                }
            }
            view.subviews.forEach(visit)
        }

        visit(contentView)
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private func captureSelection() {
        guard let startPoint,
              let currentPoint,
              let window,
              let selectionRect else {
            cancelSelection()
            return
        }

        let scrollView = sourceScrollView
        let finalOrigin = scrollView?.contentView.bounds.origin ?? initialScrollOrigin
        let startDocumentPoint = initialDocumentPoint ?? CGPoint(
            x: startPoint.x + initialScrollOrigin.x,
            y: startPoint.y + initialScrollOrigin.y
        )
        let endDocumentPoint = scrollView?.documentView.map { documentView in
            documentView.convert(currentPoint, from: self)
        } ?? CGPoint(
            x: currentPoint.x + finalOrigin.x,
            y: currentPoint.y + finalOrigin.y
        )
        let documentRect = CGRect(
            x: min(startDocumentPoint.x, endDocumentPoint.x),
            y: min(startDocumentPoint.y, endDocumentPoint.y),
            width: abs(endDocumentPoint.x - startDocumentPoint.x),
            height: abs(endDocumentPoint.y - startDocumentPoint.y)
        )
        guard documentRect.width >= 12,
              documentRect.height >= 12 else {
            cancelSelection()
            return
        }

        isHidden = true
        window.displayIfNeeded()

        let image: NSImage?
        if let scrollView,
           let pdfImage = SnapshotPDFCapture.image(of: documentRect, in: scrollView) {
            image = pdfImage
        } else if let scrollView, documentRect.height > scrollView.contentView.bounds.height + 1 {
            image = captureScrolled(documentRect: documentRect, in: scrollView)
        } else {
            image = SnapshotWindowCapture.image(of: selectionRect, in: self)
        }

        isHidden = false
        sourceScrollView?.contentView.setBoundsOrigin(finalOrigin)
        if let sourceScrollView {
            sourceScrollView.reflectScrolledClipView(sourceScrollView.contentView)
        }
        cancelSelectionState()

        guard let image else {
            onCancel()
            return
        }
        onCapture(image)
    }

    private func captureScrolled(documentRect: CGRect, in scrollView: NSScrollView) -> NSImage? {
        let clipView = scrollView.contentView
        guard let documentView = clipView.documentView else { return nil }
        let viewportHeight = max(clipView.bounds.height, 1)
        var offsets = sampledScrollOrigins + [initialScrollOrigin, clipView.bounds.origin]
        let minimumY = min(initialScrollOrigin.y, clipView.bounds.origin.y)
        let maximumY = max(initialScrollOrigin.y, clipView.bounds.origin.y)
        let step = max(viewportHeight * 0.72, 24)
        var y = minimumY
        while y <= maximumY {
            offsets.append(CGPoint(x: clipView.bounds.origin.x, y: y))
            y += step
        }
        offsets = Array(Set(offsets)).sorted { $0.y < $1.y }

        var segments: [SnapshotImageSegment] = []
        for offset in offsets {
            clipView.setBoundsOrigin(offset)
            scrollView.reflectScrolledClipView(clipView)
            window?.displayIfNeeded()

            let visibleDocumentRect = documentView.convert(clipView.bounds, from: clipView)
            let intersection = documentRect.intersection(visibleDocumentRect)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }

            let overlayRect = documentView.convert(intersection, to: self)
            guard let image = SnapshotWindowCapture.image(of: overlayRect, in: self) else { continue }
            segments.append(SnapshotImageSegment(documentRect: intersection, image: image))
        }

        guard !segments.isEmpty else { return nil }
        return SnapshotImageComposer.compose(segments: segments, documentRect: documentRect)
    }

    private func cancelSelection() {
        stopAutoScrollTimer()
        cancelSelectionState()
        onCancel()
    }

    private func cancelSelectionState() {
        startPoint = nil
        currentPoint = nil
        sourceScrollView = nil
        initialDocumentPoint = nil
        sampledScrollOrigins = []
        needsDisplay = true
    }
}

private struct SnapshotImageSegment {
    let documentRect: CGRect
    let image: NSImage
}

@MainActor
private enum SnapshotImageComposer {
    static func compose(segments: [SnapshotImageSegment], documentRect: CGRect) -> NSImage? {
        let image = NSImage(size: documentRect.size)
        image.lockFocusFlipped(false)
        for segment in segments {
            let destination = CGRect(
                x: segment.documentRect.minX - documentRect.minX,
                y: segment.documentRect.minY - documentRect.minY,
                width: segment.documentRect.width,
                height: segment.documentRect.height
            )
            segment.image.draw(in: destination, from: .zero, operation: .copy, fraction: 1)
        }
        image.unlockFocus()
        return image
    }
}

@MainActor
private enum SnapshotPDFCapture {
    static func image(of documentRect: CGRect, in scrollView: NSScrollView) -> NSImage? {
        guard let pdfView = ancestorPDFView(of: scrollView),
              let document = pdfView.document,
              let documentView = scrollView.documentView,
              !documentRect.isNull,
              documentRect.width > 1,
              documentRect.height > 1 else {
            return nil
        }

        let selectionInPDFView = documentView.convert(documentRect, to: pdfView)
        guard !selectionInPDFView.isNull,
              selectionInPDFView.width > 1,
              selectionInPDFView.height > 1 else {
            return nil
        }

        let image = NSImage(size: selectionInPDFView.size)
        image.lockFocusFlipped(false)
        NSColor.white.setFill()
        CGRect(origin: .zero, size: selectionInPDFView.size).fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }

            let pageBounds = page.bounds(for: .cropBox)
            let pageRectInPDFView = pdfView.convert(pageBounds, from: page)
            let intersection = selectionInPDFView.intersection(pageRectInPDFView)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0,
                  pageBounds.width > 0,
                  pageBounds.height > 0 else {
                continue
            }

            let destination = CGRect(
                x: intersection.minX - selectionInPDFView.minX,
                y: intersection.minY - selectionInPDFView.minY,
                width: intersection.width,
                height: intersection.height
            )
            let scaleX = pageRectInPDFView.width / pageBounds.width
            let scaleY = pageRectInPDFView.height / pageBounds.height
            guard scaleX > 0, scaleY > 0 else { continue }

            context.saveGState()
            context.clip(to: destination)
            context.translateBy(
                x: pageRectInPDFView.minX - selectionInPDFView.minX,
                y: pageRectInPDFView.minY - selectionInPDFView.minY
            )
            context.scaleBy(x: scaleX, y: scaleY)
            context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            page.draw(with: .cropBox, to: context)
            context.restoreGState()
        }

        image.unlockFocus()
        return image
    }

    private static func ancestorPDFView(of view: NSView) -> PDFView? {
        var candidate: NSView? = view
        while let current = candidate {
            if let pdfView = current as? PDFView {
                return pdfView
            }
            candidate = current.superview
        }
        return nil
    }
}

@MainActor
private enum SnapshotWindowCapture {
    static func image(of rectInView: CGRect, in view: NSView) -> NSImage? {
        guard let contentView = view.window?.contentView,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            return nil
        }

        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        let contentRect = view.convert(rectInView, to: contentView)
            .intersection(contentView.bounds)
        guard !contentRect.isNull, contentRect.width > 1, contentRect.height > 1 else {
            return nil
        }

        // The SwiftUI/AppKit view hierarchy may be flipped, while the bitmap
        // representation uses a bottom-left origin. Convert the selected view
        // rect before drawing it out of the cached window image.
        let bitmapRect = CGRect(
            x: contentRect.minX,
            y: contentView.bounds.maxY - contentRect.maxY,
            width: contentRect.width,
            height: contentRect.height
        )

        let scaleX = CGFloat(representation.pixelsWide) / max(contentView.bounds.width, 1)
        let scaleY = CGFloat(representation.pixelsHigh) / max(contentView.bounds.height, 1)
        let pixelRect = CGRect(
            x: floor(bitmapRect.minX * scaleX),
            // NSBitmapImageRep's source rect is bottom-left based; CGImage's
            // crop rect addresses the raw pixel rows from the opposite edge.
            y: floor(CGFloat(representation.pixelsHigh) - bitmapRect.maxY * scaleY),
            width: ceil(bitmapRect.width * scaleX),
            height: ceil(bitmapRect.height * scaleY)
        ).intersection(CGRect(
            x: 0,
            y: 0,
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        ))

        if let sourceImage = representation.cgImage,
           let croppedImage = sourceImage.cropping(to: pixelRect) {
            let croppedRepresentation = NSBitmapImageRep(cgImage: croppedImage)
            croppedRepresentation.size = contentRect.size
            let image = NSImage(size: contentRect.size)
            image.addRepresentation(croppedRepresentation)
            return image
        }

        // Keep the working AppKit path as a fallback if a bitmap cannot be cropped.
        let image = NSImage(size: contentRect.size)
        image.lockFocusFlipped(false)
        representation.draw(
            in: CGRect(origin: .zero, size: contentRect.size),
            from: bitmapRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        image.unlockFocus()
        return image
    }
}
