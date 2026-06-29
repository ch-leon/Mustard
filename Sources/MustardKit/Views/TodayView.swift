import SwiftUI
import SwiftData

public struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @State private var selectedTask: MustardTask?
    private let today = Date.now

    public init() {}

    private var scheduled: [MustardTask] { DayPlanner.tasksForDay(allTasks, day: today) }
    private var unscheduled: [MustardTask] { DayPlanner.unscheduled(allTasks) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(scheduled) { task in
                        TimelineRow(task: task, onToggleDone: { toggle(task) }, onOpen: { selectedTask = task })
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }
                if scheduled.isEmpty {
                    Text("Nothing scheduled yet")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.vertical, 16)
                }
                QuickCaptureField(scheduleOnto: today)

                if !unscheduled.isEmpty {
                    Text("INBOX")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.top, 24)
                        .padding(.bottom, 4)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(unscheduled) { task in
                            TimelineRow(task: task, onToggleDone: { toggle(task) }, onOpen: { selectedTask = task })
                            Divider().overlay(Theme.Palette.hairline)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Palette.bg)
        .onAppear { DayPlanner.carryForward(allTasks, to: today) }
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Today")
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private func toggle(_ task: MustardTask) {
        if task.stage == .done {
            task.stage = .planned
            task.completedAt = nil
        } else {
            TaskCompletion.complete(task, in: context)
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
