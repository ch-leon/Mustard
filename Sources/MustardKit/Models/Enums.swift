import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case inbox, planned, inProgress, done, someday
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .done: "Done"
        case .someday: "Someday"
        }
    }

    public var isOpen: Bool { self != .done && self != .someday }
}

public enum TaskOwner: String, Codable, CaseIterable, Identifiable {
    case me, agent
    public var id: String { rawValue }
    public var label: String { self == .me ? "Me" : "Agent" }
}
