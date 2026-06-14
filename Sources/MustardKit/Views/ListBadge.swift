import SwiftUI

/// Small, calm pill showing a task's list: the area's color dot + list name.
/// Tertiary so it sits quietly in a row's meta line.
struct ListBadge: View {
    let list: TaskList

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: list.area?.colorHex ?? "#B0ACA1"))
                .frame(width: 6, height: 6)
            Text(list.name.isEmpty ? "Untitled list" : list.name)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}
