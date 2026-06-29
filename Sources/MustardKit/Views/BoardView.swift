import SwiftUI
import SwiftData

/// The owner-segmented task board (BAK-79). A single board whose visible columns
/// change with the owner lens (Everyone / Mine / Agent). Pipeline + two human gates
/// (Needs Approval, Needs Review). Recreated from the design handoff; all hex/sizes
/// that Theme lacks (column kind tints) come straight from the handoff.
///
/// Scope note: only the board content right of the existing app sidebar lives here.
public struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @Query(sort: \Area.name) private var areas: [Area]

    @State private var view: BoardOwnerView
    @State private var area: BoardArea = .all
    @State private var selectedTask: MustardTask?

    private let settings = BoardSettings()
    private var compact: Bool { settings.compact }
    private var showConfidence: Bool { settings.showConfidence }
    private var columnWidth: CGFloat { compact ? 162 : 182 }

    public init() {
        _view = State(initialValue: BoardSettings().defaultView)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            columns
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.bg)
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Board")
                    .font(Theme.Fonts.header)
                    .foregroundStyle(Theme.Palette.textPrimary)
                let waiting = PersonalBoard.waitingCount(allTasks, view: view, area: area)
                if waiting > 0 {
                    Text("● \(waiting) waiting on you")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(hex: "#6A61C9"))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#EEEBFA"), in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: "#E2DCF4"), lineWidth: 0.5))
                }
                Spacer(minLength: 0)
            }

            controls
                .padding(.top, 16)

            HStack(spacing: 6) {
                Text("●").foregroundStyle(Theme.Palette.agent)
                Text(view.caption)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color(hex: "#8A8579"))
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            ownerSegmentedControl
            Rectangle()
                .fill(Color(hex: "#E1DCD1"))
                .frame(width: 0.5, height: 22)
            areaChips
        }
    }

    private var ownerSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(Array(BoardOwnerView.allCases.enumerated()), id: \.element.id) { idx, v in
                let active = v == view
                let activeBg = v == .agent ? Theme.Palette.agent : Theme.Palette.textPrimary
                Text(v.label)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Color.white : Color(hex: "#8A8579"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(active ? AnyShapeStyle(activeBg) : AnyShapeStyle(Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { view = v }
                    .overlay(alignment: .trailing) {
                        if idx < BoardOwnerView.allCases.count - 1 {
                            Rectangle().fill(Color(hex: "#E1DCD1")).frame(width: 0.5)
                        }
                    }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#E1DCD1"), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var areaChips: some View {
        HStack(spacing: 6) {
            areaChip(label: "All areas", target: .all)
            ForEach(areas) { a in
                areaChip(label: a.name, target: .area(a.name))
            }
        }
    }

    @ViewBuilder
    private func areaChip(label: String, target: BoardArea) -> some View {
        let active = area == target
        Text(label)
            .font(.system(size: 12, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? Color(hex: "#46433B") : Theme.Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(active ? Color(hex: "#EAE5DB") : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(active ? Color(hex: "#DAD3C6") : Color.clear, lineWidth: 0.5))
            .contentShape(Capsule())
            .onTapGesture { area = target }
    }

    // MARK: Columns

    private var columns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 11) {
                ForEach(PersonalBoard.columns(for: view), id: \.self) { stage in
                    column(stage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func column(_ stage: TaskStage) -> some View {
        let style = ColumnStyle(stage.kind)
        let all = PersonalBoard.tasks(allTasks, in: stage, view: view, area: area)
        let isDone = stage == .done
        let visible = isDone ? Array(all.prefix(PersonalBoard.doneColumnLimit)) : all
        let older = isDone ? PersonalBoard.olderDoneCount(allTasks, view: view, area: area) : 0
        let totalCount = isDone ? visible.count + older : all.count

        return VStack(alignment: .leading, spacing: 0) {
            if let accent = style.accent {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(height: 3)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 9)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stage.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.04 * 11)
                        .foregroundStyle(style.head)
                    Text("\(totalCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#C0BCB1"))
                }
                if let sub = stage.subLabel {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 9)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if visible.isEmpty && older == 0 {
                        Text("—")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: "#C8C3B7"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                    }
                    ForEach(visible) { task in
                        MustardBoardCard(task: task, showConfidence: showConfidence)
                            .draggable(task.uid)
                            .onTapGesture { selectedTask = task }
                    }
                    if older > 0 {
                        Text("+\(older) older completed")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                    QuickColumnAdd(stage: stage)
                }
            }
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(style.background, in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first,
                  let task = allTasks.first(where: { $0.uid == uid }) else { return false }
            guard task.stage != stage else { return true }
            if stage == .done {
                TaskCompletion.complete(task, in: context)
            } else {
                PersonalBoard.move(task, to: stage)
                // Keep owner coherent with the lane dropped into; Inbox/Done are shared.
                switch stage {
                case .forAgent, .needsApproval, .queued, .needsReview: task.owner = .agent
                case .planned, .scheduled, .inProgress, .blocked: task.owner = .me
                case .inbox, .done: break
                }
            }
            return true
        }
    }
}

/// Visual treatment for a board column, mapped from `TaskColumnKind`. The tints are
/// from the design handoff ("Column styling by kind") — Theme has no column tokens.
private struct ColumnStyle {
    let background: Color
    let accent: Color?
    let head: Color

    init(_ kind: TaskColumnKind) {
        switch kind {
        case .standard:
            background = Color(hex: "#EFEBE2").opacity(0.55)
            accent = nil
            head = Color(hex: "#9A968B")
        case .handoff:
            background = Theme.Palette.agent.opacity(0.05)
            accent = Color(hex: "#CFC9F0")
            head = Color(hex: "#8079C6")
        case .gate:
            background = Theme.Palette.agent.opacity(0.085)
            accent = Theme.Palette.agent
            head = Color(hex: "#6A61C9")
        case .agent:
            background = Theme.Palette.agent.opacity(0.05)
            accent = Color(hex: "#BCB6EC")
            head = Color(hex: "#8079C6")
        case .warn:
            background = Theme.Palette.warning.opacity(0.07)
            accent = Theme.Palette.warning
            head = Color(hex: "#B07A29")
        case .done:
            background = Theme.Palette.done.opacity(0.05)
            accent = Color(hex: "#9BD0BD")
            head = Color(hex: "#6A9C84")
        }
    }
}

/// Per-column "+ Add" affordance: inserts a new `.me` task at this stage. `stage` is
/// the source of truth; the legacy `status` field is left at its default.
struct QuickColumnAdd: View {
    @Environment(\.modelContext) private var context
    let stage: TaskStage
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#C0BCB1"))
            }
            .buttonStyle(.plain)
            TextField("Add…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#C0BCB1"))
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.horizontal, 4)
        .padding(.top, 7)
        .padding(.bottom, 2)
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { focused = true; return }
        let task = MustardTask(title: trimmed)
        task.stage = stage
        context.insert(task)
        text = ""
        focused = true
    }
}

#if DEBUG
#Preview {
    BoardView()
        .frame(width: 1100, height: 700)
        .modelContainer(PreviewData.container)
        .environment(AgentService(context: PreviewData.container.mainContext))
}
#endif
