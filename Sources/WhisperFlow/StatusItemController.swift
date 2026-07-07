import AppKit
import AVFoundation
import ServiceManagement

/// Menu bar icon: a ringed waveform "voice button" when idle, live waveform
/// bars while recording (driven by mic level), pulsing wave while
/// transcribing. Also owns the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let dictation: DictationController

    /// Set by AppDelegate; opens the shortcut-capture panel.
    var onCaptureRequested: (() -> Void)?

    private var animationTimer: Timer?
    private var levelHistory: [Float] = Array(repeating: 0, count: 5)
    private var animationPhase: Double = 0

    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
    private let hotkeyRootItem = NSMenuItem(title: "Hold Key", action: nil, keyEquivalent: "")
    private let inputDeviceRootItem = NSMenuItem(title: "Input Device", action: nil, keyEquivalent: "")
    private let languageRootItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    private let modelRootItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
    private let micPermItem = NSMenuItem(title: "Microphone", action: #selector(openMicrophoneSettings), keyEquivalent: "")
    private let axPermItem = NSMenuItem(title: "Accessibility", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let soundsItem = NSMenuItem(title: "Sound Feedback", action: #selector(toggleSounds), keyEquivalent: "")
    private let clipboardItem = NSMenuItem(title: "Restore Clipboard After Paste", action: #selector(toggleRestoreClipboard), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    init(dictation: DictationController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.dictation = dictation
        super.init()

        statusItem.button?.image = Self.idleIcon()
        refreshTooltip()
        buildMenu()

        dictation.onStateChange = { [weak self] state in
            self?.dictationStateChanged(state)
        }
        dictation.engine.onStateChange = { [weak self] _ in
            self?.refreshStatusLine()
        }
    }

    func refreshTooltip() {
        statusItem.button?.toolTip = "WhisperFlow — hold \(Settings.shared.binding.display) to dictate"
    }

    // MARK: - Dictation state → icon

    private func dictationStateChanged(_ state: DictationController.State) {
        animationTimer?.invalidate()
        animationTimer = nil

        switch state {
        case .idle:
            statusItem.button?.image = Self.idleIcon()
        case .recording, .transcribing:
            levelHistory = Array(repeating: 0, count: 5)
            animationPhase = 0
            let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickAnimation() }
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
            tickAnimation()
        }
        refreshStatusLine()
    }

    private func tickAnimation() {
        switch dictation.state {
        case .recording:
            levelHistory.removeFirst()
            levelHistory.append(dictation.recorder.level)
            statusItem.button?.image = Self.barsIcon(levels: levelHistory)
        case .transcribing:
            animationPhase += 0.35
            let levels = (0..<5).map { i in
                Float(0.5 + 0.45 * sin(animationPhase + Double(i) * 0.9))
            }
            statusItem.button?.image = Self.barsIcon(levels: levels)
        case .idle:
            break
        }
    }

    // MARK: - Icon drawing

    /// Idle: a ring enclosing a small static waveform — WhisperFlow's "voice
    /// button". Distinct from the bare animated bars shown while active.
    private static func idleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()

            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 1.5
            ring.stroke()

            let heights: [CGFloat] = [4.0, 7.5, 5.5]
            let barWidth: CGFloat = 1.8
            let gap: CGFloat = 1.5
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            var x = (rect.width - totalWidth) / 2
            for height in heights {
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: (rect.height - height) / 2, width: barWidth, height: height),
                    xRadius: 0.9, yRadius: 0.9
                )
                bar.fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func barsIcon(levels: [Float]) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let barWidth: CGFloat = 2.0
            let gap: CGFloat = 1.5
            let totalWidth = CGFloat(levels.count) * barWidth + CGFloat(levels.count - 1) * gap
            var x = (rect.width - totalWidth) / 2
            for level in levels {
                let height = max(3, CGFloat(level) * (rect.height - 2))
                let y = (rect.height - height) / 2
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: barWidth, height: height),
                    xRadius: 1, yRadius: 1
                )
                bar.fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        // Hold-key binding submenu: presets + free-form recorder.
        let hotkeyMenu = NSMenu()
        for (index, preset) in KeyBinding.presets.enumerated() {
            let item = NSMenuItem(title: preset.display, action: #selector(selectPresetHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            hotkeyMenu.addItem(item)
        }
        hotkeyMenu.addItem(.separator())
        let recordItem = NSMenuItem(title: "Press New Shortcut…", action: #selector(captureShortcut), keyEquivalent: "")
        recordItem.target = self
        hotkeyMenu.addItem(recordItem)
        hotkeyRootItem.submenu = hotkeyMenu
        menu.addItem(hotkeyRootItem)

        // Input device submenu is rebuilt on every menu open.
        inputDeviceRootItem.submenu = NSMenu()
        menu.addItem(inputDeviceRootItem)

        // Language submenu
        let languageMenu = NSMenu()
        for choice in LanguageChoice.all {
            let item = NSMenuItem(title: choice.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.code ?? "auto"
            languageMenu.addItem(item)
        }
        languageRootItem.submenu = languageMenu
        menu.addItem(languageRootItem)

        // Model submenu
        let modelMenu = NSMenu()
        for choice in ModelChoice.all {
            let item = NSMenuItem(title: choice.title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.variant
            modelMenu.addItem(item)
        }
        modelRootItem.submenu = modelMenu
        menu.addItem(modelRootItem)

        menu.addItem(.separator())

        // Permissions submenu — live status, click to open System Settings.
        let permissionsMenu = NSMenu()
        micPermItem.target = self
        axPermItem.target = self
        permissionsMenu.addItem(micPermItem)
        permissionsMenu.addItem(axPermItem)
        let permissionsRoot = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        permissionsRoot.submenu = permissionsMenu
        menu.addItem(permissionsRoot)

        menu.addItem(.separator())

        soundsItem.target = self
        menu.addItem(soundsItem)
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit WhisperFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshStatusLine()

        switch dictation.state {
        case .idle:
            toggleMenuItem.title = "Start Dictation"
            toggleMenuItem.isEnabled = dictation.engine.state == .ready
        case .recording:
            toggleMenuItem.title = "Stop & Insert"
            toggleMenuItem.isEnabled = true
        case .transcribing:
            toggleMenuItem.title = "Transcribing…"
            toggleMenuItem.isEnabled = false
        }

        let settings = Settings.shared

        hotkeyRootItem.title = "Hold Key: \(settings.binding.display)"
        for item in hotkeyRootItem.submenu?.items ?? [] where item.action == #selector(selectPresetHotkey(_:)) {
            item.state = KeyBinding.presets.indices.contains(item.tag) && settings.binding == KeyBinding.presets[item.tag] ? .on : .off
        }

        rebuildInputDeviceMenu()

        for item in languageRootItem.submenu?.items ?? [] {
            item.state = (item.representedObject as? String) == (settings.language ?? "auto") ? .on : .off
        }
        for item in modelRootItem.submenu?.items ?? [] {
            item.state = (item.representedObject as? String) == settings.modelVariant ? .on : .off
        }

        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        micPermItem.title = micGranted ? "Microphone: Granted ✓" : "Microphone: Not Granted — Open Settings…"
        let axGranted = AXIsProcessTrusted()
        axPermItem.title = axGranted ? "Accessibility: Granted ✓" : "Accessibility: Not Granted — Open Settings…"

        soundsItem.state = settings.soundsEnabled ? .on : .off
        clipboardItem.state = settings.restoreClipboard ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func rebuildInputDeviceMenu() {
        guard let submenu = inputDeviceRootItem.submenu else { return }
        submenu.removeAllItems()
        let selectedUID = Settings.shared.inputDeviceUID

        let defaultItem = NSMenuItem(title: "System Default", action: #selector(selectInputDevice(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.state = selectedUID == nil ? .on : .off
        submenu.addItem(defaultItem)
        submenu.addItem(.separator())

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        var selectedFound = false
        for device in discovery.devices {
            let item = NSMenuItem(title: device.localizedName, action: #selector(selectInputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if device.uniqueID == selectedUID {
                item.state = .on
                selectedFound = true
            }
            submenu.addItem(item)
        }

        // Selected device currently disconnected: show it so it can be deselected.
        if let selectedUID, !selectedFound {
            let item = NSMenuItem(title: "Saved device (disconnected)", action: #selector(selectInputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = selectedUID
            item.state = .on
            submenu.addItem(item)
        }
    }

    private func refreshStatusLine() {
        switch dictation.state {
        case .recording:
            statusMenuItem.title = "● Recording… (release to insert)"
        case .transcribing:
            statusMenuItem.title = "Transcribing…"
        case .idle:
            statusMenuItem.title = dictation.engine.state.menuDescription
        }
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        dictation.toggle()
    }

    @objc private func selectPresetHotkey(_ sender: NSMenuItem) {
        guard KeyBinding.presets.indices.contains(sender.tag) else { return }
        Settings.shared.binding = KeyBinding.presets[sender.tag]
        refreshTooltip()
    }

    @objc private func captureShortcut() {
        onCaptureRequested?()
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        Settings.shared.inputDeviceUID = sender.representedObject as? String
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        Settings.shared.language = raw == "auto" ? nil : raw
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let variant = sender.representedObject as? String else { return }
        guard variant != Settings.shared.modelVariant else { return }
        Settings.shared.modelVariant = variant
        dictation.engine.load(variant: variant)
    }

    @objc private func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    @objc private func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleSounds() {
        Settings.shared.soundsEnabled.toggle()
    }

    @objc private func toggleRestoreClipboard() {
        Settings.shared.restoreClipboard.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
    }
}
