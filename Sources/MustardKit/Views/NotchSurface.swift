import AppKit
import SwiftUI
import SwiftData

/// The notch surface (spec §6a): a black, notch-hugging panel at the top
/// of the built-in display. Idle: thin strip rotating focus → waiting count.
/// Hover: expands into the agent tray + quick capture. Intentionally dark —
/// it extends the physical notch — unlike the rest of the app.
@MainActor
public final class NotchController {
    private var panel: NSPanel?
    private let makeContent: (_ onHover: @escaping (Bool) -> Void) -> AnyView

    private let expandedSize = NSSize(width: 420, height: 300)

    public init(content: @escaping (_ onHover: @escaping (Bool) -> Void) -> AnyView) {
        self.makeContent = content
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Idle strip geometry: hug the physical notch with a small lip below;
    /// sensible fallback for displays without a notch.
    private func idleFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let notchHeight = screen.safeAreaInsets.top
        let width: CGFloat
        let height: CGFloat
        if notchHeight > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = frame.width - left.width - right.width + 24
            height = notchHeight + 20
        } else {
            width = 230
            height = 30
        }
        return NSRect(
            x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height
        )
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(
            x: frame.midX - expandedSize.width / 2,
            y: frame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    public func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show()
    }

    public func show() {
        guard let screen else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: idleFrame(on: screen),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.contentView = NSHostingView(
                rootView: makeContent { [weak self] hovering in
                    self?.setExpanded(hovering)
                }
            )
            self.panel = panel
        }
        panel?.setFrame(idleFrame(on: screen), display: true)
        panel?.orderFrontRegardless()
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, let screen else { return }
        let target = expanded ? expandedFrame(on: screen) : idleFrame(on: screen)
        panel.hasShadow = expanded
        panel.setFrame(target, display: true, animate: true)
    }
}

public struct NotchView: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    @Query private var tasks: [MustardTask]
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @Query(sort: \CalendarEvent.start) private var events: [CalendarEvent]
    @State private var hovering = false
    @State private var captureText = ""
    @FocusState private var captureFocused: Bool
    let onHoverChange: (Bool) -> Void

    public init(onHoverChange: @escaping (Bool) -> Void) {
        self.onHoverChange = onHoverChange
    }

    private var focusTask: MustardTask? {
        let todays = DayPlanner.tasksForDay(tasks, day: .now).filter { $0.status.isOpen && !$0.isBlocked }
        return tasks.first { $0.status == .inProgress && !$0.isBlocked } ?? todays.first
    }

    private var pending: [Recommendation] {
        RecommendationQueue.pending(recommendations, now: .now)
    }

    /// Tasks the board is waiting on you to review (output review now lives on the
    /// board's Needs Review column — ADR-0010).
    private var needsReviewCount: Int {
        tasks.filter { $0.stage == .needsReview }.count
    }

    private var waitingCount: Int {
        pending.count + needsReviewCount
    }

    private var todayMeetings: [CalendarEvent] {
        events.filter { Calendar.current.isDateInToday($0.start) }
    }

    private var nextMeeting: CalendarEvent? {
        events.first { $0.start > .now && Calendar.current.isDateInToday($0.start) }
    }

    private func nextMeetingLabel() -> String? {
        guard let m = nextMeeting else { return nil }
        return "\(m.title) · \(m.start.formatted(date: .omitted, time: .shortened))"
    }

    public var body: some View {
        VStack(spacing: 0) {
            shape
            Spacer(minLength: 0)
        }
        .onHover { isIn in
            withAnimation(.snappy(duration: 0.16)) { hovering = isIn }
            onHoverChange(isIn)
        }
    }

    private func capture() {
        let trimmed = captureText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { captureFocused = true; return }
        context.insert(MustardTask(title: trimmed))
        captureText = ""
        captureFocused = true
    }

    private var shape: some View {
        Group {
            if hovering { expandedContent } else { idleContent }
        }
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: hovering ? 18 : 10,
                bottomTrailingRadius: hovering ? 18 : 10
            )
            .fill(.black)
        )
    }

    private var idleContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 4)) { timeline in
                let items = NotchTicker.idleItems(
                    focusTitle: agent.isExecuting ? (agent.currentTitle ?? "Agent working…") : focusTask?.title,
                    waitingCount: waitingCount,
                    nextEvent: nextMeetingLabel()
                )
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 4)
                HStack(spacing: 5) {
                    if agent.isExecuting {
                        Circle().fill(Color(hex: "#7F77DD")).frame(width: 5, height: 5)
                    } else if waitingCount > 0 {
                        Circle().fill(Color(hex: "#5DCAA5")).frame(width: 5, height: 5)
                    }
                    Text(NotchTicker.item(items, tick: tick))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 30)

            HStack(spacing: 8) {
                if agent.isExecuting {
                    ProgressView().controlSize(.small).colorScheme(.dark)
                    Text(agent.currentTitle ?? "Agent working…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else if let task = focusTask {
                    Image(systemName: "target")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6E9FFF"))
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text("All clear")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if waitingCount > 0 {
                    Text("\(waitingCount) waiting")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#AFA9EC"))
                }
            }

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            if !todayMeetings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY").font(.system(size: 9, weight: .semibold)).tracking(0.08)
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach(todayMeetings.prefix(3)) { event in
                        HStack(spacing: 8) {
                            Text(event.isAllDay ? "all-day" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "#9FB7E0"))
                                .frame(width: 56, alignment: .leading)
                            Text(event.title)
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            Spacer(minLength: 0)
                            if let join = event.joinURL, let url = URL(string: join) {
                                Link("Join", destination: url)
                                    .font(.system(size: 11)).foregroundStyle(Color(hex: "#6E9FFF"))
                            }
                        }
                    }
                }
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }

            if pending.isEmpty {
                Text("No recommendations waiting")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(pending.prefix(3)) { rec in
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#AFA9EC"))
                        Text(rec.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer()
                        if rec.action == .fyi {
                            // FYI is inert on approve (no claude run, no card), so a generic
                            // "Approve" here would clear it with nothing filed. Acknowledging an
                            // FYI must file it to the KB log like the console's Keep — Keep = file,
                            // Dismiss = drop. keep() is a synchronous local write (no executor).
                            Button("Keep") { agent.keep(rec) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "#6E9FFF"))
                            Button("Dismiss") { rec.decision = .denied }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            Button("Approve") {
                                Task { await agent.decide(rec, .approved) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#6E9FFF"))
                            .disabled(agent.isExecuting)
                            Button("Deny") { rec.decision = .denied }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: capture) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                TextField("Quick capture…", text: $captureText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($captureFocused)
                    .onSubmit(capture)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
