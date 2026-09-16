import AppKit
import Foundation
import SwiftUI
import WebKit

/// Displays Word documents as a sharp, scrollable page on the app's document canvas.
struct DocxPreviewView: View {
    let url: URL
    let zoom: Double
    let previewRevision: Date?
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onZoomChanged: (Double) -> Void

    var body: some View {
        DocxHTMLPreview(
            url: url,
            zoom: zoom,
            previewRevision: previewRevision,
            findQuery: findQuery,
            findRequestID: findRequestID,
            findBackwards: findBackwards,
            isFindTarget: isFindTarget,
            onFindFocus: onFindFocus,
            onFindMatchCount: onFindMatchCount,
            onZoomChanged: onZoomChanged
        )
        .background(BPTokens.Color.canvas)
    }
}

private struct DocxHTMLPreview: NSViewRepresentable {
    let url: URL
    let zoom: Double
    let previewRevision: Date?
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let isFindTarget: Bool
    let onFindFocus: @MainActor @Sendable () -> Void
    let onFindMatchCount: @MainActor @Sendable (Int) -> Void
    let onZoomChanged: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, revision: previewRevision)
    }

    func makeNSView(context: Context) -> DocxHTMLPreviewContainer {
        let view = DocxHTMLPreviewContainer(
            onZoomChanged: onZoomChanged,
            onFindFocus: onFindFocus,
            onFindMatchCount: onFindMatchCount
        )
        view.setPreview(url: url, zoom: zoom)
        return view
    }

    func updateNSView(_ view: DocxHTMLPreviewContainer, context: Context) {
        view.setZoom(zoom)
        view.updateFind(
            query: findQuery,
            requestID: findRequestID,
            backwards: findBackwards,
            isFindTarget: isFindTarget
        )

        guard context.coordinator.url != url || context.coordinator.revision != previewRevision else {
            return
        }

        context.coordinator.url = url
        context.coordinator.revision = previewRevision
        view.setPreview(url: url, zoom: zoom)
    }

    static func dismantleNSView(_ view: DocxHTMLPreviewContainer, coordinator: Coordinator) {
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

@MainActor
private final class DocxHTMLPreviewContainer: NSView, WKNavigationDelegate {
    private let webView: ZoomableDocxWebView
    private let statusLabel = NSTextField(labelWithString: "Preparing Word Preview…")
    private var previewURL: URL?
    private var previewTask: Task<Void, Never>?
    private var artifactDirectory: URL?
    private var zoom = 1.0
    private let onZoomChanged: (Double) -> Void
    private var findQuery = ""
    private var findRequestID = -1
    private var findBackwards = false
    private var isFindTarget = true
    private let onFindMatchCount: @MainActor @Sendable (Int) -> Void

    init(
        onZoomChanged: @escaping (Double) -> Void,
        onFindFocus: @escaping @MainActor @Sendable () -> Void,
        onFindMatchCount: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        self.onZoomChanged = onZoomChanged
        self.onFindMatchCount = onFindMatchCount
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = ZoomableDocxWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        webView.onFindFocus = onFindFocus
        configure()
    }

    required init?(coder: NSCoder) {
        onZoomChanged = { _ in }
        onFindMatchCount = { _ in }
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = ZoomableDocxWebView(frame: .zero, configuration: configuration)
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        updateCanvasAppearance()
        webView.frame = bounds
        statusLabel.frame = NSRect(
            x: 24,
            y: (bounds.height - 28) / 2,
            width: max(bounds.width - 48, 200),
            height: 28
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCanvasAppearance()
    }

    func setPreview(url: URL, zoom: Double) {
        setZoom(zoom)
        guard previewURL != url else {
            loadPreview(url: url)
            return
        }

        previewURL = url
        previewTask?.cancel()
        removeArtifact()
        webView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "Preparing Word Preview…"

        previewTask = Task { @MainActor [weak self] in
            do {
                let artifact = try await Task.detached(priority: .userInitiated) {
                    try DocxHTMLConverter.convert(url: url)
                }.value
                guard let self, self.previewURL == url, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: artifact.directoryURL)
                    return
                }
                self.artifactDirectory = artifact.directoryURL
                self.loadPreview(url: artifact.htmlURL)
            } catch {
                guard let self, self.previewURL == url, !Task.isCancelled else { return }
                self.statusLabel.stringValue = "Unable to prepare the Word preview."
                self.statusLabel.isHidden = false
            }
        }
    }

    func setZoom(_ zoom: Double) {
        self.zoom = min(max(CGFloat(zoom), 0.7), 2.0)
        webView.currentZoom = self.zoom
        webView.pageZoom = self.zoom
    }

    func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        webView.navigationDelegate = nil
        webView.stopLoading()
        removeArtifact()
    }

    func updateFind(query: String, requestID: Int, backwards: Bool, isFindTarget: Bool) {
        let queryChanged = findQuery != query
        let targetChanged = self.isFindTarget != isFindTarget
        guard findQuery != query
                || findRequestID != requestID
                || findBackwards != backwards
                || self.isFindTarget != isFindTarget else { return }
        findQuery = query
        findRequestID = requestID
        findBackwards = backwards
        self.isFindTarget = isFindTarget
        applyFind(updateMatchCount: queryChanged || targetChanged)
    }

    private func applyFind(updateMatchCount: Bool) {
        guard isFindTarget, !webView.isHidden else { return }
        if updateMatchCount {
            WebViewFindSupport.countMatches(in: webView, query: findQuery) { [onFindMatchCount] count in
                onFindMatchCount(count)
            }
        }
        WebViewFindSupport.find(in: webView, query: findQuery, backwards: findBackwards)
    }

    private func configure() {
        wantsLayer = true
        updateCanvasAppearance()

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.onMagnificationChanged = { [weak self] zoom in
            self?.setZoom(Double(zoom))
        }
        webView.onMagnificationEnded = { [weak self] magnification in
            guard let self else { return }
            self.setZoom(Double(magnification))
            self.onZoomChanged(Double(self.zoom))
        }
        webView.autoresizingMask = [.width, .height]
        webView.isHidden = true
        addSubview(webView)

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.autoresizingMask = [.width]
        addSubview(statusLabel)
    }

    private func updateCanvasAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PreviewCanvasStyle.backgroundColor.cgColor
        }
    }

    private func loadPreview(url: URL) {
        let accessURL = artifactDirectory ?? url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: accessURL)
    }

    private func removeArtifact() {
        guard let artifactDirectory else { return }
        try? FileManager.default.removeItem(at: artifactDirectory)
        self.artifactDirectory = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.pageZoom = zoom
        webView.isHidden = false
        statusLabel.isHidden = true
        applyFind(updateMatchCount: true)
    }
}

