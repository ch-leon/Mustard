import SwiftUI
import SwiftData

/// Mobile Triage tab — the pending-recommendation queue. This interim LIST presentation
/// gives the BAK-115 detail sheet a home and makes Today's "Agent has N for you" nudge
/// land somewhere real; BAK-119 upgrades it to the Tinder-style swipe deck (tap → this
/// same MobileRecommendationSheet for full triage). Uses the tested RecommendationQueue
/// so snooze/ignore rules stay in one place.
struct MobileTriageView: View {
    @Query private var recommendations: [Recommendation]
    @State private var selected: Recommendation?

    private var pending: [Recommendation] {
        RecommendationQueue.pending(recommendations, now: .now)
            .sorted { $0.confidence > $1.confidence }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if pending.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(Color(hex: "#1D9E75"))
                            Text("All clear").font(.headline)
                            Text("Nothing waiting on you.").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        ForEach(pending) { rec in card(rec) }
                    }
                }
                .padding()
            }
            .navigationTitle("Triage")
            .sheet(item: $selected) { MobileRecommendationSheet(rec: $0) }
        }
    }

    /// Tappable rec card — .contentShape+.onTapGesture (no nested Buttons here, but keep
    /// the established mobile pattern so a future inline action can't double-fire).
    private func card(_ rec: Recommendation) -> some View {
        let badge = SourceBadge.badge(forRaw: rec.source)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !badge.isQuiet {
                    Label(badge.label, systemImage: badge.symbol)
                        .labelStyle(.titleAndIcon).font(.caption2.weight(.medium))
                        .foregroundStyle(Color(hex: badge.fgHex))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: badge.bgHex), in: Capsule())
                }
                Text("✦ \(rec.action.label)").font(.caption2.weight(.medium)).foregroundStyle(Color(hex: "#534AB7"))
                Spacer(minLength: 0)
                if rec.action.isGated { Image(systemName: "lock").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(rec.title).font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !rec.reasoning.isEmpty {
                Text(rec.reasoning).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(String(format: "%.2f", rec.confidence))
                    .font(.caption2.weight(.medium)).foregroundStyle(Theme.confidenceColor(rec.confidence))
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < Int((rec.confidence * 5).rounded(.down)) ? Theme.confidenceColor(rec.confidence) : Color(hex: "#E4DFD5"))
                            .frame(width: 14, height: 4)
                    }
                }
                Spacer(minLength: 0)
                Text("Review").font(.caption2.weight(.semibold)).foregroundStyle(Color(hex: "#6A61C9"))
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(Color(hex: "#FBFAF7"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#E7E3DA"), lineWidth: 0.5))
        .overlay(alignment: .leading) { Color(hex: "#7F77DD").frame(width: 2.5).clipShape(Capsule()) }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { selected = rec }
    }
}
