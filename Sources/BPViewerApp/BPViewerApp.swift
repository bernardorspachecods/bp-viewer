import AppKit
import SwiftUI

@main
@MainActor
struct BPViewerApp: App {
    @NSApplicationDelegateAdaptor(BPViewerAppDelegate.self) private var appDelegate
    @StateObject private var windowManager: WorkspaceWindowManager
    @StateObject private var model: AppModel

    init() {
        let windowManager = WorkspaceWindowManager.shared
        _windowManager = StateObject(wrappedValue: windowManager)
        let model = AppModel(workspaceSession: windowManager.session)
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        Window("bp-viewer", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Markdown File") {
                    windowManager.modelForActiveWindow(fallback: model)?.createNewMarkdownDocument()
                }
                    .keyboardShortcut("t", modifiers: [.command])

                Button("New Workspace…") {
                    windowManager.chooseAndOpenWorkspace(
                        from: windowManager.modelForActiveWindow(fallback: model)
                    )
                }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Open Folder…") {
                    windowManager.chooseAndOpenWorkspace(
                        from: windowManager.modelForActiveWindow(fallback: model)
                    )
                }
                    .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("Refresh Preview") {
                    windowManager.modelForActiveWindow(fallback: model)?.refreshActiveTab()
                }
                    .keyboardShortcut("r", modifiers: [.command])

                    Button("Find in Document") {
                        windowManager.modelForActiveWindow(fallback: model)?.showFindBar()
                    }
                    .keyboardShortcut("f", modifiers: [.command])

                Button("Zoom In") {
                    windowManager.modelForActiveWindow(fallback: model)?.zoomIn()
                }
                    .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom Out") {
                    windowManager.modelForActiveWindow(fallback: model)?.zoomOut()
                }
                    .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Zoom") {
                    windowManager.modelForActiveWindow(fallback: model)?.resetPreviewZoom()
                }
                    .keyboardShortcut("0", modifiers: [.command])

                Button("Toggle Sidebar") {
                    guard let activeModel = windowManager.modelForActiveWindow(fallback: model) else { return }
                    activeModel.setSidebarVisible(!activeModel.sidebarVisible)
                }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                Button("Toggle Theme") {
                    windowManager.modelForActiveWindow(fallback: model)?.cycleTheme()
                }
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .windowArrangement) {
                Button("Close Tab") {
                    windowManager.modelForActiveWindow(fallback: model)?.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Tabs") {
                    Button("Next Tab") {
                        windowManager.modelForActiveWindow(fallback: model)?.selectNextTab()
                    }
                    .keyboardShortcut(.tab, modifiers: [.control])

                ForEach(Array((windowManager.activeModel ?? model).tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                    Button("\(index + 1): \(tab.title)") {
                        windowManager.modelForActiveWindow(fallback: model)?.selectTab(number: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(windowManager.activeModel ?? model)
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
