import SwiftUI
import SwiftData

/// The filtered content for a selected list (or the Unfiled bucket): a header,
/// the tasks, and a quick-add that files new tasks into the list. Mirrors
/// TodayView's structure and reuses TimelineRow + TaskDetailSheet.
struct ListContentView: View {
    @Environment(\.modelContext) private var context
    let scope: ListScope
    @Query private var allTasks: [MustardTask]
    @State private var selectedTask: MustardTask?

    private var tasks: [MustardTask] {
        switch scope {
        case .unfiled: return AreaOrganizer.unfiled(allTasks)
        case .list(let list): return AreaOrganizer.tasks(in: list, from: allTasks)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(tasks) { task in
                    TimelineRow(task: task, onToggleDone: { toggle(task) }, onOpen: { selectedTask = task })
                    Divider().overlay(Theme.Palette.hairline)
                }
                if tasks.isEmpty {
                    Text(scope.isUnfiled ? "Nothing unfiled." : "No tasks in this list yet.")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.vertical, 16)
                }
                QuickCaptureField(fileInto: scope.listValue)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Palette.bg)
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            switch scope {
            case .unfiled:
                Image(systemName: "tray").foregroundStyle(Theme.Palette.textTertiary)
                Text("Unfiled")
                    .font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
            case .list(let list):
                Circle()
                    .fill(Color(hex: list.area?.colorHex ?? "#B0ACA1"))
                    .frame(width: 10, height: 10)
                Text(list.name.isEmpty ? "Untitled list" : list.name)
                    .font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
                if let area = list.area {
                    Text(area.name)
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private func toggle(_ task: MustardTask) {
        if task.status == .done {
            task.status = .planned
            task.completedAt = nil
        } else {
            task.markDone()
        }
    }
}