private final class ZoomableDocxWebView: FindTrackingWKWebView {
    var currentZoom: CGFloat = 1.0
    var onMagnificationChanged: ((CGFloat) -> Void)?
    var onMagnificationEnded: ((CGFloat) -> Void)?

    override func magnify(with event: NSEvent) {
        let scale = max(CGFloat(0.1), 1 + event.magnification)
        let targetZoom = min(max(currentZoom * scale, 0.7), 2.0)
        currentZoom = targetZoom
        onMagnificationChanged?(targetZoom)

        if event.phase == .ended {
            onMagnificationEnded?(targetZoom)
        }
    }
}

private struct DocxHTMLArtifact: Sendable {
    let htmlURL: URL
    let directoryURL: URL
}

private struct DocxPageSize {
    let width: CGFloat
    let height: CGFloat

    static let a4 = DocxPageSize(width: 794, height: 1123)
}

private enum DocxHTMLConverter {
    static func convert(url: URL) throws -> DocxHTMLArtifact {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-viewer-docx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let htmlURL = directoryURL.appendingPathComponent("document.html")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = [
            "-convert", "html",
            "-output", htmlURL.path,
            url.path
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: htmlURL.path) else {
            try? FileManager.default.removeItem(at: directoryURL)
            throw DocxHTMLConversionError.failed
        }

        let source = try String(contentsOf: htmlURL, encoding: .utf8)
        let pageSize = (try? pageSize(from: url)) ?? .a4
        let headerImageName = extractHeaderImage(from: url, to: directoryURL)
        let styledSource = DocxHTMLStyler.apply(
            to: source,
            pageSize: pageSize,
            headerImageName: headerImageName
        )
        try styledSource.write(to: htmlURL, atomically: true, encoding: .utf8)
        return DocxHTMLArtifact(htmlURL: htmlURL, directoryURL: directoryURL)
    }

    private static func pageSize(from url: URL) throws -> DocxPageSize {
        let source = try String(
            data: unzipData(from: url, entry: "word/document.xml"),
            encoding: .utf8
        ) ?? ""
        guard let start = source.range(of: "<w:pgSz"),
              let end = source.range(of: ">", range: start.upperBound..<source.endIndex),
              let width = attribute("w:w", in: String(source[start.lowerBound..<end.upperBound])),
              let height = attribute("w:h", in: String(source[start.lowerBound..<end.upperBound])),
              let widthTwips = Double(width),
              let heightTwips = Double(height) else {
            throw DocxHTMLConversionError.failed
        }
        return DocxPageSize(
            width: CGFloat(widthTwips / 15),
            height: CGFloat(heightTwips / 15)
        )
    }

