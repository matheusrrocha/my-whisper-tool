import AppKit
import CoreGraphics

/// Watches the configured hold-to-talk binding system-wide using a CGEvent tap.
/// The tap needs Accessibility; if it isn't granted yet, we retry every few
/// seconds so the hotkey starts working as soon as permission is given.
///
/// For non-modifier bindings (F13, ⌃⌥Space, …) the bound key events are
/// swallowed so holding them doesn't type into the focused app. Lone-modifier
/// bindings pass through untouched — a held modifier types nothing by itself.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Fired when another key is typed while the hotkey is held
    /// (e.g. Option+e for accents) — the dictation should cancel.
    var onTypingWhileHeld: (() -> Void)?

    /// Set while the shortcut-capture panel is open.
    var isPaused = false

    private(set) var isHeld = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var healthTimer: Timer?

    func start() {
        if !createTap() {
            Log.hotkey.notice("event tap unavailable (Accessibility not granted yet) — retrying every 2.5s")
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.createTap() {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
        }
        // Taps can be silently disabled (e.g. after a slow callback); revive them.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                Log.hotkey.error("event tap found disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    private func createTap() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.notice("event tap created")
        return true
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // macOS disables taps that stall; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.hotkey.error("event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public) — re-enabling")
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passthrough
        }
        if isPaused { return passthrough }

        return swallow(type: type, event: event) ? nil : passthrough
    }

    /// Core matching logic. Returns true if the event should be swallowed.
    private func swallow(type: CGEventType, event: CGEvent) -> Bool {
        let binding = Settings.shared.binding
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let required = Self.cgFlags(for: binding.modifiers)

        switch type {
        case .flagsChanged:
            if binding.isModifierOnly {
                guard keyCode == binding.keyCode else { return false }
                let pressed = event.flags.contains(required)
                if pressed && !isHeld {
                    isHeld = true
                    Log.hotkey.notice("hold key pressed")
                    onPress?()
                } else if !pressed && isHeld {
                    isHeld = false
                    Log.hotkey.notice("hold key released")
                    onRelease?()
                }
            } else if isHeld && !event.flags.contains(required) {
                // A required modifier was released before the key itself.
                isHeld = false
                onRelease?()
            }
            return false

        case .keyDown:
            if !binding.isModifierOnly && keyCode == binding.keyCode {
                if isHeld {
                    return true  // swallow key repeats
                }
                if event.flags.contains(required) {
                    isHeld = true
                    onPress?()
                    return true
                }
                return false
            }
            if isHeld {
                onTypingWhileHeld?()
            }
            return false

        case .keyUp:
            if !binding.isModifierOnly && keyCode == binding.keyCode && isHeld {
                isHeld = false
                onRelease?()
                return true
            }
            return false

        default:
            return false
        }
    }

    static func cgFlags(for modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
