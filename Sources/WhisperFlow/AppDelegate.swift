import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dictation = DictationController()
    private let hotkey = HotkeyMonitor()
    private let shortcutCapture = ShortcutCapture()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusController = StatusItemController(dictation: dictation)
        self.statusController = statusController

        statusController.onCaptureRequested = { [weak self] in
            self?.beginShortcutCapture()
        }

        dictation.onError = { message in
            Self.showAlert(title: "WhisperFlow", message: message)
        }

        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.dictation.startRecording() }
        }
        hotkey.onRelease = { [weak self] in
            Task { @MainActor in self?.dictation.finishRecording() }
        }
        hotkey.onTypingWhileHeld = { [weak self] in
            // The user is typing a shortcut/accent with the modifier held —
            // this wasn't a dictation, discard it.
            Task { @MainActor in self?.dictation.cancelRecording() }
        }
        hotkey.start()

        requestPermissionsIfNeeded()
        dictation.engine.load(variant: Settings.shared.modelVariant)
    }

    private func beginShortcutCapture() {
        hotkey.isPaused = true
        shortcutCapture.begin { [weak self] binding in
            if let binding {
                Settings.shared.binding = binding
            }
            self?.hotkey.isPaused = false
            self?.statusController?.refreshTooltip()
        }
    }

    private func requestPermissionsIfNeeded() {
        // Microphone: prompt up front so first dictation isn't lost.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        // Accessibility: needed for the global hotkey and for pasting (Cmd+V).
        // The hotkey monitor retries on its own once permission is granted.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
