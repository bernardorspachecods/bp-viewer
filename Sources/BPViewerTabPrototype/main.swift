// PROTOTYPE — throwaway AppKit spike for comparing native macOS tab surfaces.
// This target does not share production state or UI and should not be used by
// the application itself.

import AppKit

@MainActor
final class TabPrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: TabPrototypeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = TabPrototypeWindowController()
        windowController = controller
        controller.showWindow(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class TabPrototypeWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "bp-viewer — Native tab prototype"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = TabPrototypeViewController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class TabPrototypeViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let title = NSTextField(labelWithString: "Native macOS tab surfaces")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let instructions = NSTextField(labelWithString: "Experimenta clicar, arrastar e reordenar as tabs. Compara diretamente com o Terminal.")
        instructions.textColor = .secondaryLabelColor
        instructions.lineBreakMode = .byWordWrapping

        let classicLabel = candidateLabel("A — NSTabView top tabs")
        let classicTabs = makeClassicTabView()

        let segmentedLabel = candidateLabel("B — NSTabViewController segmented tabs")
        let segmentedController = makeSegmentedTabController()

        let stack = NSStackView(views: [
            title,
            instructions,
            classicLabel,
            classicTabs,
            segmentedLabel,
            segmentedController.view
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            classicTabs.heightAnchor.constraint(equalToConstant: 220),
            segmentedController.view.heightAnchor.constraint(equalToConstant: 220),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            classicLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            segmentedLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            classicTabs.widthAnchor.constraint(equalTo: stack.widthAnchor),
            segmentedController.view.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func candidateLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeClassicTabView() -> NSTabView {
        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        addItems(to: tabView)
        return tabView
    }

    private func makeSegmentedTabController() -> NSTabViewController {
        let controller = NSTabViewController()
        controller.tabStyle = .segmentedControlOnTop

        for title in sampleTitles {
            let child = NSViewController()
            let content = SampleContentView(title: title)
            child.view = content
            child.title = title
            controller.addChild(child)
        }

        return controller
    }

    private func addItems(to tabView: NSTabView) {
        for title in sampleTitles {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = SampleContentView(title: title)
            tabView.addTabViewItem(item)
        }
    }

    private var sampleTitles: [String] {
        ["README", "AGENTS", "chapter-methods", "references"]
    }
}

@MainActor
final class SampleContentView: NSView {
    init(title: String) {
        super.init(frame: .zero)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 28, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "Conteúdo fictício para testar seleção, largura, drag-and-drop e animação.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(heading)
        addSubview(subtitle)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@main
@MainActor
struct BPViewerTabPrototype {
    static func main() {
        let app = NSApplication.shared
        let delegate = TabPrototypeAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
