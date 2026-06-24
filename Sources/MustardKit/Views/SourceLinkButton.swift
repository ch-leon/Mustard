import SwiftUI
import AppKit

/// A compact source-glyph button that opens the item's source in the inspector.
/// Renders nothing when the item has no openable (http/https) source.
struct SourceLinkButton: View {
    let link: SourceLink?

    init(rec: Recommendation) { link = SourceLink(from: rec) }
    init(task: MustardTask) { link = SourceLink(from: task) }
    init(card: OutputCard) { link = SourceLink(from: card) }

    var body: some View {
        if let link { SourceLinkButtonInner(link: link) }
    }
}

private struct SourceLinkButtonInner: View {
    @Environment(SourcePanelController.self) private var panel
    @Environment(\.openURL) private var openURL
    let link: SourceLink

    var body: some View {
        Button { panel.open(link) } label: {
            Image(systemName: link.symbol).font(.system(size: 12))
                .foregroundStyle(Theme.Palette.agent)
        }
        .buttonStyle(.plain)
        .help("Open source in panel — \(link.sourceName)")
        .contextMenu {
            Button("Open in panel") { panel.open(link) }
            Button("Open in browser") { openURL(link.url) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            }
        }
    }
}
