import SwiftUI

struct DelegationBadge: View {
    let task: MustardTask
    var body: some View {
        let phase = DelegationPhase.of(task)
        if let label = phase.label, let tone = phase.tone {
            content(label, tone)
        } else if task.owner == .agent {
            content("Agent", .agentHasIt)   // agent-owned, no active phase
        }
    }

    @ViewBuilder private func content(_ label: String, _ tone: DelegationTone) -> some View {
        switch tone {
        case .agentHasIt:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.agent)
        case .needsYou:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.warningDeep)
                .padding(.vertical, 1).padding(.horizontal, 8)
                .background(Theme.Palette.warningSoft, in: Capsule())
        case .doneByAgent:
            Label(label, systemImage: "checkmark")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

public struct TimelineRow: View {
    @Environment(AgentService.self) private var agent
    let task: MustardTask
    var onToggleDone: () -> Void
    var onOpen: () -> Void

    public init(task: MustardTask, onToggleDone: @escaping () -> Void, onOpen: @escaping () -> Void = {}) {
        self.task = task
        self.onToggleDone = onToggleDone
        self.onOpen = onOpen
    }

    private var timeText: String {
        guard let when = task.scheduledAt else { return "" }
        return when.formatted(date: .omitted, time: .shortened)
    }

    private var isDone: Bool { task.status == .done }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeText)
                .font(Theme.Fonts.gutter)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 1)

            Button(action: onToggleDone) {
                Image(systemName: isDone ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isDone ? Theme.Palette.done : Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(isDone ? Theme.Fonts.body : Theme.Fonts.title)
                    .foregroundStyle(isDone ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
                    .strikethrough(isDone, color: Theme.Palette.textTertiary)
                if task.estimateMinutes != 30 || task.owner == .agent || task.list != nil {
                    HStack(spacing: 6) {
                        DelegationBadge(task: task)
                        if let list = task.list {
                            ListBadge(list: list)
                        }
                        if task.estimateMinutes != 30 {
                            Text("\(task.estimateMinutes) min")
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .font(Theme.Fonts.meta)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if task.owner == .me && task.delegation == nil && task.status != .done {
                Button { Task { await agent.delegate(task) } } label: {
                    Label("Ask agent to do this", systemImage: "cpu")
                }
            }
        }
    }
}
