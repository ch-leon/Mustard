#if os(macOS)
import SwiftUI

/// The floating push-to-talk pill (F25 v1): live transcript while the hotkey is
/// held, then a brief committed/cancelled flash. Renders `VoiceCaptureController`
/// state only — every decision lives in the pure `VoiceCapture`.
public struct VoiceCapturePillView: View {
    private let controller: VoiceCaptureController
    @State private var pulsing = false

    public init(controller: VoiceCaptureController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 10) {
            icon
            text
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 380, alignment: .leading)
        .background(Theme.Palette.bg, in: Capsule())
        .overlay(Capsule().stroke(Theme.Palette.divider, lineWidth: 1))
        .elevation(.float, cornerRadius: 28)
        .padding(8)
        .animation(Theme.Motion.settle, value: controller.phase)
    }

    @ViewBuilder private var icon: some View {
        switch controller.phase {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.Palette.accent)
                .scaleEffect(pulsing ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
                .onDisappear { pulsing = false }
        case .committed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.done)
        case .cancelled:
            Image(systemName: "mic.slash").foregroundStyle(Theme.Palette.textTertiary)
        case .denied, .unavailable:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.warning)
        case .idle:
            Image(systemName: "mic").foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    @ViewBuilder private var text: some View {
        switch controller.phase {
        case .recording:
            Text(controller.liveTranscript.isEmpty ? "Listening…" : controller.liveTranscript)
                .font(Theme.Fonts.body)
                .foregroundStyle(controller.liveTranscript.isEmpty
                                 ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                .lineLimit(2)
        case .committed(let title):
            Text("Added — \(title)")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
        case .cancelled:
            Text("Nothing captured")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textTertiary)
        case .denied:
            Text("Allow the microphone and speech recognition in System Settings → Privacy")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(2)
        case .unavailable(let reason):
            Text(reason)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(2)
        case .idle:
            Text("")
        }
    }
}
#endif
