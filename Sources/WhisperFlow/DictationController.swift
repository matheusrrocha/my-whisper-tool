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
        didSet { onStateChange?(state) }
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

    func toggle() {
        switch state {
        case .idle: startRecording()
        case .recording: finishRecording()
        case .transcribing: break
        }
    }

    func startRecording() {
        guard state == .idle else { return }
        guard engine.state == .ready else {
            playError()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        default:
            onError?("Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            try recorder.start()
            play(startSound)
            state = .recording
        } catch {
            playError()
            onError?(error.localizedDescription)
        }
    }

    func finishRecording() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        play(stopSound)

        let duration = Double(samples.count) / 16000.0
        guard duration >= minimumDuration else {
            state = .idle
            return
        }

        state = .transcribing
        let language = Settings.shared.language
        Task {
            do {
                let text = try await engine.transcribe(samples: samples, language: language)
                if !text.isEmpty {
                    inserter.insert(text)
                }
            } catch {
                playError()
                onError?(error.localizedDescription)
            }
            state = .idle
        }
    }

    /// Discards the current recording without transcribing.
    func cancelRecording() {
        guard state == .recording else { return }
        _ = recorder.stop()
        state = .idle
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
