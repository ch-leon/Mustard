import SwiftUI
import SwiftData

/// Personal Kanban (spec feature 3): my tasks in status columns,
/// drag a card between columns to change status. Things-3-calm.
public struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @State private var selectedTask: MustardTask?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Board")
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(PersonalBoard.columns, id: \.self) { status in
                        column(status)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.bg)
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
    }

    private func column(_ status: TaskStatus) -> some View {
        let tasks = PersonalBoard.tasks(allTasks, status: status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(status.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("\(tasks.count)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(tasks) { task in
                BoardCard(task: task)
                    .draggable(task.uid)
                    .onTapGesture { selectedTask = task }
            }

            QuickColumnAdd(status: status)
        }
        .padding(10)
        .frame(width: 220, alignment: .top)
        .background(Theme.Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first,
                  let task = allTasks.first(where: { $0.uid == uid }) else { return false }
            guard task.status != status else { return true }
            if status == .done {
                TaskCompletion.complete(task, in: context)
            } else {
                PersonalBoard.move(task, to: status)
            }
            return true
        }
    }
}

struct BoardCard: View {
    let task: MustardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .strikethrough(task.status == .done, color: Theme.Palette.textTertiary)
            if task.isBlocked {
                Label("Blocked", systemImage: "exclamationmark.octagon")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            if task.scheduledAt != nil || task.estimateMinutes != 30 || task.list != nil {
                HStack(spacing: 6) {
                    if let when = task.scheduledAt {
                        Label(
                            when.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                            systemImage: "calendar"
                        )
                        .foregroundStyle(Theme.Palette.accent)
                    }
                    if let list = task.list {
                        ListBadge(list: list)
                    }
                    if task.estimateMinutes != 30 {
                        Text("\(task.estimateMinutes)m")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .font(Theme.Fonts.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
    }
}

struct QuickColumnAdd: View {
    @Environment(\.modelContext) private var context
    let status: TaskStatus
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            TextField("Add…", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.meta)
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { focused = true; return }
        let task = MustardTask(title: trimmed)
        task.status = status
        context.insert(task)
        text = ""
        focused = true
    }
}
