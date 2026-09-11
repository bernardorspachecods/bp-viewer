import AppKit
@preconcurrency import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let data: Data
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let pageIndex: Int
    let onPageChanged: (Int) -> Void
    @Binding var isOutlineVisible: Bool
    @State private var requestedPageIndex: Int?
    @State private var selectedOutlineID: String?

    private var outlineEntries: [PDFOutlineEntry] {
        PDFOutlineEntry.entries(from: data)
    }

    private var outlineItems: [DocumentOutlineItem] {
        outlineEntries.map {
            DocumentOutlineItem(
                id: $0.id,
                title: $0.title,
                level: $0.level,
                isSelectable: $0.pageIndex != nil
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !outlineItems.isEmpty {
                DocumentOutlineToolbar(isVisible: isOutlineVisible) {
                    isOutlineVisible.toggle()
                }
            }

            HStack(spacing: 0) {
                if isOutlineVisible {
                    DocumentOutlineSidebar(
                        entries: outlineItems,
                        selectedID: selectedOutlineID
                    ) { item in
                        guard let pageIndex = outlineEntries.first(where: { $0.id == item.id })?.pageIndex else {
                            return
                        }
                        selectedOutlineID = item.id
                        requestedPageIndex = pageIndex
                    }
                    Divider()
                }

                PDFKitPreviewView(
                    data: data,
                    zoom: zoom,
                    findQuery: findQuery,
                    findRequestID: findRequestID,
                    findBackwards: findBackwards,
                    pageIndex: pageIndex,
                    requestedPageIndex: requestedPageIndex,
                    onPageChanged: { index in
                        if requestedPageIndex == index {
                            requestedPageIndex = nil
                        }
                        onPageChanged(index)
                    }
                )
            }
        }
    }
}

private struct PDFOutlineEntry: Identifiable {
    let id: String
    let title: String
    let level: Int
    let pageIndex: Int?

    static func entries(from data: Data) -> [PDFOutlineEntry] {
        guard let document = PDFDocument(data: data),
              let root = document.outlineRoot else {
            return []
        }
        return entries(from: root, document: document, prefix: "outline", level: 0)
    }

    private static func entries(
        from outline: PDFOutline,
        document: PDFDocument,
        prefix: String,
        level: Int
    ) -> [PDFOutlineEntry] {
        (0..<outline.numberOfChildren).flatMap { offset -> [PDFOutlineEntry] in
            guard let child = outline.child(at: offset) else { return [] }
            let id = "\(prefix)-\(offset)"
            let children = entries(from: child, document: document, prefix: id, level: level + 1)
            let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pageIndex: Int? = child.destination.flatMap { destination in
                guard let page = destination.page else { return nil }
                return document.index(for: page)
            }
            guard !title.isEmpty || pageIndex != nil || !children.isEmpty else {
                return []
            }

            let entry = PDFOutlineEntry(
                id: id,
                title: title.isEmpty ? "Sem título" : title,
                level: level,
                pageIndex: pageIndex,
            )
            return [entry] + children
        }
    }
}

private struct PDFKitPreviewView: NSViewRepresentable {
    let data: Data
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let pageIndex: Int
    let requestedPageIndex: Int?
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeNSView(context: Context) -> FittingPDFView {
        let view = FittingPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = false
        view.backgroundColor = .windowBackgroundColor
        view.delegate = context.coordinator
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: FittingPDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        let documentChanged = view.loadedPDFData != data
        let previousPosition = documentChanged
            ? view.readingPosition(fallbackPageIndex: pageIndex)
            : nil
        if documentChanged {
            view.isRestoringPosition = true
            view.document = PDFDocument(data: data)
            view.loadedPDFData = data
        }
        let zoomChanged = view.zoom != zoom
        view.zoom = zoom
        if documentChanged || zoomChanged {
            view.fitPageWidth(force: true)
        }
        view.updateFind(
            query: findQuery,
            requestID: findRequestID,
            backwards: findBackwards,
            force: documentChanged
        )
        if let previousPosition {
            view.scheduleRestore(of: previousPosition) { restoredPageIndex in
                onPageChanged(restoredPageIndex)
            }
        } else {
            view.goToPage(at: requestedPageIndex ?? pageIndex)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPageChanged: (Int) -> Void
        private var pageChangedObservers: [ObserverToken] = []

        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func observe(_ view: FittingPDFView) {
            let notificationNames: [Notification.Name] = [
                Notification.Name.PDFViewPageChanged,
                Notification.Name.PDFViewVisiblePagesChanged
            ]
            let observers = notificationNames.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: view,
                    queue: .main
                ) { [weak self, weak view] _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view, !view.isRestoringPosition,
                              let page = view.currentPage,
                              let document = view.document,
                              let pageIndex = (0..<document.pageCount).first(where: {
                                  document.page(at: $0) === page
                              }) else { return }
                        self.onPageChanged(pageIndex)
                    }
                }
            }
            pageChangedObservers = observers.map(ObserverToken.init)
        }

        deinit {
            for observer in pageChangedObservers {
                NotificationCenter.default.removeObserver(observer.value)
            }
        }
    }

    private final class ObserverToken: @unchecked Sendable {
        let value: NSObjectProtocol

        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }
}

