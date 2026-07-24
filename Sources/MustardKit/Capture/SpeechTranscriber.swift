import Foundation

/// Seam between the capture controller and the speech stack, so the controller
/// can be exercised without a microphone. The live implementation is
/// `SpeechTranscriber` below (macOS only).
@MainActor
public protocol SpeechTranscribing: AnyObject {
    /// Streamed partial transcripts while recording (drives the live pill).
    var onPartial: ((String) -> Void)? { get set }
    /// Ask for speech + microphone permission. True when both granted.
    func requestAuthorization() async -> Bool
    /// Begin listening. Throws if the audio engine can't start.
    func start() throws
    /// Stop listening and return the best final transcript (falls back to the
    /// last partial if the recognizer doesn't finalize promptly).
    func stop() async -> String
    /// Abandon the recording, discarding any transcript.
    func cancel()
}

#if os(macOS)
import Speech
import AVFoundation

/// On-device push-to-talk transcription (F25 v1, ADR-0011): `SFSpeechRecognizer`
/// fed by an `AVAudioEngine` mic tap. `requiresOnDeviceRecognition` is set
/// whenever the recognizer supports it, so audio never leaves the Mac.
@MainActor
public final class SpeechTranscriber: SpeechTranscribing {
    public var onPartial: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finished = false
    private var finishContinuation: CheckedContinuation<String, Never>?

    public init() {}

    public func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "SpeechTranscriber", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable."])
        }
        latest = ""
        finished = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true   // audio stays local (ADR-0011)
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Recognizer callbacks arrive on an arbitrary queue — hop home.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    self.onPartial?(self.latest)
                    if result.isFinal { self.finish() }
                }
                if error != nil { self.finish() }
            }
        }
    }

    public func stop() async -> String {
        stopAudio()
        request?.endAudio()
        if finished { return latest }
        // Wait briefly for the recognizer to finalize; the last partial is a fine
        // fallback — release-to-task must never hang on recognition.
        return await withCheckedContinuation { cont in
            finishContinuation = cont
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.finish()
            }
        }
    }

    public func cancel() {
        stopAudio()
        task?.cancel()
        latest = ""
        finish()
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Idempotent: resolves a pending `stop()` and marks the session done so late
    /// recognizer callbacks (or the timeout task) can't double-resume.
    private func finish() {
        finished = true
        task = nil
        request = nil
        finishContinuation?.resume(returning: latest)
        finishContinuation = nil
    }
}
#endif
