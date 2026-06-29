import SwiftUI
import SwiftData

/// A single board task card (BAK-79). Owner-segmented design — see the design
/// handoff "Component: Task Card". Presentational: it reads a `MustardTask` and
/// dispatches owner toggles to `PersonalBoard`/`AgentService`. All hex/sizes are
/// from the handoff (Theme lacks the source/status/confidence tints).
public struct MustardBoardCard: View {
    @Environment(AgentService.self) private var agent
    let task: MustardTask
    let showConfidence: Bool

    public init(task: MustardTask, showConfidence: Bool) {
        self.task = task
        self.showConfidence = showConfidence
    }

    private var stage: TaskStage { task.stage }
    private var isDone: Bool { stage == .done }
    private var isAgent: Bool { task.owner == .agent }
    private var isBlocked: Bool { stage == .blocked || task.isBlocked }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            title
            metaRow
            confidenceRow
            statusPill
            blockedRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Color(hex: "#FBFAF7"), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#E7E3DA"), lineWidth: 0.5))
        .overlay(alignment: .leading) { accentBorder }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .opacity(isDone ? 0.66 : 1)
    }

    // MARK: Left accent border (2.5px)

    @ViewBuilder private var accentBorder: some View {
        if isBlocked {
            Color(hex: "#D98A29").frame(width: 2.5)
        } else if isAgent {
            Theme.Palette.agent.frame(width: 2.5)
        }
    }

    // MARK: Top row — owner toggle + gated padlock

    @ViewBuilder private var topRow: some View {
        if !isDone {
            HStack(spacing: 6) {
                ownerToggle
                Spacer(minLength: 0)
                if task.isGated {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .help("Gated action — always reviewed by you")
                }
            }
            .frame(minHeight: 18)
            .padding(.bottom, 7)
        }
    }

    private var ownerToggle: some View {
        HStack(spacing: 0) {
            ownerTab(label: "You", active: !isAgent) {
                PersonalBoard.reassign(task, to: .me)
            }
            ownerTab(label: "✦", active: isAgent) {
                agent.delegate(task)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#E1DCD1"), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func ownerTab(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        let isAgentTab = label == "✦"
        Text(label)
            .font(.system(size: 10, weight: active ? .semibold : .regular))
            .foregroundStyle(
                active ? (isAgentTab ? Color.white : Color(hex: "#46433B"))
                       : Color(hex: "#BBB6AA")
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                active ? (isAgentTab ? Theme.Palette.agent : Color(hex: "#EAE5DB"))
                       : Color.clear
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    // MARK: Title

    private var title: some View {
        Text(task.title)
            .font(.system(size: 13.5))
            .lineSpacing(13.5 * 0.35)
            .foregroundStyle(isDone ? Color(hex: "#A6A296") : Theme.Palette.textPrimary)
            .strikethrough(isDone, color: Color(hex: "#C8C3B7"))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Meta row — area · source · due

    @ViewBuilder private var metaRow: some View {
        let area = task.list?.area
        let badge = sourceBadge
        let due = task.scheduledAt
        if area != nil || badge != nil || due != nil {
            FlowMeta {
                if let area {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: area.colorHex))
                            .frame(width: 7, height: 7)
                        Text(area.name)
                    }
                }
                if let badge {
                    HStack(spacing: 4) {
                        Text(badge.icon)
                        Text(badge.label)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(badge.fg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(badge.bg, in: Capsule())
                }
                if let due {
                    Text("🗓 \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.top, 8)
        }
    }

    /// Only `meeting` and `vault`/`manual` are real sources today (see report).
    /// Manual tasks show no badge.
    private var sourceBadge: (label: String, icon: String, fg: Color, bg: Color)? {
        switch task.source {
        case "meeting":
            return ("Notes", "◷", Color(hex: "#6A61C9"), Color(hex: "#EEEBFA"))
        case "manual":
            return nil
        default: // "vault" and any other harvested source map to KB grey
            return ("KB", "📚", Color(hex: "#7B776C"), Color(hex: "#F1EDE4"))
        }
    }

    // MARK: Confidence

    @ViewBuilder private var confidenceRow: some View {
        if showConfidence, stage == .needsApproval, let conf = task.confidence {
            let color = confColor(conf)
            let filled = Int((conf * 5).rounded())
            HStack(spacing: 6) {
                Text(String(format: "%.2f", conf))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(color)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < filled ? color : Color(hex: "#E4DFD5"))
                            .frame(width: 11, height: 4)
                    }
                }
            }
            .padding(.top, 9)
        }
    }

    private func confColor(_ c: Double) -> Color {
        if c >= 0.7 { return Theme.Palette.done }
        if c >= 0.5 { return Color(hex: "#BA7517") }
        return Color(hex: "#D85A30")
    }

    // MARK: Status pill

    @ViewBuilder private var statusPill: some View {
        if let s = statusInfo {
            Text(s.text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(s.fg)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(s.bg, in: Capsule())
                .padding(.top, 9)
        }
    }

    private var statusInfo: (text: String, fg: Color, bg: Color)? {
        switch stage {
        case .forAgent:
            return ("Waiting for agent to pick up", Color(hex: "#8A8579"), Color(hex: "#F1EDE4"))
        case .needsApproval:
            return ("Your move · approve to run", Color(hex: "#6A61C9"), Color(hex: "#EEEBFA"))
        case .queued:
            return ("Queued to run", Color(hex: "#8A8579"), Color(hex: "#F1EDE4"))
        case .needsReview:
            return ("Review output", Color(hex: "#1B7A57"), Color(hex: "#E3F2EB"))
        default:
            return nil
        }
    }

    // MARK: Blocked reason

    @ViewBuilder private var blockedRow: some View {
        if isBlocked {
            let reason = task.blockedReason.trimmingCharacters(in: .whitespaces)
            Text("⚠ \(reason.isEmpty ? "Blocked" : reason)")
                .font(.system(size: 11.5))
                .lineSpacing(11.5 * 0.35)
                .foregroundStyle(Color(hex: "#B07A29"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }
}

/// Wrapping horizontal layout for the meta row (area/source/due may overflow the
/// narrow column). Falls back gracefully on older SDKs via SwiftUI's `Layout`.
private struct FlowMeta: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview {
    let ctx = PreviewData.container.mainContext
    let tasks = (try? ctx.fetch(FetchDescriptor<MustardTask>())) ?? []
    return ScrollView {
        VStack(spacing: 8) {
            ForEach(tasks) { MustardBoardCard(task: $0, showConfidence: true) }
        }
        .padding()
        .frame(width: 200)
    }
    .background(Color(hex: "#EFEBE2").opacity(0.4))
    .environment(AgentService(context: ctx))
}
#endif
