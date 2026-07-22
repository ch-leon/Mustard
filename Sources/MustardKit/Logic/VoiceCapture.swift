import Foundation

/// Pure press-to-talk capture decisions (F25 v1, ADR-0011): whether a hotkey
/// release commits a task, and how a spoken transcript becomes a task title.
/// The impure edges (Carbon hotkey, SFSpeech) live in `Capture/` and only call
/// through here, so every decision stays unit-tested.
public enum VoiceCapture {
    /// Holds shorter than this cancel — swallows accidental hotkey taps.
    public static let minimumHold: TimeInterval = 0.3

    public enum CancelReason: Equatable {
        case tooShort
        case emptyTranscript
    }

    public enum Outcome: Equatable {
        case commit(title: String)
        case cancelled(CancelReason)
    }

    /// Decide what a hotkey release does. Too-short holds cancel first (a tap is a
    /// tap regardless of what the recognizer produced); then an empty transcript
    /// cancels; otherwise commit with the normalized title.
    public static func outcome(pressedAt: Date, releasedAt: Date, transcript: String) -> Outcome {
        // 1ms tolerance: Date stores seconds as a Double, so an interval built to be
        // exactly `minimumHold` can compare a hair under it. Imperceptible for UX.
        guard releasedAt.timeIntervalSince(pressedAt) >= minimumHold - 0.001 else {
            return .cancelled(.tooShort)
        }
        let title = normalizeTitle(transcript)
        guard !title.isEmpty else { return .cancelled(.emptyTranscript) }
        return .commit(title: title)
    }

    /// Transcript → title: trim, collapse whitespace runs (incl. newlines) to single
    /// spaces, drop one trailing full stop (SFSpeech punctuates most utterances with
    /// "." — noise in a title; "?"/"!" are kept), and capitalize the first letter.
    public static func normalizeTitle(_ transcript: String) -> String {
        var text = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.hasSuffix(".") && !text.hasSuffix("..") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
