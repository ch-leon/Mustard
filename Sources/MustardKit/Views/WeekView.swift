import SwiftUI
import SwiftData

/// Week planner (spec feature 6, Sunsama/Akiflow): an unscheduled rail and a
/// Mon–Sun grid. Drag a rail task onto a day to schedule it (keeps time-of-day,
/// 9:00 default); drag a day block back to the rail to unschedule.
public struct WeekView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @State private var weekOffset = 0

    public init() {}

    private var days: [Date] { WeekPlanner.days(weekOffset: weekOffset) }
    private var unscheduled: [MustardTask] { WeekPlanner.unscheduled(allTasks) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Palette.hairline)
            HStack(alignment: .top, spacing: 0) {
                rail
                Divider().overlay(Theme.Palette.hairline)
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                    if day != days.last { Divider().overlay(Theme.Palette.hairline) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Week").font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(Theme.Palette.textSecondary)
            Button("Today") { weekOffset = 0 }
                .buttonStyle(.plain).font(Theme.Fonts.meta)
                .foregroundStyle(weekOffset == 0 ? Theme.Palette.textTertiary : Theme.Palette.accent)
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(Theme.Palette.textSecondary)
            if let first = days.first, let last = days.last {
                Text("\(first.formatted(.dateTime.day().month())) – \(last.formatted(.dateTime.day().month()))")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UNSCHEDULED")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(unscheduled) { task in
                        WeekChip(task: task).draggable(task.uid)
                    }
                    if unscheduled.isEmpty {
                        Text("All scheduled")
                            .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
            }
        }
        .padding(12)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface.opacity(0.4))
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first, let task = allTasks.first(where: { $0.uid == uid })
            else { return false }
            task.scheduledAt = nil
            return true
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayTasks = WeekPlanner.tasks(allTasks, on: day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Theme.Palette.accent : Theme.Palette.textSecondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(dayTasks) { task in
                        WeekBlock(task: task).draggable(task.uid)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .top)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? Theme.Palette.accent.opacity(0.05) : .clear)
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first, let task = allTasks.first(where: { $0.uid == uid })
            else { return false }
            task.scheduledAt = WeekPlanner.scheduleDate(on: day, keepingTimeFrom: task.scheduledAt)
            if task.status == .inbox { task.status = .planned }
            return true
        }
    }
}

struct WeekChip: View {
    let task: MustardTask
    var body: some View {
        HStack(spacing: 6) {
            if task.owner == .agent {
                Image(systemName: "cpu").font(.system(size: 10)).foregroundStyle(Theme.Palette.agent)
            }
            Text(task.title).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
    }
}

struct WeekBlock: View {
    let task: MustardTask
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let when = task.scheduledAt {
                Text(when.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text(task.title)
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textPrimary)
                .strikethrough(task.status == .done, color: Theme.Palette.textTertiary)
                .lineLimit(2)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
