import SwiftUI

/// A labelled property row: small uppercase label on the left, control on the right.
/// Mirrors the predecessor TaskDrawer's PropertyRow within Mustard's calm styling.
struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 92, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
