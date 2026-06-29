import Foundation

/// Board view preferences, persisted in UserDefaults. Maps the design prototype's
/// three props: defaultView, density (compact), showConfidence.
public struct BoardSettings {
    private let store: UserDefaults
    public init(store: UserDefaults = .standard) { self.store = store }

    public var defaultView: BoardOwnerView {
        get { BoardOwnerView(rawValue: store.string(forKey: "board.defaultView") ?? "") ?? .everyone }
        set { store.set(newValue.rawValue, forKey: "board.defaultView") }
    }

    public var compact: Bool {
        get { store.bool(forKey: "board.compact") }
        set { store.set(newValue, forKey: "board.compact") }
    }

    public var showConfidence: Bool {
        get { store.object(forKey: "board.showConfidence") as? Bool ?? true }
        set { store.set(newValue, forKey: "board.showConfidence") }
    }
}
