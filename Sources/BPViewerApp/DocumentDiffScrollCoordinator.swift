import AppKit

/// Keeps the two source surfaces in a diff on the same vertical coordinate.
/// DocumentDiffLayout gives both editors matching row heights; sharing the
/// scroll position therefore keeps corresponding rows aligned while either
/// side is being scrolled.
@MainActor
final class DocumentDiffScrollCoordinator {
    enum Side {
        case reference
        case edited
    }

    private weak var referenceScrollView: NSScrollView?
    private weak var editedScrollView: NSScrollView?
    private var referenceObserver: NSObjectProtocol?
    private var editedObserver: NSObjectProtocol?
    private var isSynchronizing = false

    func register(_ scrollView: NSScrollView, as side: Side) {
        switch side {
        case .reference:
            guard referenceScrollView !== scrollView else { return }
            removeObserver(referenceObserver)
            referenceScrollView = scrollView
            referenceObserver = observer(for: scrollView)
        case .edited:
            guard editedScrollView !== scrollView else { return }
            removeObserver(editedObserver)
            editedScrollView = scrollView
            editedObserver = observer(for: scrollView)
        }

        synchronizeIfPossible()
    }

    func reset() {
        removeObserver(referenceObserver)
        removeObserver(editedObserver)
        referenceObserver = nil
        editedObserver = nil
        referenceScrollView = nil
        editedScrollView = nil
    }

    private func observer(for scrollView: NSScrollView) -> NSObjectProtocol {
        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        return NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            MainActor.assumeIsolated {
                guard let self, let scrollView else { return }
                self.scrollViewDidScroll(scrollView)
            }
        }
    }

    private func scrollViewDidScroll(_ source: NSScrollView) {
        guard !isSynchronizing else { return }

        let target: NSScrollView?
        if source === referenceScrollView {
            target = editedScrollView
        } else if source === editedScrollView {
            target = referenceScrollView
        } else {
            target = nil
        }
        guard let target else { return }

        synchronize(source: source, target: target)
    }

    private func synchronizeIfPossible() {
        guard let referenceScrollView,
              let editedScrollView else { return }
        synchronize(source: referenceScrollView, target: editedScrollView)
    }

    private func synchronize(source: NSScrollView, target: NSScrollView) {
        let sourceY = source.contentView.bounds.origin.y
        var targetBounds = target.contentView.bounds
        targetBounds.origin.y = sourceY
        let constrainedBounds = target.contentView.constrainBoundsRect(targetBounds)
        guard abs(constrainedBounds.origin.y - target.contentView.bounds.origin.y) > 0.1 else {
            return
        }

        isSynchronizing = true
        target.contentView.setBoundsOrigin(constrainedBounds.origin)
        target.reflectScrolledClipView(target.contentView)
        isSynchronizing = false
    }

    private func removeObserver(_ observer: NSObjectProtocol?) {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
    }
}
