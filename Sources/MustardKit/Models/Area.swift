import Foundation
import SwiftData

@Model
public final class Area {
    public var name: String = ""
    public var colorHex: String = "#2D7FF9"
    public var createdAt: Date = Date.now
    // Nullify (not cascade): deleting an Area keeps its lists — they just lose
    // their area. Organising never destroys data.
    @Relationship(deleteRule: .nullify, inverse: \TaskList.area)
    public var lists: [TaskList]? = []

    public init(name: String = "", colorHex: String = "#2D7FF9") {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = .now
    }
}
