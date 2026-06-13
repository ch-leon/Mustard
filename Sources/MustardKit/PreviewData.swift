import Foundation
import SwiftData

/// In-memory sample container for #Preview and manual demo runs.
@MainActor
public enum PreviewData {
    public static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, CalendarEvent.self, configurations: config
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

        let meeting = CalendarEvent(
            externalId: "sample-1", title: "Sprint planning",
            start: today(13, 0), end: today(14, 0),
            joinURL: "https://meet.google.com/sample"
        )
        ctx.insert(meeting)

        let rec = Recommendation(
            title: "Reply to Kamil re: BLE handshake regression",
            body: "Kamil asked for a status by EOD.",
            actionType: "draft_email", vaultPath: "/vault",
            confidence: 0.82,
            reasoning: "He flagged a regression and asked for status by EOD; the tracker shows the fix moved to In Review yesterday.",
            draft: "Hi Kamil,\n\nConfirming the BLE handshake regression is now in review — fix landed yesterday, QA verifying today. Verified build by EOD tomorrow.\n\nCheers,\nLeon",
            source: "gmail", sourceContext: "Thales SDK — kamil@thalesgroup.com"
        )
        ctx.insert(rec)
        return container
    }()
}
