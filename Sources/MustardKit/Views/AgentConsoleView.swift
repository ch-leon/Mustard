import SwiftUI
import SwiftData
import AppKit

/// The agent console: vault source row, Recommendations queue (decide),
/// Review queue (accept/revise/discard). Things-3-calm throughout.
public struct AgentConsoleView: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    @AppStorage("vaultPath") private var vaultPath = ""
    @AppStorage("meetingVaultPath") private var meetingVaultPath = ""
    @AppStorage("sweepIntervalHours") private var sweepIntervalHours = 0.0
    @AppStorage("lastSweptAt") private var lastSweptAt = 0.0
    @AppStorage("trustLevel") private var trustRaw = TrustLevel.manual.rawValue

    private var trust: TrustLevel { TrustLevel(rawValue: trustRaw) ?? .manual }
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @Query(sort: \OutputCard.createdAt, order: .reverse) private var cards: [OutputCard]

    public init() {}

    private var pending: [Recommendation] {
        recommendations.filter {
            $0.decision == .pending && ($0.snoozedUntil == nil || $0.snoozedUntil! <= .now)
        }
    }

    private var reviewQueue: [OutputCard] {
        cards.filter { $0.review == .pending }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                sourceRow
                meetingSourceRow
                if let error = agent.lastError {
                    Text(error)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Color(hex: "#D85A30"))
                        .padding(.vertical, 8)
                }

                sectionLabel("RECOMMENDATIONS", count: pending.count)
                if pending.isEmpty {
                    emptyLine("Nothing waiting on you. Run a sweep.")
                }
                ForEach(pending) { rec in
                    RecommendationRow(rec: rec)
                    Divider().overlay(Theme.Palette.hairline)
                }

                sectionLabel("REVIEW", count: reviewQueue.count)
                if reviewQueue.isEmpty {
                    emptyLine("No output waiting for review.")
                }
                ForEach(reviewQueue) { card in
                    OutputCardRow(card: card)
                    Divider().overlay(Theme.Palette.hairline)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Palette.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agent")
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Palette.textPrimary)
            if agent.isExecuting {
                ProgressView().controlSize(.small)
                Text("working…")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.bottom, 12)
    }

    /// Picker for the meeting-notes vault (Leon's "Codeheroes work/" root). Tasks
    /// harvest automatically on the 60s loop; the last digest shows here.
    private var meetingSourceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.wave.2")
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(meetingVaultPath.isEmpty ? "Choose your meeting-notes vault…" : meetingVaultPath)
                .font(Theme.Fonts.meta)
                .foregroundStyle(meetingVaultPath.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url {
                    meetingVaultPath = url.path
                }
            }
            .controlSize(.small)
            Spacer()
            if let summary = agent.lastMeetingSummary {
                Text(summary)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.bottom, 4)
    }

    private var sourceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(vaultPath.isEmpty ? "Choose your knowledge base folder…" : vaultPath)
                .font(Theme.Fonts.meta)
                .foregroundStyle(vaultPath.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url {
                    vaultPath = url.path
                }
            }
            .controlSize(.small)
            Spacer()
            Button {
                Task { await agent.sweep(vaultPath: vaultPath) }
            } label: {
                if agent.isSweeping {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Sweeping…")
                    }
                } else {
                    Label("Sweep", systemImage: "wand.and.stars")
                }
            }
            .disabled(vaultPath.isEmpty || agent.isSweeping)
            .tint(Theme.Palette.accent)

            Menu(autoLabel) {
                Button("Off") { sweepIntervalHours = 0 }
                Button("Every hour") { sweepIntervalHours = 1 }
                Button("Every 4 hours") { sweepIntervalHours = 4 }
                Button("Daily") { sweepIntervalHours = 24 }
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(vaultPath.isEmpty)

            Menu("Trust: \(trust.label)") {
                ForEach(TrustLevel.allCases) { level in
                    Button {
                        trustRaw = level.rawValue
                        Task { await agent.applyTrust(level) }
                    } label: {
                        Text("\(level.label) — \(level.blurb)")
                    }
                }
            }
            .controlSize(.small)
            .fixedSize()
            .help(trust.blurb)
        }
        .padding(.vertical, 10)
    }

    private var autoLabel: String {
        let last = lastSweptAt > 0
            ? " · last " + Date(timeIntervalSince1970: lastSweptAt)
                .formatted(date: .omitted, time: .shortened)
            : ""
        switch sweepIntervalHours {
        case 0: return "Auto: off"
        case 1: return "Auto: hourly" + last
        case 24: return "Auto: daily" + last
        default: return "Auto: \(Int(sweepIntervalHours))h" + last
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textTertiary)
            if count > 0 {
                Text("\(count)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(title == "REVIEW" ? Theme.Palette.done : Theme.Palette.agent)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.meta)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.vertical, 12)
    }
}

/// Rich triage card: collapsed summary that expands into a review drawer
/// (re-bucket, editable draft, comment), with the old tool's outcome verbs.
struct RecommendationRow: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    let rec: Recommendation
    @State private var expanded = false
    @State private var commenting = false
    @State private var commentText = ""

    private var confidenceSegments: Int { Int((rec.confidence * 5).rounded(.down)) }
    private var confidenceColor: Color {
        rec.confidence >= 0.7 ? Theme.Palette.done
            : rec.confidence >= 0.4 ? Color(hex: "#BA7517") : Color(hex: "#D85A30")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            provenanceLine
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.Palette.agent)
                Text(rec.title).font(Theme.Fonts.title).foregroundStyle(Theme.Palette.textPrimary)
                if rec.action.isGated {
                    Label("Always needs you", systemImage: "lock")
                        .labelStyle(.titleAndIcon).font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .help("Email, Slack, and ticket actions are always gated regardless of trust.")
                }
                Spacer()
                Button(expanded ? "Hide" : "Review") {
                    withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.plain).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.accent)
            }

            actionAndConfidence

            if !rec.reasoning.isEmpty {
                (Text("Why · ").foregroundStyle(Theme.Palette.textTertiary)
                    + Text(rec.reasoning).foregroundStyle(Theme.Palette.textSecondary))
                    .font(Theme.Fonts.meta)
                    .lineLimit(expanded ? nil : 1)
            }

            if expanded { drawer }

            outcomes
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var provenanceLine: some View {
        HStack(spacing: 6) {
            Text(rec.source.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            if !rec.sourceContext.isEmpty {
                Text("· \(rec.sourceContext)").font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer()
            if let urlStr = rec.sourceURL, let url = URL(string: urlStr) {
                Link("Open ↗", destination: url).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private var actionAndConfidence: some View {
        HStack(spacing: 8) {
            Text(rec.action.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#534AB7"))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.Palette.agent.opacity(0.14), in: Capsule())
            Spacer()
            Text("confidence").font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary)
            Text(String(format: "%.2f", rec.confidence))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(confidenceColor)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < confidenceSegments ? confidenceColor : Theme.Palette.surface)
                        .frame(width: 16, height: 5)
                }
            }
        }
    }

    @ViewBuilder private var drawer: some View {
        // Re-bucket chips
        VStack(alignment: .leading, spacing: 6) {
            Text("RE-BUCKET").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            FlowChips(selected: rec.action) { rec.action = $0 }
        }
        .padding(.top, 4)

        // Editable draft
        VStack(alignment: .leading, spacing: 6) {
            Text("PROPOSED DRAFT").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            TextEditor(text: Binding(get: { rec.draft }, set: { rec.draft = $0 }))
                .font(Theme.Fonts.meta)
                .frame(minHeight: 70, maxHeight: 160)
                .padding(6)
                .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
        }
        .padding(.top, 6)

        if commenting {
            TextField("Feedback to the agent…", text: $commentText)
                .textFieldStyle(.roundedBorder).font(Theme.Fonts.meta)
                .onSubmit { agent.comment(rec, commentText); commenting = false }
                .padding(.top, 4)
        } else if !rec.comment.isEmpty {
            (Text("Comment · ").foregroundStyle(Theme.Palette.textTertiary)
                + Text(rec.comment).foregroundStyle(Theme.Palette.textSecondary))
                .font(Theme.Fonts.meta).padding(.top, 4)
        }
    }

    private var outcomes: some View {
        HStack(spacing: 8) {
            Button("Approve") { Task { await agent.decide(rec, .approved) } }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.accent)
                .controlSize(.small).disabled(agent.isExecuting)

            if !expanded {
                Button("Review") { withAnimation(.snappy(duration: 0.15)) { expanded = true } }
                    .controlSize(.small)
            } else {
                Button("Comment") { commenting.toggle(); commentText = rec.comment }
                    .controlSize(.small)
            }

            Menu("Snooze") {
                Button("1 hour") { agent.snooze(rec, until: .now.addingTimeInterval(3600)) }
                Button("This evening") { agent.snooze(rec, until: eveningOrSoon()) }
                Button("Tomorrow") { agent.snooze(rec, until: tomorrow9()) }
            }
            .controlSize(.small).fixedSize()

            Button("Schedule") {
                rec.decision = .scheduled
                let task = MustardTask(title: rec.title); task.notes = draftOrBody
                let cal = Calendar.current
                if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) {
                    task.scheduledAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                    task.status = .planned
                }
                context.insert(task)
            }
            .controlSize(.small)

            Button("I'll do it") {
                rec.decision = .selfExecute
                let task = MustardTask(title: rec.title); task.notes = draftOrBody
                context.insert(task)
            }
            .controlSize(.small)

            Spacer()
            Button("Reject", role: .destructive) { rec.decision = .denied }
                .controlSize(.small)
        }
    }

    private var draftOrBody: String { rec.draft.isEmpty ? rec.body : rec.draft }

    private func eveningOrSoon() -> Date {
        let target = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
        return max(target, .now.addingTimeInterval(60))
    }
    private func tomorrow9() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// The re-bucket chip row.
struct FlowChips: View {
    let selected: RecommendationAction
    let onSelect: (RecommendationAction) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(RecommendationAction.allCases) { action in
                let isOn = action == selected
                Button { onSelect(action) } label: {
                    Text(action.label)
                        .font(.system(size: 11))
                        .foregroundStyle(isOn ? Color(hex: "#534AB7") : Theme.Palette.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isOn ? Theme.Palette.agent : Theme.Palette.hairline,
                                        lineWidth: isOn ? 1 : 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OutputCardRow: View {
    @Environment(AgentService.self) private var agent
    let card: OutputCard
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: card.kind == "error" ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(card.kind == "error" ? Color(hex: "#D85A30") : Theme.Palette.done)
                Text(card.recommendation?.title ?? "Output")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text(card.content)
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(expanded ? nil : 3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Accept") { card.review = .accepted }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.done)
                    .controlSize(.small)
                Button("Revise") {
                    card.review = .revised
                    if let rec = card.recommendation {
                        Task { await agent.execute(rec) }
                    }
                }
                .controlSize(.small)
                .disabled(agent.isExecuting)
                Button("Discard", role: .destructive) { card.review = .discarded }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }
}
