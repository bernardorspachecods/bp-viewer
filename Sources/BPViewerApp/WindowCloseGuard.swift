import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView(frame: .zero)
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            guard let window else { return }
            MainActor.assumeIsolated {
                coordinator?.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        guard let window = nsView.window else { return }
        context.coordinator.attach(to: window)
    }

    final class WindowAttachmentView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var model: AppModel?
        private weak var window: NSWindow?

        init(model: AppModel) {
            self.model = model
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            model?.attach(to: window)
            WorkspaceWindowManager.shared.register(model: model, window: window)
            window.delegate = self
        }

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            WorkspaceWindowManager.shared.unregister(window: window)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model?.shouldCloseWindow(sender) ?? true
        }
    }
}