extension PDFKitPreviewView.Coordinator: PDFViewDelegate {
    nonisolated func pdfView(_ sender: PDFView, willClickOnLink url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "file"].contains(scheme) else {
            return
        }
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func pdfViewPerformPrint(_ sender: PDFView) {
        // Do not let an embedded PDF action open the system print flow.
    }

    nonisolated func pdfViewPerformFind(_ sender: PDFView) {
        // Search is controlled by the app's own find bar.
    }

    nonisolated func pdfViewPerformGo(toPage sender: PDFView) {
        // Page navigation is controlled by the app and the outline sidebar.
    }

    nonisolated func pdfView(
        _ sender: PDFView,
        openPDF url: URL,
        forRemoteGoToAction action: PDFActionRemoteGoTo
    ) {
        // Remote go-to actions must never open another document silently.
    }
}

final class FittingPDFView: PDFView {
    struct ReadingPosition {
        let pageIndex: Int
        let point: CGPoint?
    }

    var zoom = 1.0
    var loadedPDFData: Data?
    var isRestoringPosition = false
    private var activeFindQuery = ""
    private var lastFindRequestID = 0
    private var findMatches: [PDFSelection] = []
    private var currentFindIndex = 0
    private var restoreGeneration = 0

    override func layout() {
        super.layout()
        fitPageWidth()
    }

    func fitPageWidth(force: Bool = false) {
        guard let page = document?.page(at: 0) else { return }

        let pageBounds = page.bounds(for: displayBox)
        let availableWidth = bounds.width - 32
        guard pageBounds.width > 0, availableWidth > 0 else { return }

        let targetScale = max((availableWidth / pageBounds.width) * zoom, 0.1)
        guard force || abs(scaleFactor - targetScale) > 0.001 else { return }

        scaleFactor = targetScale
    }

    func goToPage(at index: Int) {
        guard let document, document.pageCount > 0 else { return }
        let safeIndex = min(max(index, 0), document.pageCount - 1)
        guard let page = document.page(at: safeIndex), currentPage !== page else { return }
        go(to: page)
    }

    func readingPosition(fallbackPageIndex: Int) -> ReadingPosition {
        guard let document,
              let currentPage,
              let pageIndex = (0..<document.pageCount).first(where: {
                  document.page(at: $0) === currentPage
              }) else {
            return ReadingPosition(pageIndex: fallbackPageIndex, point: nil)
        }

        return ReadingPosition(
            pageIndex: pageIndex,
            point: currentDestination?.point
        )
    }

    func scheduleRestore(of position: ReadingPosition, onRestored: @escaping (Int) -> Void) {
        restoreGeneration += 1
        let generation = restoreGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.layoutDocumentView()
            guard let document, document.pageCount > 0 else {
                self.isRestoringPosition = false
                return
            }
            let safeIndex = min(max(position.pageIndex, 0), document.pageCount - 1)
            guard let page = document.page(at: safeIndex) else {
                self.isRestoringPosition = false
                return
            }
            if let point = position.point {
                go(to: PDFDestination(page: page, at: point))
            } else {
                go(to: page)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.restoreGeneration == generation else { return }
                self.isRestoringPosition = false
                onRestored(safeIndex)
            }
        }
    }

    func updateFind(query: String, requestID: Int, backwards: Bool, force: Bool = false) {
        guard force || query != activeFindQuery || requestID != lastFindRequestID else { return }

        let queryChanged = query != activeFindQuery
        activeFindQuery = query
        lastFindRequestID = requestID

        guard let document, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            findMatches = []
            highlightedSelections = []
            currentSelection = nil
            return
        }

        if force || queryChanged {
            findMatches = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            currentFindIndex = backwards ? max(findMatches.count - 1, 0) : 0
        } else if !findMatches.isEmpty {
            let step = backwards ? -1 : 1
            currentFindIndex = (currentFindIndex + step + findMatches.count) % findMatches.count
        }

        highlightedSelections = findMatches
        guard !findMatches.isEmpty else {
            currentSelection = nil
            return
        }

        let selection = findMatches[currentFindIndex]
        setCurrentSelection(selection, animate: true)
        scrollSelectionToVisible(selection)
    }
}
