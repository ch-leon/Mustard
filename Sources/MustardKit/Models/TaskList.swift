import Foundation
import SwiftData

@Model
public final class TaskList {
    public var name: String = ""
    public var createdAt: Date = Date.now
    public var area: Area?
    @Relationship(deleteRule: .cascade, inverse: \MustardTask.list)
    public var tasks: [MustardTask]? = []

    public init(name: String = "", area: Area? = nil) {
        self.name = name
        self.area = area
        self.createdAt = .now
    }
}
