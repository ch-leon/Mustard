import SwiftUI
import SwiftData

public enum MustardScreen: String, CaseIterable, Identifiable {
    case today = "Today"
    case board = "Board"
    case week = "Week"
    case agent = "Agent"
    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .board: "rectangle.split.3x1"
        case .week: "calendar"
        case .agent: "sparkles"
        }
    }
}

/// Root: a calm fixed sidebar (no toolbar chrome) and the active screen.
public struct RootView: View {
    @State private var screen: MustardScreen = .today
    @State private var showCommandBar = false
    @Query private var cards: [OutputCard]
    @Query private var recommendations: [Recommendation]

    public init() {}

    private var waitingCount: Int {
        recommendations.filter { $0.decision == .pending }.count
            + cards.filter { $0.review == .pending }.count
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.Palette.hairline)
            Group {
                switch screen {
                case .today: TodayView()
                case .board: BoardView()
                case .week: WeekView()
                case .agent: AgentConsoleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Palette.bg)
        .overlay {
            if showCommandBar {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandBar = false }
                    CommandBarView(isPresented: $showCommandBar, screen: $screen)
                        .padding(.top, 90)
                }
            }
        }
        .background {
            // Hidden trigger: ⌘K opens the command bar while the window is key.
            Button("") { showCommandBar.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
        // Locked light design (ADR-0005); pin appearance so native controls
        // (TextEditor, DatePicker, pickers) don't render dark under macOS dark mode.
        // The notch is a separate panel with its own explicit dark colors — unaffected.
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mustard")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.bottom, 16)
            ForEach(MustardScreen.allCases) { item in
                Button {
                    screen = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 13))
                            .frame(width: 16)
                        Text(item.rawValue)
                            .font(Theme.Fonts.body)
                        Spacer()
                        if item == .agent && waitingCount > 0 {
                            Text("\(waitingCount)")
                                .font(Theme.Fonts.meta)
                                .foregroundStyle(Theme.Palette.agent)
                        }
                    }
                    .foregroundStyle(screen == item ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        screen == item ? Theme.Palette.surface : .clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(Theme.Palette.bg)
    }
}
