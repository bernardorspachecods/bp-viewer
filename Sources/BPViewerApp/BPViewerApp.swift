import AppKit
import SwiftUI

@main
@MainActor
struct BPViewerApp: App {
    @NSApplicationDelegateAdaptor(BPViewerAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup("bp-viewer") {
            RootView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Markdown File", action: model.createNewMarkdownDocument)
                    .keyboardShortcut("t", modifiers: [.command])

                Button("Open Folder…", action: model.openFolder)
                    .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("Refresh Preview", action: model.refreshActiveTab)
                    .keyboardShortcut("r", modifiers: [.command])

                    Button("Find in Document", action: model.showFindBar)
                    .keyboardShortcut("f", modifiers: [.command])

                Button("Zoom In", action: model.zoomIn)
                    .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom Out", action: model.zoomOut)
                    .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Zoom", action: model.resetPreviewZoom)
                    .keyboardShortcut("0", modifiers: [.command])

                Button("Toggle Sidebar", action: { model.setSidebarVisible(!model.sidebarVisible) })
                    .keyboardShortcut("b", modifiers: [.command, .option])

                Button("Toggle Theme", action: model.cycleTheme)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .windowArrangement) {
                Button("Close Tab", action: model.closeActiveTab)
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Tabs") {
                    Button("Next Tab", action: model.selectNextTab)
                    .keyboardShortcut(.tab, modifiers: [.control])

                ForEach(Array(model.tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                    Button("\(index + 1): \(tab.title)") {
                        model.selectTab(number: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class BPViewerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.post(name: .bpViewerOpenFiles, object: urls)
        application.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .bpViewerOpenFiles, object: urls)
    }
}
