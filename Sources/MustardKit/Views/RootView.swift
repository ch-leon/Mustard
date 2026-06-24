import SwiftUI
import SwiftData

public enum MustardScreen: String, CaseIterable, Identifiable {
    case today = "Today"
    case board = "Board"
    case week = "Week"
    case agent = "Agent"
    case lists = "Lists"
    public var id: String { rawValue }

    /// Screens shown as top-level sidebar buttons. `.lists` is intentionally
    /// excluded — it's reached by selecting an area/list/unfiled row below.
    static let primary: [MustardScreen] = [.today, .board, .week, .agent]

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .board: "rectangle.split.3x1"
        case .week: "calendar"
        case .agent: "sparkles"
        case .lists: "tray.full"
        }
    }
}

/// What the Lists screen is showing: a specific list, or the unfiled bucket.
enum ListScope: Equatable {
    case list(TaskList)
    case unfiled

    static func == (lhs: ListScope, rhs: ListScope) -> Bool {
        switch (lhs, rhs) {
        case (.unfiled, .unfiled): return true
        case let (.list(a), .list(b)): return a === b
        default: return false
        }
    }

    var isUnfiled: Bool { if case .unfiled = self { return true }; return false }
    var listValue: TaskList? { if case .list(let l) = self { return l }; return nil }
}

/// Root: a calm fixed sidebar (no toolbar chrome) and the active screen.
public struct RootView: View {
    @State private var screen: MustardScreen = .today
    @State private var selectedScope: ListScope?
    @State private var showCommandBar = false
    @State private var sourcePanel = SourcePanelController()
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
                case .lists: ListContentView(scope: selectedScope ?? .unfiled)
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
            Group {
                // Hidden trigger: ⌘K opens the command bar while the window is key.
                Button("") { showCommandBar.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                // Hidden trigger: ⌘⇧S toggles the source inspector.
                Button("") { sourcePanel.isPresented.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            .opacity(0)
        }
        .inspector(isPresented: $sourcePanel.isPresented) {
            SourcePanelView()
                .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
        }
        .environment(sourcePanel)
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
            ForEach(MustardScreen.primary) { item in
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

            AreaSidebarSection(screen: $screen, selectedScope: $selectedScope)

            Spacer()
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(Theme.Palette.bg)
    }
}