    private static func extractHeaderImage(from url: URL, to directoryURL: URL) -> String? {
        guard let headerSource = try? String(
            data: unzipData(from: url, entry: "word/header1.xml"),
            encoding: .utf8
        ),
        let relationshipID = attribute("r:embed", in: headerSource),
        let relationships = try? String(
            data: unzipData(from: url, entry: "word/_rels/header1.xml.rels"),
            encoding: .utf8
        ),
        let relationshipRange = relationships.range(of: "Id=\"\(relationshipID)\"") else {
            return nil
        }

        let relationshipStart = relationships[..<relationshipRange.lowerBound]
            .range(of: "<Relationship", options: .backwards)?.lowerBound ?? relationshipRange.lowerBound
        guard let relationshipEnd = relationships.range(
            of: ">",
            range: relationshipRange.upperBound..<relationships.endIndex
        ) else {
            return nil
        }
        let relationship = String(relationships[relationshipStart..<relationshipEnd.upperBound])
        guard let target = attribute("Target", in: relationship) else { return nil }

        let zipEntry = "word/" + target
            .replacingOccurrences(of: "../", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let imageData = try? unzipData(from: url, entry: zipEntry) else { return nil }

        let imageName = "header-" + URL(fileURLWithPath: zipEntry).lastPathComponent
        let imageURL = directoryURL.appendingPathComponent(imageName)
        guard (try? imageData.write(to: imageURL, options: .atomic)) != nil else { return nil }
        return imageName
    }

    private static func unzipData(from url: URL, entry: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocxHTMLConversionError.failed
        }
        return outputPipe.fileHandleForReading.readDataToEndOfFile()
    }

    private static func attribute(_ name: String, in source: String) -> String? {
        let prefix = "\(name)=\""
        guard let start = source.range(of: prefix),
              let end = source.range(of: "\"", range: start.upperBound..<source.endIndex) else {
            return nil
        }
        return String(source[start.upperBound..<end.lowerBound])
    }

    private enum DocxHTMLConversionError: Error {
        case failed
    }
}

private enum DocxHTMLStyler {
    static func apply(
        to source: String,
        pageSize: DocxPageSize,
        headerImageName: String?
    ) -> String {
        let headerMarkup = headerImageName.map {
            "<img class=\"bp-viewer-header-logo\" src=\"\($0)\" alt=\"\">"
        } ?? ""
        let style = """
        <style id="bp-viewer-docx-style">
          :root {
            color-scheme: light;
          }
          html {
            min-height: 100%;
            width: 100%;
            min-width: 100%;
            background: transparent;
          }
          body {
            margin: 0;
            width: 100%;
            min-width: 100%;
            background: transparent;
            display: flex;
            flex-direction: column;
            align-items: center;
            font-family: Calibri, "Helvetica Neue", Arial, sans-serif;
            font-size: 16px;
            line-height: 1.15;
            overflow-wrap: break-word;
          }
          .bp-viewer-page,
          .bp-viewer-page p,
          .bp-viewer-page span {
            font-family: Calibri, "Helvetica Neue", Arial, sans-serif;
            font-size: 16px;
            line-height: 1.15;
          }
          .bp-viewer-page p {
            margin: 0 0 18.67px;
          }
          .bp-viewer-page p.p1,
          .bp-viewer-page p.p2,
          .bp-viewer-page p.p3 {
            margin-bottom: 14px;
          }
          .bp-viewer-page p:last-child {
            margin-bottom: 0;
          }
          .bp-viewer-page p.p2 {
            font-size: 18.67px;
          }
          .bp-viewer-page {
            box-sizing: border-box;
            position: relative;
            width: \(pageSize.width)px;
            min-height: \(pageSize.height)px;
            flex: 0 0 auto;
            margin: 16px 0;
            padding: 96px;
            background: #ffffff;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.24);
            color: #202124;
          }
          .bp-viewer-header-logo {
            position: absolute;
            top: 60px;
            left: 96px;
            display: block;
            width: 354px;
            height: auto;
          }
          .bp-viewer-page > * {
            max-width: 100%;
          }
          img {
            max-width: 100%;
            height: auto;
          }
          table {
            max-width: 100%;
          }
        </style>
        """

        var styledSource = source
        if let closingHead = styledSource.range(of: "</head>", options: .caseInsensitive) {
            styledSource.replaceSubrange(closingHead, with: style + "</head>")
        }

        guard let bodyStart = styledSource.range(of: "<body", options: .caseInsensitive),
              let bodyEnd = styledSource.range(of: "</body>", options: .caseInsensitive),
              let openingTagEnd = styledSource.range(
                  of: ">",
                  range: bodyStart.upperBound..<bodyEnd.lowerBound
              ) else {
            return "<html><head>\(style)</head><body><div class=\"bp-viewer-page\">\(headerMarkup)\(source)</div></body></html>"
        }

        styledSource.insert(
            contentsOf: "<div class=\"bp-viewer-page\">\(headerMarkup)",
            at: openingTagEnd.upperBound
        )
        if let updatedBodyEnd = styledSource.range(of: "</body>", options: .caseInsensitive) {
            styledSource.insert(contentsOf: "</div>", at: updatedBodyEnd.lowerBound)
        }
        return styledSource
    }
}
