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
    private var accent: Color { tab == .agent ? Theme.Palette.agent : Theme.Palette.accent }

    var body: some View {
        TabView(selection: $tab) {
            MobileTodayView(onOpenTriage: { tab = .agent })
                .tag(MobileTab.today)
                .tabItem { Label("Today", systemImage: "sun.max") }

            MobileWeekView(filters: filters)
                .tag(MobileTab.week)
                .tabItem { Label("Week", systemImage: "calendar") }

            MobileBoardView(filters: filters)
                .tag(MobileTab.board)
                .tabItem { Label("Board", systemImage: "rectangle.split.3x1") }

            MobileTriageView()
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
                .background(Theme.Palette.textPrimary, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 68)   // clear the tab bar
    }

    private var comingSoonToast: some View {
        Text("✦ New task — coming soon")
            .font(Theme.Fonts.meta.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.Palette.textPrimary, in: Capsule())
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
