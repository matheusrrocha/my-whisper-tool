import Testing
import AppKit
@testable import WhisperFlow

@Suite struct KeyBindingTests {
    @Test func codableRoundTrip() throws {
        let binding = KeyBinding(keyCode: 105, modifiers: [.command, .shift], isModifierOnly: false, display: "⇧⌘F13")
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)
        #expect(decoded == binding)
        #expect(decoded.modifiers == [.command, .shift])
    }

    @Test func modifierFlagMap() {
        #expect(KeyBinding.modifierFlag(forKeyCode: 61) == .option)
        #expect(KeyBinding.modifierFlag(forKeyCode: 54) == .command)
        #expect(KeyBinding.modifierFlag(forKeyCode: 63) == .function)
        #expect(KeyBinding.modifierFlag(forKeyCode: 0) == nil)
    }

    @Test func presetsAreModifierOnlyAndMapped() {
        for preset in KeyBinding.presets {
            #expect(preset.isModifierOnly, "\(preset.display) should be modifier-only")
            #expect(KeyBinding.modifierFlag(forKeyCode: preset.keyCode) != nil)
            #expect(KeyBinding.modifierName(forKeyCode: preset.keyCode) != nil)
        }
    }
}

@Suite struct TranscriptCleaningTests {
    @Test func stripsWhisperArtifacts() {
        #expect(TranscriptionEngine.clean("[BLANK_AUDIO]") == "")
        #expect(TranscriptionEngine.clean("Hello world. (music)") == "Hello world.")
        #expect(TranscriptionEngine.clean("  Olá, tudo bem?  ") == "Olá, tudo bem?")
    }

    @Test func plainFormattingLowercasesAndStripsTrailingPeriod() {
        #expect(TranscriptionEngine.applyPlainFormatting("Hello world.") == "hello world")
        #expect(TranscriptionEngine.applyPlainFormatting("Testing one two three") == "testing one two three")
        // Internal punctuation is kept; only the trailing period is dropped.
        #expect(TranscriptionEngine.applyPlainFormatting("Já entendi. Vamos lá.") == "já entendi. Vamos lá")
        // Ellipses and other terminal punctuation are untouched.
        #expect(TranscriptionEngine.applyPlainFormatting("Wait...") == "wait...")
        #expect(TranscriptionEngine.applyPlainFormatting("Really?") == "really?")
    }

    @Test func spokenPeriodEndsWithDotSpace() {
        #expect(TranscriptionEngine.applyPlainFormatting("Hello world period") == "hello world. ")
        #expect(TranscriptionEngine.applyPlainFormatting("Hello world, period.") == "hello world. ")
        #expect(TranscriptionEngine.applyPlainFormatting("Send the report full stop") == "send the report. ")
        #expect(TranscriptionEngine.applyPlainFormatting("Até amanhã ponto final") == "até amanhã. ")
    }
}

@Suite struct HotkeyFlagTests {
    @Test func cgFlagMapping() {
        let flags = HotkeyMonitor.cgFlags(for: [.command, .option])
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskAlternate))
        #expect(!flags.contains(.maskControl))
        #expect(!flags.contains(.maskShift))
    }
}
