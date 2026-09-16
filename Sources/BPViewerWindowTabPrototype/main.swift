// PROTOTYPE — throwaway AppKit spike for macOS window tabs.
// This target tests NSWindowTab/NSWindowTabGroup and is not production code.

import AppKit

@MainActor
final class WindowTabPrototypeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        let titles = ["README", "AGENTS", "chapter-methods", "references"]
        let firstWindow = makeWindow(title: titles[0])
        windows = [firstWindow]

        firstWindow.makeKeyAndOrderFront(nil)

        for title in titles.dropFirst() {
            let window = makeWindow(title: title)
            windows.append(window)
            firstWindow.addTabbedWindow(window, ordered: .above)
        }

        firstWindow.tab.title = titles[0]
        firstWindow.tabGroup?.selectedWindow = firstWindow

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        firstWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
        if windows.isEmpty {
            NSApp.terminate(nil)
        }
    }

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "bp-viewer-window-tab-prototype"
        window.delegate = self
        window.center()
        window.contentView = WindowTabContentView(title: title)
        window.tab.accessoryView = TabCloseButton(window: window)
        return window
    }
}

@MainActor
final class TabCloseButton: NSButton {
    weak var windowToClose: NSWindow?

    init(window: NSWindow) {
        windowToClose = window
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .texturedRounded
        toolTip = "Close Tab"
        target = self
        action = #selector(closeTab)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func closeTab() {
        windowToClose?.performClose(nil)
    }
}

@MainActor
final class WindowTabContentView: NSView {
    init(title: String) {
        super.init(frame: .zero)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 30, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let description = NSTextField(labelWithString: "NSWindowTab / NSWindowTabGroup — try dragging, reordering, and detaching this tab into a new window.")
        description.textColor = .secondaryLabelColor
        description.lineBreakMode = .byWordWrapping
        description.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Also try ⌃Tab, closing tabs, and the window's native tab menu.")
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        addSubview(heading)
        addSubview(description)
        addSubview(hint)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            description.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            description.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            description.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            hint.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            hint.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@main
@MainActor
struct BPViewerWindowTabPrototype {
    static func main() {
        let app = NSApplication.shared
        let delegate = WindowTabPrototypeDelegate()
        app.delegate = delegate
        app.run()
    }
}
