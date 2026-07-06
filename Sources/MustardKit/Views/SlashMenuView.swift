import SwiftUI

/// The caret-anchored "/" command menu (Craft spec, 2b Task 7). Pure render +
/// dispatch: rows come from `SlashMenu.items(query:)`, the keyboard selection is
/// owned by the text-view coordinator (which intercepts ↑/↓/⏎ while open), and a
/// click routes the command back through `onPick` → `MarkdownEditorProxy` → the
/// one undo-safe insertion path.
struct SlashMenuView: View {
    let query: String
    let selectedIndex: Int
    let onPick: (SlashCommand) -> Void

    private static let menuWidth: CGFloat = 240

    var body: some View {
        let items = SlashMenu.items(query: query)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, command in
                row(command, isSelected: index == min(selectedIndex, items.count - 1))
            }
        }
        .padding(6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .elevation(.pop, cornerRadius: Theme.Metrics.rXl)
    }

    private func row(_ command: SlashCommand, isSelected: Bool) -> some View {
        Button {
            onPick(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.icon)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 18)
                Text(command.title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.Palette.navActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.rMd))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
