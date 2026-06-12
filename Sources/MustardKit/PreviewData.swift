import Foundation
import SwiftData

/// In-memory sample container for #Preview and manual demo runs.
@MainActor
public enum PreviewData {
    public static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, configurations: config
        )
        let ctx = container.mainContext
        let cal = Calendar.current
        func today(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: .now)!
        }
        let work = Area(name: "Code Heroes", colorHex: "#2D7FF9")
        ctx.insert(work)
        let standup = MustardTask(title: "Team standup", scheduledAt: today(9, 30))
        standup.estimateMinutes = 15
        let focus = MustardTask(title: "Draft DLA 5.2 release notes", scheduledAt: today(10, 0))
        focus.estimateMinutes = 90
        let sync = MustardTask(title: "Thales SDK sync", scheduledAt: today(11, 30))
        let loose = MustardTask(title: "Reply to Kamil re: BLE issue")
        for task in [standup, focus, sync, loose] { ctx.insert(task) }
        return container
    }()
}
