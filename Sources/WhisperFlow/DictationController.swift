import AppKit
import AVFoundation

/// The state machine tying hotkey → recording → transcription → insertion.
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    private(set) var state: State = .idle {
        didSet {
            if oldValue != state {
                Log.app.notice("state: \(String(describing: oldValue), privacy: .public) → \(String(describing: self.state), privacy: .public)")
            }
            onStateChange?(state)
        }
    }
    var onStateChange: ((State) -> Void)?
    var onError: ((String) -> Void)?

    let recorder = AudioRecorder()
    let engine = TranscriptionEngine()
    private let inserter = TextInserter()

    private let startSound = NSSound(named: "Pop")
    private let stopSound = NSSound(named: "Tink")
    private let errorSound = NSSound(named: "Basso")

    /// Minimum recording length to bother transcribing (accidental taps).
    private let minimumDuration = 0.35
    /// If transcription hasn't finished after this long, reset to idle.
    private let transcribeTimeout: TimeInterval = 90
    /// Invalidates in-flight transcriptions after a watchdog reset.
    private var generation = 0

    func toggle() {
        switch state {
        case .idle: startRecording()
        case .recording: finishRecording()
        case .transcribing: break
        }
    }

    func startRecording() {
        guard state == .idle else {
            Log.app.notice("startRecording ignored: state is \(String(describing: self.state), privacy: .public)")
            return
        }
        guard engine.state == .ready else {
            Log.app.error("startRecording refused: engine is \(self.engine.state.menuDescription, privacy: .public)")
            playError()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            Log.app.notice("requesting microphone permission")
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        default:
            Log.app.error("microphone permission denied")
            reportError("Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            try recorder.start()
            play(startSound)
            state = .recording
        } catch {
            Log.app.error("recorder failed to start: \(error.localizedDescription, privacy: .public)")
            playError()
            reportError(error.localizedDescription)
        }
    }

    func finishRecording() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        play(stopSound)

        let duration = Double(samples.count) / 16000.0
        Log.app.notice("recording finished: \(String(format: "%.2f", duration), privacy: .public)s (\(samples.count, privacy: .public) samples)")
        guard !samples.isEmpty else {
            // The engine ran but no audio arrived — almost always a stale
            // Microphone permission (e.g. granted to a differently-signed build).
            Log.app.error("no audio captured — microphone permission is likely stale")
            state = .idle
            playError()
            reportError("""
            The microphone delivered no audio.

            Re-grant microphone access: System Settings → Privacy & Security → \
            Microphone → toggle WhisperFlow off and on, then try again. \
            Also check the selected Input Device in the menu.
            """)
            return
        }
        guard duration >= minimumDuration else {
            Log.app.notice("discarded: shorter than \(self.minimumDuration)s")
            state = .idle
            return
        }

        state = .transcribing
        generation += 1
        let currentGeneration = generation
        let language = Settings.shared.language

        // Watchdog: never leave the state machine stuck in .transcribing.
        DispatchQueue.main.asyncAfter(deadline: .now() + transcribeTimeout) { [weak self] in
            guard let self, self.state == .transcribing, self.generation == currentGeneration else { return }
            Log.app.error("transcription watchdog fired after \(self.transcribeTimeout)s — resetting to idle")
            self.generation += 1
            self.state = .idle
            self.playError()
            self.reportError("Transcription timed out and was cancelled.")
        }

        Task {
            do {
                let started = Date()
                let text = try await engine.transcribe(samples: samples, language: language)
                let elapsed = Date().timeIntervalSince(started)
                guard self.generation == currentGeneration else {
                    Log.app.error("transcription finished after watchdog reset — dropping result")
                    return
                }
                Log.app.notice("transcribed \(text.count, privacy: .public) chars in \(String(format: "%.2f", elapsed), privacy: .public)s")
                state = .idle
                if !text.isEmpty {
                    inserter.insert(text)
                } else {
                    Log.app.notice("empty transcript — nothing to insert")
                }
            } catch {
                Log.app.error("transcription failed: \(error.localizedDescription, privacy: .public)")
                guard self.generation == currentGeneration else { return }
                state = .idle
                playError()
                reportError(error.localizedDescription)
            }
        }
    }

    /// Discards the current recording without transcribing.
    func cancelRecording() {
        guard state == .recording else { return }
        _ = recorder.stop()
        Log.app.notice("recording cancelled")
        state = .idle
    }

    /// Reports an error without ever blocking the state machine.
    private func reportError(_ message: String) {
        let handler = onError
        Task { @MainActor in
            handler?(message)
        }
    }

    private func play(_ sound: NSSound?) {
        guard Settings.shared.soundsEnabled, let sound else { return }
        sound.stop()
        sound.volume = 0.35
        sound.play()
    }

    private func playError() {
        play(errorSound)
    }
}
