import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        context.coordinator.attach(to: window)
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
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model?.shouldCloseWindow(sender) ?? true
        }
    }
}
