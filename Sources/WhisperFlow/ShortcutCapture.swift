import AppKit

/// Small panel that records the next key press (or lone modifier press +
/// release) as the new hold-to-talk binding.
@MainActor
final class ShortcutCapture: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    private var hintLabel: NSTextField?
    private var pendingModifierKeyCode: UInt16?
    private var completion: ((KeyBinding?) -> Void)?

    func begin(completion: @escaping (KeyBinding?) -> Void) {
        guard panel == nil else { return }
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Hold Key"
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let title = NSTextField(labelWithString: "Press the key or combination you want to hold to dictate.")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString:
            "A lone modifier key (e.g. Right ⌥) is captured when you release it.\nEsc cancels.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hintLabel = hint

        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = stack

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil  // consume everything while capturing
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            if event.keyCode == 53 && modifiers.isEmpty {  // Esc
                finish(nil)
                return
            }
            if modifiers.subtracting(.function).isEmpty && !Self.isNonTypingKey(event) {
                hintLabel?.stringValue = "\"\(Self.keyName(for: event))\" would interfere with normal typing.\nCombine it with ⌘ ⌥ ⌃ ⇧, or use an F-key."
                hintLabel?.textColor = .systemOrange
                return
            }
            var stored = modifiers
            if Self.isNonTypingKey(event) {
                stored.remove(.function)  // F-keys set the fn flag implicitly
            }
            let display = Self.displayString(keyCode: event.keyCode, modifiers: stored, event: event)
            finish(KeyBinding(keyCode: event.keyCode, modifiers: stored, isModifierOnly: false, display: display))

        case .flagsChanged:
            guard let flag = KeyBinding.modifierFlag(forKeyCode: event.keyCode) else { return }
            if event.modifierFlags.contains(flag) {
                pendingModifierKeyCode = event.keyCode
            } else if pendingModifierKeyCode == event.keyCode {
                let name = KeyBinding.modifierName(forKeyCode: event.keyCode) ?? "Modifier"
                finish(KeyBinding(keyCode: event.keyCode, modifiers: flag, isModifierOnly: true, display: name))
            } else {
                pendingModifierKeyCode = nil
            }

        default:
            break
        }
    }

    private func finish(_ binding: KeyBinding?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let done = completion
        completion = nil
        if let panel {
            self.panel = nil
            panel.delegate = nil
            panel.close()
        }
        hintLabel = nil
        pendingModifierKeyCode = nil
        done?(binding)
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    /// Function keys, arrows, etc. produce characters in the Unicode
    /// function-key range and are safe to bind without modifiers.
    private static func isNonTypingKey(_ event: NSEvent) -> Bool {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return true }
        return (0xF700...0xF8FF).contains(scalar.value)
    }

    static func displayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var result = ""
        if modifiers.contains(.function) { result += "fn " }
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyName(for: event)
        return result
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 76: "Enter",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func keyName(for event: NSEvent) -> String {
        if let name = specialKeyNames[event.keyCode] { return name }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}
