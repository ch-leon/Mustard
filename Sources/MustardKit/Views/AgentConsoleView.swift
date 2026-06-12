import SwiftUI
import SwiftData
import AppKit

/// The agent console: vault source row, Recommendations queue (decide),
/// Review queue (accept/revise/discard). Things-3-calm throughout.
public struct AgentConsoleView: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    @AppStorage("vaultPath") private var vaultPath = ""
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @Query(sort: \OutputCard.createdAt, order: .reverse) private var cards: [OutputCard]

    public init() {}

    private var pending: [Recommendation] {
        recommendations.filter { $0.decision == .pending }
    }

    private var reviewQueue: [OutputCard] {
        cards.filter { $0.review == .pending }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                sourceRow
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
        }
        .padding(.vertical, 10)
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

struct RecommendationRow: View {
    @Environment(\.modelContext) private var context
    @Environment(AgentService.self) private var agent
    let rec: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.agent)
                Text(rec.title)
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            if !rec.body.isEmpty {
                Text(rec.body)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button("Approve") {
                    Task { await agent.decide(rec, .approved) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
                .controlSize(.small)
                .disabled(agent.isExecuting)

                Button("Schedule") {
                    rec.decision = .scheduled
                    let task = MustardTask(title: rec.title)
                    task.notes = rec.body
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
                    let task = MustardTask(title: rec.title)
                    task.notes = rec.body
                    context.insert(task)
                }
                .controlSize(.small)

                Button("Deny", role: .destructive) {
                    rec.decision = .denied
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
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
