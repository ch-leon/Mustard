import Foundation

public enum CommandKind: Equatable {
    case addTask(String)
    case goToday
    case goBoard
    case goAgent
    case sweep
}

public struct CommandItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let kind: CommandKind
}

/// Pure query → actions mapping for the ⌘K bar.
public enum CommandBarEngine {
    private static let commands: [CommandItem] = [
        CommandItem(id: "today", title: "Go to Today", icon: "sun.max", kind: .goToday),
        CommandItem(id: "board", title: "Go to Board", icon: "rectangle.split.3x1", kind: .goBoard),
        CommandItem(id: "agent", title: "Go to Agent", icon: "sparkles", kind: .goAgent),
        CommandItem(id: "sweep", title: "Sweep knowledge base now", icon: "wand.and.stars", kind: .sweep),
    ]

    public static func items(query: String) -> [CommandItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }

        let matching = commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
        let add = CommandItem(
            id: "add", title: "Add task: \u{201C}\(trimmed)\u{201D}",
            icon: "plus.circle", kind: .addTask(trimmed)
        )
        return [add] + matching
    }
}
