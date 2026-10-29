import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

private let codexReplyHotKeySignature = OSType(0x42505652) // BPVR

/// Where a captured reply opens: `⇧⌘E` uses a separate Viewer window, `⌥⌘E`
/// adds a tab to the workspace window in use.
private enum ReplyDestination: UInt32, CaseIterable {
    case independentWindow = 1
    case currentWorkspace = 2

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .independentWindow: [.command, .shift]
        case .currentWorkspace: [.command, .option]
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .independentWindow: UInt32(cmdKey | shiftKey)
        case .currentWorkspace: UInt32(cmdKey | optionKey)
        }
    }

    var label: String {
        switch self {
        case .independentWindow: "⇧⌘E"
        case .currentWorkspace: "⌥⌘E"
        }
    }
}

private enum ReplyCaptureClient: Equatable {
    case codex
    case claudeCode

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    var folderName: String {
        switch self {
        case .codex: "Codex Responses"
        case .claudeCode: "Claude Code Responses"
        }
    }

    var fileBaseName: String {
        switch self {
        case .codex: "Codex Reply"
        case .claudeCode: "Claude Code Reply"
        }
    }
}

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

    private var hotKeys: [EventHotKeyRef] = []
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
                      let destination = ReplyDestination(rawValue: pressedHotKey.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<CodexReplyCaptureController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.handleShortcutPress(destination)
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

        for destination in ReplyDestination.allCases {
            let identifier = EventHotKeyID(
                signature: codexReplyHotKeySignature,
                id: destination.rawValue
            )
            var hotKey: EventHotKeyRef?
            let registrationStatus = RegisterEventHotKey(
                UInt32(kVK_ANSI_E),
                destination.carbonModifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            if registrationStatus == noErr, let hotKey {
                hotKeys.append(hotKey)
            } else {
                NSLog("BP Viewer could not register %@: %d", destination.label, registrationStatus)
            }
        }

        // Carbon hotkeys can fail to register when another app has claimed the
        // same combination. Keep a global event monitor as a fallback.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard event.keyCode == UInt16(kVK_ANSI_E),
                  let destination = ReplyDestination.allCases.first(where: { $0.modifiers == flags }) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleShortcutPress(destination)
            }
        }
    }

    func unregisterGlobalShortcut() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func handleShortcutPress(_ destination: ReplyDestination) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShortcutHandledAt > 0.4 else { return }
        lastShortcutHandledAt = now
        captureLatestReply(destination: destination)
    }

    func captureLatestReply() {
        captureLatestReply(destination: .independentWindow)
    }

    private func captureLatestReply(destination: ReplyDestination) {
        guard !isCapturing else { return }
        guard let terminal = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = terminal.bundleIdentifier,
              Self.terminalBundleIdentifiers.contains(bundleIdentifier) else {
            showAlert(
                title: "Open Codex or Claude Code in a Terminal",
                message: "Focus the terminal running Codex or Claude Code CLI, then press ⇧⌘E (new window) or ⌥⌘E (current workspace)."
            )
            return
        }

        guard requestAccessibilityPermissionIfNeeded() else { return }
        let client = captureClient(for: terminal.processIdentifier)
        let originalClipboardChangeCount = NSPasteboard.general.changeCount
        let didSendCopyCommand = client == .claudeCode
            ? sendClaudeCopyCommand()
            : sendCodexCopyShortcut()
        guard didSendCopyCommand else {
            showAlert(
                title: "Couldn’t Copy the \(client.displayName) Reply",
                message: "BP Viewer could not request the \(client.displayName) reply. Check its Accessibility permission in System Settings and try again."
            )
            return
        }

        isCapturing = true
        let terminalProcessID = terminal.processIdentifier
        Task { @MainActor [weak self] in
            var didSelectClaudeCopyOption = false
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == terminalProcessID else {
                    self.isCapturing = false
                    return
                }

                if client == .claudeCode,
                   !didSelectClaudeCopyOption,
                   self.isClaudeCopyPickerVisible(in: terminalProcessID) {
                    didSelectClaudeCopyOption = self.sendReturnKey()
                }

                let clipboard = NSPasteboard.general
                guard clipboard.changeCount != originalClipboardChangeCount,
                      let response = clipboard.string(forType: .string),
                      !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                self.isCapturing = false
                self.openResponseInViewer(response, from: client, destination: destination)
                return
            }

            guard let self else { return }
            self.isCapturing = false
            let message = client == .claudeCode
                ? "If Claude Code opened its copy picker, select a response there. Otherwise make sure it is focused and has a completed reply, then try again."
                : "Make sure Codex CLI is focused and has a completed reply, then try again."
            self.showAlert(
                title: "No \(client.displayName) Reply Was Copied",
                message: message
            )
        }
    }

    private func captureClient(for processIdentifier: pid_t) -> ReplyCaptureClient {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success, let focusedWindow else { return .codex }

        let window = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        let title = accessibilityString(window, kAXTitleAttribute as CFString)?.lowercased() ?? ""
        if title.contains("‹ claude") || title.contains("claude --") {
            return .claudeCode
        }

        if let text = accessibilityText(in: window),
           text.components(separatedBy: "\n").contains(where: {
               $0.trimmingCharacters(in: .whitespaces).first == "❯"
           }) {
            return .claudeCode
        }
        return .codex
    }

    private func accessibilityString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func accessibilityText(in element: AXUIElement) -> String? {
        if accessibilityString(element, kAXRoleAttribute as CFString) == kAXTextAreaRole,
           let value = accessibilityString(element, kAXValueAttribute as CFString) {
            return value
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] else { return nil }

        for child in children {
            if let value = accessibilityText(in: child) { return value }
        }
        return nil
    }

    private func isClaudeCopyPickerVisible(in processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success, let focusedWindow else { return false }

        let window = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        guard let text = accessibilityText(in: window),
              let promptRange = text.range(of: "Select content to copy:", options: .caseInsensitive) else {
            return false
        }

        let pickerText = text[promptRange.lowerBound...]
        return pickerText.range(of: "Full response", options: .caseInsensitive) != nil
            && pickerText.range(of: "Enter to copy", options: .caseInsensitive) != nil
    }

    private func sendReturnKey() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Return),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Return),
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = []
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func sendClaudeCopyCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let textKeyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_Slash),
                keyDown: true
              ),
              let textKeyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_Slash),
                keyDown: false
              ),
              let returnKeyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Return),
                keyDown: true
              ),
              let returnKeyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Return),
                keyDown: false
              ) else {
            return false
        }

        // Override held shortcut modifiers and keyboard layout for /copy.
        textKeyDown.flags = []
        textKeyUp.flags = []
        let commandCharacters = Array("/copy".utf16)
        commandCharacters.withUnsafeBufferPointer { characters in
            textKeyDown.keyboardSetUnicodeString(
                stringLength: characters.count,
                unicodeString: characters.baseAddress
            )
        }
        textKeyDown.post(tap: .cghidEventTap)
        textKeyUp.post(tap: .cghidEventTap)

        // Give the slash-command menu time to recognize the command.
        Thread.sleep(forTimeInterval: 0.15)
        returnKeyDown.flags = []
        returnKeyUp.flags = []
        returnKeyDown.post(tap: .cghidEventTap)
        returnKeyUp.post(tap: .cghidEventTap)
        return true
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

    private func openResponseInViewer(
        _ response: String,
        from client: ReplyCaptureClient,
        destination: ReplyDestination
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let model = WorkspaceWindowManager.shared.presentForCapturedReply(
                inIndependentWindow: destination == .independentWindow
            ) else {
                showAlert(
                    title: "BP Viewer Has No Active Workspace",
                    message: "BP Viewer could not restore its window. Open the app and try the shortcut again."
                )
                return
            }
            do {
                let destinationURL = try nextSavedReplyURL(for: client)
                guard await model.createSavedMarkdownDocument(source: response, at: destinationURL) else {
                    showAlert(
                        title: "Couldn’t Save the \(client.displayName) Reply",
                        message: "The response remains open in an unsaved tab. Check that BP Viewer can write to Downloads/\(client.folderName)."
                    )
                    return
                }
            } catch {
                showAlert(
                    title: "Couldn’t Save the \(client.displayName) Reply",
                    message: "BP Viewer couldn’t find your Downloads folder. The response remains open in an unsaved tab."
                )
            }
        }
    }

    private func nextSavedReplyURL(for client: ReplyCaptureClient) throws -> URL {
        guard let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let responsesURL = downloadsURL.appendingPathComponent(client.folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )

        var index = 1
        while true {
            let name = index == 1 ? "\(client.fileBaseName).md" : "\(client.fileBaseName) \(index).md"
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
