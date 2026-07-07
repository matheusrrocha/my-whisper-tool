import AppKit

/// A hold-to-talk binding: either a lone modifier key (Right ⌥, Fn, …) held
/// down, or a regular key (F13, ⌃⌥Space, …) held with optional modifiers.
struct KeyBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifiersRaw: UInt
    var isModifierOnly: Bool
    var display: String

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiersRaw) }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isModifierOnly: Bool, display: String) {
        self.keyCode = keyCode
        self.modifiersRaw = modifiers.rawValue
        self.isModifierOnly = isModifierOnly
        self.display = display
    }

    static let rightOption = KeyBinding(keyCode: 61, modifiers: .option, isModifierOnly: true, display: "Right Option (⌥)")
    static let rightCommand = KeyBinding(keyCode: 54, modifiers: .command, isModifierOnly: true, display: "Right Command (⌘)")
    static let fnKey = KeyBinding(keyCode: 63, modifiers: .function, isModifierOnly: true, display: "Fn / Globe 🌐")
    static let presets: [KeyBinding] = [.rightOption, .rightCommand, .fnKey]

    /// Maps a modifier key's keyCode to its NSEvent flag.
    static func modifierFlag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    static func modifierName(forKeyCode keyCode: UInt16) -> String? {
        switch keyCode {
        case 54: return "Right Command (⌘)"
        case 55: return "Left Command (⌘)"
        case 56: return "Left Shift (⇧)"
        case 58: return "Left Option (⌥)"
        case 59: return "Left Control (⌃)"
        case 60: return "Right Shift (⇧)"
        case 61: return "Right Option (⌥)"
        case 62: return "Right Control (⌃)"
        case 63: return "Fn / Globe 🌐"
        default: return nil
        }
    }
}

struct ModelChoice {
    let variant: String
    let title: String

    static let all: [ModelChoice] = [
        ModelChoice(variant: "openai_whisper-base", title: "Fast (base, ~150 MB)"),
        ModelChoice(variant: "openai_whisper-small", title: "Balanced (small, ~500 MB)"),
        ModelChoice(variant: "openai_whisper-large-v3-v20240930_turbo_632MB", title: "Accurate compressed (turbo, ~630 MB)"),
        ModelChoice(variant: "openai_whisper-large-v3-v20240930_turbo", title: "Most accurate (large-v3-turbo, ~1.6 GB)"),
    ]
}

struct LanguageChoice {
    let code: String?  // nil = auto-detect
    let title: String

    static let all: [LanguageChoice] = [
        LanguageChoice(code: nil, title: "Auto-detect"),
        LanguageChoice(code: "en", title: "English"),
        LanguageChoice(code: "pt", title: "Português"),
        LanguageChoice(code: "es", title: "Español"),
        LanguageChoice(code: "fr", title: "Français"),
        LanguageChoice(code: "de", title: "Deutsch"),
    ]
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private var cachedBinding: KeyBinding?

    /// The hold-to-talk key binding. Read on every keyboard event, so cached.
    var binding: KeyBinding {
        get {
            if let cachedBinding { return cachedBinding }
            let decoded = defaults.data(forKey: "keyBinding").flatMap {
                try? JSONDecoder().decode(KeyBinding.self, from: $0)
            }
            let binding = decoded ?? .rightOption
            cachedBinding = binding
            return binding
        }
        set {
            cachedBinding = newValue
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "keyBinding")
        }
    }

    var modelVariant: String {
        get { defaults.string(forKey: "modelVariant") ?? "openai_whisper-large-v3-v20240930_turbo" }
        set { defaults.set(newValue, forKey: "modelVariant") }
    }

    /// Whisper language code, or nil for auto-detect.
    var language: String? {
        get {
            let value = defaults.string(forKey: "language") ?? "auto"
            return value == "auto" ? nil : value
        }
        set { defaults.set(newValue ?? "auto", forKey: "language") }
    }

    /// AVCaptureDevice uniqueID of the preferred input device; nil = system default.
    var inputDeviceUID: String? {
        get { defaults.string(forKey: "inputDeviceUID") }
        set { defaults.set(newValue, forKey: "inputDeviceUID") }
    }

    /// Lowercase the first letter and drop the trailing auto-period; a spoken
    /// "period" still ends the text with ". ".
    var plainFormatting: Bool {
        get { defaults.object(forKey: "plainFormatting") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "plainFormatting") }
    }

    var soundsEnabled: Bool {
        get { defaults.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundsEnabled") }
    }

    var restoreClipboard: Bool {
        get { defaults.object(forKey: "restoreClipboard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "restoreClipboard") }
    }
}
