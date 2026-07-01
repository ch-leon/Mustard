import SwiftUI
import SwiftData

/// The four mobile tabs, in the handoff's mobile order (Today · Week · Board · Agent —
/// note this differs from the desktop sidebar order).
enum MobileTab: Hashable { case today, week, board, agent }

/// Owner + area filters shared across Board and Week (one instance — changing it on one
/// screen affects the other, per the handoff). A reference type so both screens mutate
/// the same state. The real screens (BAK-114/116) read/write this.
@Observable final class MobileFilters {
    var owner: BoardOwnerView = .everyone
    var area: BoardArea = .all
}

/// Bottom-tab shell (BAK-110). Agent-tab badge = pending triage count; a FAB on Today
/// and Board (create form is desktop-only, so it flashes "coming soon").
struct MobileRootView: View {
    @Query private var recommendations: [Recommendation]
    @State private var tab: MobileTab = .today
    @State private var filters = MobileFilters()
    @State private var comingSoon = false

    private var triageCount: Int { AgentInbox.pendingRecCount(recommendations) }
    private var accent: Color { tab == .agent ? Color(hex: "#7F77DD") : Color(hex: "#2D7FF9") }

    var body: some View {
        TabView(selection: $tab) {
            MobileScreenStub(title: "Today", note: "Timeline, progress + nudge — BAK-113")
                .tag(MobileTab.today)
                .tabItem { Label("Today", systemImage: "sun.max") }

            MobileScreenStub(title: "Week", note: "Day-strip + capacity — BAK-116", filters: filters)
                .tag(MobileTab.week)
                .tabItem { Label("Week", systemImage: "calendar") }

            MobileScreenStub(title: "Board", note: "Stacked sections + gate actions — BAK-114", filters: filters)
                .tag(MobileTab.board)
                .tabItem { Label("Board", systemImage: "rectangle.split.3x1") }

            MobileScreenStub(title: "Triage", note: "Swipe deck — BAK-119")
                .tag(MobileTab.agent)
                .tabItem { Label("Agent", systemImage: "sparkles") }
                .badge(triageCount)
        }
        .tint(accent)
        .overlay(alignment: .bottomTrailing) {
            if tab == .today || tab == .board { fab }
        }
        .overlay(alignment: .top) {
            if comingSoon { comingSoonToast }
        }
        .animation(.easeInOut(duration: 0.2), value: comingSoon)
        // Auto-dismiss lives on the always-present TabView so switching tabs mid-toast
        // still clears it.
        .task(id: comingSoon) {
            guard comingSoon else { return }
            try? await Task.sleep(for: .seconds(2.6))
            comingSoon = false
        }
    }

    private var fab: some View {
        Button {
            comingSoon = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color(hex: "#2B2A26"), in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 68)   // clear the tab bar
    }

    private var comingSoonToast: some View {
        Text("✦ New task — coming soon")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(hex: "#2B2A26"), in: Capsule())
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Placeholder tab content until the real screens land. Board/Week take the shared
/// filters so the wiring is exercised now.
private struct MobileScreenStub: View {
    let title: String
    let note: String
    var filters: MobileFilters?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36)).foregroundStyle(Color(hex: "#7F77DD"))
            Text(title).font(.largeTitle.bold())
            Text(note).font(.footnote).foregroundStyle(.secondary)
            if let filters {
                Text("Filters — owner: \(filters.owner.label) · area: \(areaLabel(filters.area))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func areaLabel(_ a: BoardArea) -> String {
        switch a {
        case .all: "All"
        case .area(let n): n
        case .personal: "Personal"
        }
    }
}
