import AppKit
import SwiftUI

@main
struct BPViewerApp: App {
    @NSApplicationDelegateAdaptor(BPViewerAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("bp-viewer") {
            RootView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir pasta…", action: model.openFolder)
                    .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Visualização") {
                Button("Atualizar preview", action: model.refreshActiveTab)
                    .keyboardShortcut("r", modifiers: [.command])

                Button("Pesquisar no preview", action: model.showFindBar)
                    .keyboardShortcut("f", modifiers: [.command])

                Button("Aumentar zoom", action: model.zoomIn)
                    .keyboardShortcut("+", modifiers: [.command])

                Button("Diminuir zoom", action: model.zoomOut)
                    .keyboardShortcut("-", modifiers: [.command])

                Button("Repor zoom", action: model.resetPreviewZoom)
                    .keyboardShortcut("0", modifiers: [.command])

                Button("Alternar sidebar", action: { model.setSidebarVisible(!model.sidebarVisible) })
                    .keyboardShortcut("b", modifiers: [.command, .option])

                Button("Alternar tema", action: model.cycleTheme)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }

            CommandGroup(after: .windowArrangement) {
                Button("Fechar tab", action: {
                    if let activeTab = model.activeTab { model.closeTab(activeTab) }
                })
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Tabs") {
                ForEach(Array(model.tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                    Button("\(index + 1): \(tab.title)") {
                        model.selectTab(number: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }
    }
}

final class BPViewerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
