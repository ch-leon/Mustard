#if os(macOS)
import AppKit
import SwiftUI
import SwiftData
import Observation

/// Orchestrates push-to-talk capture (F25 v1, ADR-0011): global hotkey press →
/// record with a live-transcript pill → release → `VoiceCapture.outcome` decides →
/// commit inserts an Inbox task (`source = "voice"`, `captureState = .raw`) for
/// the cleanup queue. All decisions live in the pure `VoiceCapture`; this class
/// only sequences the mic, the panel, and the insert.
@MainActor
@Observable
public final class VoiceCaptureController {
    public enum Phase: Equatable {
        case idle
        case recording
        case committed(String)   // flashed briefly: "Added — <title>"
        case cancelled           // too short / nothing heard
        case denied              // mic or speech permission missing
        case unavailable(String) // recognizer/engine failure
    }

    public private(set) var phase: Phase = .idle
    public private(set) var liveTranscript = ""

    private let context: ModelContext
    private let transcriber: SpeechTranscribing
    private let hotKey: PushToTalkHotKey
    private var panel: NSPanel?
    private var pressedAt: Date?
    private var authorized = false
    private var dismissTask: Task<Void, Never>?

    public init(
        context: ModelContext,
        transcriber: SpeechTranscribing? = nil,
        hotKey: PushToTalkHotKey? = nil
    ) {
        self.context = context
        self.transcriber = transcriber ?? SpeechTranscriber()
        self.hotKey = hotKey ?? PushToTalkHotKey()
    }

    /// Claim the hotkey and pre-flight permissions (so the TCC prompts appear at
    /// launch, not mid-capture with the key held down).
    public func activate() {
        transcriber.onPartial = { [weak self] text in self?.liveTranscript = text }
        hotKey.onPress = { [weak self] in self?.beginCapture() }
        hotKey.onRelease = { [weak self] in self?.endCapture() }
        hotKey.register()
        Task { [weak self] in
            guard let self else { return }
            self.authorized = await self.transcriber.requestAuthorization()
        }
    }

    private func beginCapture() {
        guard phase != .recording else { return }   // key auto-repeat / re-entry
        dismissTask?.cancel()
        pressedAt = .now
        liveTranscript = ""
        guard authorized else {
            phase = .denied
            showPanel()
            scheduleDismiss(after: 2.5)
            return
        }
        do {
            try transcriber.start()
            phase = .recording
            showPanel()
        } catch {
            phase = .unavailable(error.localizedDescription)
            showPanel()
            scheduleDismiss(after: 2.5)
        }
    }

    private func endCapture() {
        guard phase == .recording, let pressedAt else { return }
        // Stamp the release BEFORE awaiting the recognizer — its finalization
        // latency must not count toward the minimum-hold gate.
        let releasedAt = Date.now
        self.pressedAt = nil
        if releasedAt.timeIntervalSince(pressedAt) < VoiceCapture.minimumHold {
            transcriber.cancel()   // an accidental tap: no transcript wanted
            phase = .cancelled
            scheduleDismiss(after: 0.8)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let transcript = await self.transcriber.stop()
            switch VoiceCapture.outcome(
                pressedAt: pressedAt, releasedAt: releasedAt, transcript: transcript
            ) {
            case .commit(let title):
                self.insertCapture(title: title, transcript: transcript)
                self.phase = .committed(title)
                self.scheduleDismiss(after: 1.6)
            case .cancelled:
                self.phase = .cancelled
                self.scheduleDismiss(after: 0.8)
            }
        }
    }

    private func insertCapture(title: String, transcript: String) {
        let task = MustardTask(title: title)
        task.source = "voice"
        task.sourceContext = "Voice capture"
        task.captureState = .raw
        task.captureTranscript = transcript
        context.insert(task)
        try? context.save()
    }

    // MARK: - Pill panel (HoverPanel pattern: non-activating, never steals focus)

    private func showPanel() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 56),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.contentView = NSHostingView(rootView: VoiceCapturePillView(controller: self))
            self.panel = panel
        }
        if let screen = NSScreen.main, let panel {
            // Top-centre, tucked under the notch/menu bar where the eye already is.
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - 8))
        }
        panel?.orderFrontRegardless()
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.phase = .idle
        }
    }
}
#endif
