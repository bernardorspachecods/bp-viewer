import Darwin
import Foundation

struct ActiveDocumentChange: Sendable {
    let tabID: String
    let url: URL
}

/// Watches the active document and its preview dependencies. It owns only
/// filesystem observation and debouncing; the app decides how to reconcile a
/// change with editing and rendering state.
@MainActor
final class ActiveDocumentWatcher {
    private let onChange: (ActiveDocumentChange) -> Void
    private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var watchedURLs: Set<URL> = []
    private var watchedTabID: String?
    private var refreshGeneration = 0

    init(onChange: @escaping (ActiveDocumentChange) -> Void) {
        self.onChange = onChange
    }

    func start(tabID: String, urls: [URL]) {
        let normalizedURLs = Set(urls.map(\.standardizedFileURL))
        guard watchedTabID != tabID || watchedURLs != normalizedURLs else { return }

        stop()
        watchedTabID = tabID
        for url in normalizedURLs {
            let descriptor = Darwin.open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.scheduleChange(for: url)
            }
            source.setCancelHandler {
                Darwin.close(descriptor)
            }
            watchers[url] = source
            watchedURLs.insert(url)
            source.resume()
        }
    }

    func stop() {
        watchers.values.forEach { $0.cancel() }
        watchers.removeAll()
        watchedURLs.removeAll()
        watchedTabID = nil
        refreshGeneration += 1
    }

    private func scheduleChange(for url: URL) {
        guard watchedURLs.contains(url), let watchedTabID else { return }

        refreshGeneration += 1
        let generation = refreshGeneration
        let tabID = watchedTabID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self,
                  self.refreshGeneration == generation,
                  self.watchedTabID == tabID,
                  self.watchedURLs.contains(url) else { return }
            self.onChange(ActiveDocumentChange(tabID: tabID, url: url))
        }
    }
}
