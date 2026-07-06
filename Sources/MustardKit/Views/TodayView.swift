import SwiftUI
import SwiftData

public struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    @Query private var recommendations: [Recommendation]
    @State private var selectedTask: MustardTask?
    @State private var nudgeDismissed = false
    private let today = Date.now
    /// Navigate to the Agent console (the header "✦ Plan with agent" entry).
    private let onPlan: () -> Void

    // Morning-ritual entry state. The two Doubles are epoch seconds (0 == never);
    // RitualPrompt works in Date? so we bridge in `shouldOffer` below.
    @AppStorage(RitualPrompt.lastPlannedKey) private var lastPlanned: Double = 0
    @AppStorage(RitualPrompt.dismissedKey) private var ritualDismissed: Double = 0
    @State private var showRitual = false
    // ⌘K → open-ritual channel. The command bar can't reach Today's local
    // `showRitual` state, so it flips this AppStorage flag (the app's existing
    // lightweight cross-view channel); we consume it in onAppear/onChange.
    @AppStorage(RitualPrompt.openRequestedKey) private var ritualOpenRequested = false

    public init(onPlan: @escaping () -> Void = {}) { self.onPlan = onPlan }

    /// Whether to show the "Plan your day" banner (and offer the ritual at all).
    private var shouldOffer: Bool {
        RitualPrompt.shouldOffer(
            lastPlannedDay: lastPlanned > 0 ? Date(timeIntervalSince1970: lastPlanned) : nil,
            dismissedDay: ritualDismissed > 0 ? Date(timeIntervalSince1970: ritualDismissed) : nil,
            now: .now)
    }

    /// Today's focus-starred open tasks — pinned above the timeline.
    private var focusTasks: [MustardTask] { RitualPlanner.focused(allTasks, day: today) }

    private var progress: (done: Int, total: Int) { DayPlanner.dayProgress(allTasks, day: today) }
    private var nudgeCount: Int { AgentInbox.waitingCount(recommendations: recommendations, tasks: allTasks) }

    private var scheduled: [MustardTask] { DayPlanner.tasksForDay(allTasks, day: today) }
    private var unscheduled: [MustardTask] { DayPlanner.unscheduled(allTasks) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                progressBar
                ritualBanner
                agentNudge
                focusSection
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(scheduled) { task in
                        TimelineRow(task: task, onToggleDone: { toggle(task) }, onOpen: { selectedTask = task })
                        Divider().overlay(Theme.Palette.hairline)
                    }
                }
                if scheduled.isEmpty {
                    // Warm empty state (Craft pass Phase 1) — points at the capture
                    // field directly below it.
                    VStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text("Nothing scheduled yet")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text("Capture a task below to start the day")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
        .onAppear {
            DayPlanner.carryForward(allTasks, to: today)
            consumeRitualRequest()
        }
        .onChange(of: ritualOpenRequested) { consumeRitualRequest() }
        .sheet(item: $selectedTask) { TaskDetailSheet(task: $0) }
        .sheet(isPresented: $showRitual) {
            MorningRitualView(
                day: today,
                onFinish: { lastPlanned = Date.now.timeIntervalSince1970; showRitual = false },
                onOpenConsole: { showRitual = false; onPlan() })
        }
    }

    /// Honour a ⌘K "Plan my day" request routed through AppStorage, then clear it.
    private func consumeRitualRequest() {
        if ritualOpenRequested {
            showRitual = true
            ritualOpenRequested = false
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Today")
                .font(Theme.Fonts.docH1)   // editorial weight (Craft pass Phase 1); same 22pt
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

    /// "Plan your day" banner — a YOU action (not the agent), so accent-family
    /// styling: plain surface + hairline, sunrise glyph in accent. Shown until the
    /// day is planned or the offer is dismissed (both reset at midnight).
    @ViewBuilder private var ritualBanner: some View {
        if shouldOffer {
            let rolled = RitualPlanner.rollover(allTasks, day: today).count
            let recs = AgentInbox.pendingRecCount(recommendations)
            HStack(spacing: 10) {
                Image(systemName: "sunrise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plan your day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(ritualSubtitle(rolled: rolled, recs: recs))
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    ritualDismissed = Date.now.timeIntervalSince1970
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss for today")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Palette.hairline, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { showRitual = true }
            .padding(.bottom, 16)
        }
    }

    /// Subtitle assembled from counts; omit zero parts, both zero → generic line.
    private func ritualSubtitle(rolled: Int, recs: Int) -> String {
        var parts: [String] = []
        if rolled > 0 { parts.append("\(rolled) rolled over") }
        if recs > 0 { parts.append("\(recs) from the agent") }
        return parts.isEmpty ? "Set up today in under a minute" : parts.joined(separator: " · ")
    }

    /// FOCUS pins — today's starred tasks, above the chronological timeline.
    /// They still appear in the timeline below (deliberate duplication: the
    /// timeline stays the chronological truth). One-line filter later if disliked.
    @ViewBuilder private var focusSection: some View {
        let focus = focusTasks
        if !focus.isEmpty {
            Text("FOCUS")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.top, 4)
                .padding(.bottom, 4)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(focus) { task in
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.accent)
                        TimelineRow(task: task, onToggleDone: { toggle(task) }, onOpen: { selectedTask = task })
                    }
                    Divider().overlay(Theme.Palette.hairline)
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Dismissible nudge shown when the agent has items waiting (recs + review).
    /// Auto-hides when the queue empties; tap opens the Agent console.
    @ViewBuilder private var agentNudge: some View {
        let n = nudgeCount
        if n > 0 && !nudgeDismissed {
            HStack(spacing: 10) {
                Text("✦")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.agentText)
                    .frame(width: 24, height: 24)
                    .background(Theme.Palette.agentTintLight, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent has \(n) thing\(n == 1 ? "" : "s") for you")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Tap to review in the Agent console")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    nudgeDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Palette.agentTintFaint, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Palette.agentTintMid, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: onPlan)
            .padding(.bottom, 16)
        }
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
