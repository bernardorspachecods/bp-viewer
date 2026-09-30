import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

private let codexReplyHotKeySignature = OSType(0x42505652) // BPVR
private let codexReplyHotKeyID = UInt32(1)

@MainActor
final class CodexReplyCaptureController {
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "org.wezfurlong.wezterm",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable"
    ]

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var isCapturing = false
    private var didRequestAccessibilityPermission = false
    private var lastShortcutHandledAt: TimeInterval = 0

    func registerGlobalShortcut() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressedHotKey = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKey
                )
                guard parameterStatus == noErr,
                      pressedHotKey.signature == codexReplyHotKeySignature,
                      pressedHotKey.id == codexReplyHotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<CodexReplyCaptureController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.handleShortcutPress()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            NSLog("BP Viewer could not install its global Codex shortcut handler: %d", handlerStatus)
            return
        }

        let identifier = EventHotKeyID(signature: codexReplyHotKeySignature, id: codexReplyHotKeyID)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if registrationStatus != noErr {
            NSLog("BP Viewer could not register ⇧⌘E: %d", registrationStatus)
        }

        // Carbon hotkeys can fail to register when another app has claimed the
        // same combination. Keep a global event monitor as a fallback.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard event.keyCode == UInt16(kVK_ANSI_E), flags == [.command, .shift] else { return }
            Task { @MainActor [weak self] in
                self?.handleShortcutPress()
            }
        }
    }

    func unregisterGlobalShortcut() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func handleShortcutPress() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShortcutHandledAt > 0.4 else { return }
        lastShortcutHandledAt = now
        captureLatestReply()
    }

    func captureLatestReply() {
        guard !isCapturing else { return }
        guard let terminal = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = terminal.bundleIdentifier,
              Self.terminalBundleIdentifiers.contains(bundleIdentifier) else {
            showAlert(
                title: "Open Codex CLI in a Terminal",
                message: "Focus the terminal running Codex CLI, then press ⇧⌘E."
            )
            return
        }

        guard requestAccessibilityPermissionIfNeeded() else { return }
        let originalClipboardChangeCount = NSPasteboard.general.changeCount
        guard sendCodexCopyShortcut() else {
            showAlert(
                title: "Couldn’t Copy the Codex Reply",
                message: "BP Viewer could not send Codex’s Ctrl+O copy shortcut. Check its Accessibility permission in System Settings and try again."
            )
            return
        }

        isCapturing = true
        let terminalProcessID = terminal.processIdentifier
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == terminalProcessID else {
                    self.isCapturing = false
                    return
                }

                let clipboard = NSPasteboard.general
                guard clipboard.changeCount != originalClipboardChangeCount,
                      let response = clipboard.string(forType: .string),
                      !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                self.isCapturing = false
                self.openResponseInViewer(response)
                return
            }

            guard let self else { return }
            self.isCapturing = false
            self.showAlert(
                title: "No Codex Reply Was Copied",
                message: "Make sure Codex CLI is focused and has a completed reply, then try again."
            )
        }
    }

    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        guard !AXIsProcessTrusted() else { return true }

        // macOS displays its own Accessibility prompt each time this is called
        // with AXTrustedCheckOptionPrompt. A global shortcut can be pressed
        // repeatedly, so only ask once per app session.
        guard !didRequestAccessibilityPermission else {
            showAlert(
                title: "Restart Viewer to Apply Accessibility Access",
                message: "After enabling Viewer in System Settings → Privacy & Security → Accessibility, quit and reopen Viewer, then try ⇧⌘E again. macOS can keep the previous permission state for an app that is already running."
            )
            return false
        }
        didRequestAccessibilityPermission = true

        NSApp.activate(ignoringOtherApps: true)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return false
    }

    private func sendCodexCopyShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_O),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_O),
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func openResponseInViewer(_ response: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let model = WorkspaceWindowManager.shared.presentForCapturedReply() else {
                showAlert(
                    title: "BP Viewer Has No Active Workspace",
                    message: "BP Viewer could not restore its window. Open the app and try the shortcut again."
                )
                return
            }
            do {
                let destinationURL = try nextSavedReplyURL()
                guard await model.createSavedMarkdownDocument(source: response, at: destinationURL) else {
                    showAlert(
                        title: "Couldn’t Save the Codex Reply",
                        message: "The response remains open in an unsaved tab. Check that BP Viewer can write to Downloads/Codex Responses."
                    )
                    return
                }
            } catch {
                showAlert(
                    title: "Couldn’t Save the Codex Reply",
                    message: "BP Viewer couldn’t find your Downloads folder. The response remains open in an unsaved tab."
                )
            }
        }
    }

    private func nextSavedReplyURL() throws -> URL {
        guard let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let responsesURL = downloadsURL.appendingPathComponent("Codex Responses", isDirectory: true)
        try FileManager.default.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )

        var index = 1
        while true {
            let name = index == 1 ? "Codex Reply.md" : "Codex Reply \(index).md"
            let candidateURL = responsesURL.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: candidateURL.path) else {
                index += 1
                continue
            }
            return candidateURL
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
