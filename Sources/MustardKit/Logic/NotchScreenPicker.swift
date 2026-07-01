import Foundation

/// Lightweight, testable stand-in for `NSScreen` so screen-selection policy
/// can be unit tested without a live display list.
public struct NotchScreenDescriptor: Equatable {
    public let id: AnyHashable
    public let hasNotch: Bool
    public let isMain: Bool

    public init(id: AnyHashable, hasNotch: Bool, isMain: Bool) {
        self.id = id
        self.hasNotch = hasNotch
        self.isMain = isMain
    }
}

/// Decides which screen the notch panel renders on: prefer a connected
/// external (non-notch) display over the built-in notch screen, so the
/// panel follows the monitor actually in use instead of staying stuck on
/// the laptop's physical notch whenever the lid is open.
public enum NotchScreenPicker {
    public static func choose(from screens: [NotchScreenDescriptor]) -> NotchScreenDescriptor? {
        if screens.count > 1, let external = screens.first(where: { !$0.hasNotch }) {
            return external
        }
        if let notch = screens.first(where: { $0.hasNotch }) {
            return notch
        }
        if let main = screens.first(where: { $0.isMain }) {
            return main
        }
        return screens.first
    }
}
