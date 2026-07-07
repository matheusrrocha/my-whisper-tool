import AVFoundation
import AudioToolbox
import CoreAudio

/// Records from the selected input device (or system default), converting to
/// 16 kHz mono Float32 (what Whisper expects) and exposing a smoothed input
/// level for UI feedback.
///
/// A fresh AVAudioEngine is built for every recording: assigning an input
/// device to an already-initialized engine silently stops it from rendering,
/// and the tap format must be derived from the hardware sample rate of the
/// device actually in use.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    private let lock = NSLock()
    private var buffer: [Float] = []
    private var _level: Float = 0

    var isRecording: Bool { engine != nil }

    /// Smoothed input level in 0...1, safe to read from any thread.
    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return _level
    }

    var durationSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(buffer.count) / 16000.0
    }

    func start() throws {
        guard engine == nil else { return }
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        _level = 0
        lock.unlock()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let uid = Settings.shared.inputDeviceUID {
            if let deviceID = Self.audioDeviceID(forUID: uid) {
                assignInputDevice(deviceID, to: input)
            } else {
                Log.audio.error("selected input device \(uid, privacy: .public) not found — using system default")
            }
        }

        // After a device switch the node's output format can be stale; trust
        // the hardware sample rate and rebuild the tap format from it.
        let hardwareRate = input.inputFormat(forBus: 0).sampleRate
        let outputFormat = input.outputFormat(forBus: 0)
        guard hardwareRate > 0, outputFormat.channelCount > 0 else {
            throw NSError(domain: "WhisperFlow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No audio input device available.",
            ])
        }
        guard let nodeFormat = AVAudioFormat(
            commonFormat: outputFormat.commonFormat,
            sampleRate: hardwareRate,
            channels: outputFormat.channelCount,
            interleaved: outputFormat.isInterleaved
        ) else {
            throw NSError(domain: "WhisperFlow", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not derive input format.",
            ])
        }
        guard let converter = AVAudioConverter(from: nodeFormat, to: targetFormat) else {
            throw NSError(domain: "WhisperFlow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create audio converter.",
            ])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: nodeFormat) { [weak self] pcmBuffer, _ in
            self?.process(pcmBuffer, converter: converter)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        Log.audio.notice("recording started (rate \(hardwareRate, privacy: .public) Hz, \(outputFormat.channelCount, privacy: .public) ch)")
    }

    /// Stops recording and returns the captured 16 kHz mono samples.
    func stop() -> [Float] {
        guard let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        lock.lock(); defer { lock.unlock() }
        let samples = buffer
        buffer = []
        _level = 0
        return samples
    }

    // MARK: - Input device selection

    private func assignInputDevice(_ deviceID: AudioDeviceID, to input: AVAudioInputNode) {
        guard let audioUnit = input.audioUnit else {
            Log.audio.error("cannot select input device: input node has no audio unit")
            return
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            Log.audio.notice("input device assigned (id \(deviceID, privacy: .public))")
        } else {
            Log.audio.error("could not select input device (OSStatus \(status, privacy: .public))")
        }
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var uidCF = uid as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &uidCF) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func process(_ pcmBuffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Input level from the raw buffer (before resampling).
        if let channel = pcmBuffer.floatChannelData?[0] {
            let frames = Int(pcmBuffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames { sum += channel[i] * channel[i] }
            let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
            // Map RMS to a perceptual-ish 0...1 range (-50 dB floor).
            let db = 20 * log10(max(rms, 1e-7))
            let normalized = max(0, min(1, (db + 50) / 50))
            lock.lock()
            _level = _level * 0.6 + normalized * 0.4
            lock.unlock()
        }

        // Resample to 16 kHz mono.
        let ratio = targetFormat.sampleRate / pcmBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }

        let frames = Int(out.frameLength)
        lock.lock()
        buffer.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
        // Safety cap: 10 minutes of audio.
        if buffer.count > 16000 * 600 {
            buffer.removeFirst(buffer.count - 16000 * 600)
        }
        lock.unlock()
    }
}
