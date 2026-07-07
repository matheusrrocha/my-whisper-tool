import Foundation
import WhisperKit

/// Owns the WhisperKit instance: downloads the model on first use,
/// loads it, and runs transcription.
@MainActor
final class TranscriptionEngine {
    enum State: Equatable {
        case unloaded
        case downloading(Double)  // 0...1
        case loading
        case ready
        case failed(String)

        var menuDescription: String {
            switch self {
            case .unloaded: return "Model not loaded"
            case .downloading(let p): return "Downloading model… \(Int(p * 100))%"
            case .loading: return "Loading model…"
            case .ready: return "Ready"
            case .failed(let message): return "Error: \(message)"
            }
        }
    }

    private(set) var state: State = .unloaded {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?

    private var whisperKit: WhisperKit?
    private var loadTask: Task<Void, Never>?

    private var modelsFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("WhisperFlow", isDirectory: true)
    }

    func load(variant: String) {
        loadTask?.cancel()
        whisperKit = nil
        state = .downloading(0)
        loadTask = Task {
            do {
                Log.engine.notice("downloading/verifying model \(variant, privacy: .public)")
                let folder = try await WhisperKit.download(
                    variant: variant,
                    downloadBase: modelsFolder,
                    useBackgroundSession: false
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(progress.fractionCompleted)
                    }
                }
                guard !Task.isCancelled else { return }
                Log.engine.notice("model on disk at \(folder.path, privacy: .public), loading")
                self.state = .loading
                let config = WhisperKitConfig(
                    modelFolder: folder.path,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true,
                    download: false
                )
                let kit = try await WhisperKit(config)
                guard !Task.isCancelled else { return }
                self.whisperKit = kit
                self.state = .ready
                Log.engine.notice("model ready")
            } catch {
                guard !Task.isCancelled else { return }
                Log.engine.error("model load failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Transcribes 16 kHz mono samples. Returns cleaned-up text ("" if silence).
    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let whisperKit else {
            throw NSError(domain: "WhisperFlow", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Model is not loaded yet.",
            ])
        }
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.detectLanguage = (language == nil)
        options.temperature = 0
        options.chunkingStrategy = .vad

        Log.engine.notice("transcribe start: \(samples.count, privacy: .public) samples, language \(language ?? "auto", privacy: .public)")
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        Log.engine.notice("transcribe done: \(results.count, privacy: .public) result(s)")
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = Self.clean(text)
        if Settings.shared.plainFormatting {
            cleaned = Self.applyPlainFormatting(cleaned)
        }
        return cleaned
    }

    /// Dictation-friendly output: lowercase start, no auto-appended trailing
    /// period. Saying "period" (or "full stop" / "ponto final") still ends
    /// the text with ". ".
    nonisolated static func applyPlainFormatting(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        let spokenPeriod = #"(?i)[\s,]*\b(period|full stop|ponto final)\s*[.!?]?\s*$"#
        if let range = result.range(of: spokenPeriod, options: .regularExpression) {
            result.replaceSubrange(range, with: ". ")
        } else if result.hasSuffix(".") && !result.hasSuffix("..") {
            result.removeLast()
        }

        if let first = result.first, first.isUppercase {
            result = first.lowercased() + result.dropFirst()
        }
        return result
    }

    /// Strips Whisper artifacts like "[BLANK_AUDIO]" or "(music)" that show up on silence.
    nonisolated static func clean(_ text: String) -> String {
        var result = text
        for pattern in ["\\[[^\\]]*\\]", "\\([^)]*\\)"] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
