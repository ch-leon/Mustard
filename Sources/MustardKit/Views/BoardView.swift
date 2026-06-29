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
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.bg)
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
    }

    private func column(_ status: TaskStatus) -> some View {
        // The Done column shows only recent completions; older ones collapse into
        // a "+N older" footer so 280+ done tasks can't flood the board.
        let tasks = status == .done
            ? PersonalBoard.recentDone(allTasks)
            : PersonalBoard.tasks(allTasks, status: status)
        let olderDone = status == .done ? PersonalBoard.olderDoneCount(allTasks) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(status.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("\(tasks.count + olderDone)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            // Cards scroll within the column so a tall column never grows the
            // whole board past the window (which would push the sidebar nav
            // off-screen). LazyVStack keeps a long column cheap to render.
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(tasks) { task in
                        BoardCard(task: task)
                            .draggable(task.uid)
                            .onTapGesture { selectedTask = task }
                    }

                    if olderDone > 0 {
                        Text("+\(olderDone) older completed")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                }
            }

            QuickColumnAdd(status: status)
        }
        .padding(10)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first,
                  let task = allTasks.first(where: { $0.uid == uid }) else { return false }
            guard task.status != status else { return true }
            if status == .done {
                TaskCompletion.complete(task, in: context)
            } else {
                PersonalBoard.moveStatus(task, to: status)
            }
            return true
        }
    }
}

struct BoardCard: View {
    @Environment(AgentService.self) private var agent
    let task: MustardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .strikethrough(task.status == .done, color: Theme.Palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if task.isBlocked {
                Label("Blocked", systemImage: "exclamationmark.octagon")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            if task.scheduledAt != nil || task.estimateMinutes != 30 || task.list != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let when = task.scheduledAt {
                        Label(
                            when.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                            systemImage: "calendar"
                        )
                        .foregroundStyle(Theme.Palette.accent)
                        .lineLimit(1)
                    }
                    if task.list != nil || task.estimateMinutes != 30 {
                        HStack(spacing: 6) {
                            if let list = task.list {
                                ListBadge(list: list)
                            }
                            if task.estimateMinutes != 30 {
                                Text("\(task.estimateMinutes)m")
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                            DelegationBadge(task: task)
                        }
                        .lineLimit(1)
                    }
                }
                .font(Theme.Fonts.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
        .contextMenu {
            if task.owner == .me && task.delegation == nil && task.status != .done {
                Button { agent.delegate(task) } label: {
                    Label("Ask agent to do this", systemImage: "cpu")
                }
            }
        }
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
