import SwiftUI
import SwiftData

public struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @State private var selectedTask: MustardTask?
    private let today = Date.now
    /// Navigate to the Agent console (the header "✦ Plan with agent" entry).
    private let onPlan: () -> Void

    public init(onPlan: @escaping () -> Void = {}) { self.onPlan = onPlan }

    private var progress: (done: Int, total: Int) { DayPlanner.dayProgress(allTasks, day: today) }

    private var scheduled: [MustardTask] { DayPlanner.tasksForDay(allTasks, day: today) }
    private var unscheduled: [MustardTask] { DayPlanner.unscheduled(allTasks) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                progressBar
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
            Button(action: onPlan) {
                Text("✦ Plan with agent")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.Palette.agentText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Theme.Palette.agentTintLight, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Open the Agent console to plan your day.")
        }
        .padding(.bottom, 12)
    }

    /// Thin day-progress bar — "N of M done" over today's scheduled tasks.
    @ViewBuilder private var progressBar: some View {
        let p = progress
        if p.total > 0 {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.hairline)
                        Capsule().fill(Theme.Palette.done)
                            .frame(width: geo.size.width * CGFloat(p.done) / CGFloat(p.total))
                    }
                }
                .frame(height: 4)
                Text("\(p.done) of \(p.total) done")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.bottom, 16)
        }
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
