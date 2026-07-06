import SwiftUI

/// Backlinks panel for the note editor (BAK-151): the notes that link INTO the
/// current one, each with the containing-line snippet recovered from its indexed
/// content. Dumb by design — the host (NoteEditorView) passes the same-project
/// entries; this view only filters, sorts, and renders. Navigation flows back
/// through `onNavigate`, which the host routes through NotesView selection so the
/// editor's save-on-switch fires.
struct BacklinksPanel: View {
    let current: NoteRef
    let entries: [NoteIndexEntry]
    let onNavigate: (NoteRef) -> Void

    @AppStorage("notesBacklinksExpanded") private var expanded = true

    /// Notes whose resolved forwardLinks include the current note, alphabetised by
    /// title (case-insensitive) so the list has a calm, stable order.
    private var linkers: [NoteIndexEntry] {
        entries
            .filter { $0.forwardLinks.contains(current.relativePath) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Theme.Palette.hairline)
            DisclosureGroup(isExpanded: $expanded) {
                content
            } label: {
                Text("Backlinks · \(linkers.count)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if linkers.isEmpty {
            // Centered glyph + line — the calm empty-state pattern (Craft pass Phase 1).
            VStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("No backlinks yet")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            // ONE resolver over the same-project candidate set, shared by every
            // row — hoists the candidate-map build out of the per-row snippet scan.
            let resolve = WikilinkIndex.resolver(paths: entries.map(\.relativePath))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(linkers, id: \.relativePath) { linker in
                        row(linker, resolve: resolve)
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxHeight: 200)
        }
    }

    private func row(_ linker: NoteIndexEntry, resolve: (String) -> String?) -> some View {
        let snippet = BacklinkSnippets.snippet(
            in: linker.contentSnapshot,
            targetPath: current.relativePath,
            resolve: resolve
        )
        return Button {
            onNavigate(NoteRef(project: current.project,
                               workingDirectory: current.workingDirectory,
                               relativePath: linker.relativePath))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(linker.title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
