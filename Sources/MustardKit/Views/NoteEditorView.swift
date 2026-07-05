import SwiftUI

/// Raw-markdown note editor for the Notes surface (BAK-150): a plain monospaced
/// Source editor with a Preview toggle, a dirty indicator, and a snapshot-guarded
/// save to the vault. Syntax highlighting is out of scope (Phase C) — Source is a
/// plain `TextEditor`.
///
/// `onNavigate` routes backlink-row taps back through NotesView selection (so the
/// editor's save-on-switch fires). `resolveWikilink`/`onWikilinkTap` (Task 9) wire
/// the preview's `[[wikilinks]]` — the former colours resolved vs dangling links,
/// the latter navigates on tap (or offers create-from-unresolved in the host).
struct NoteEditorView: View {
    let ref: NoteRef
    /// Same-project index entries, passed by NotesView — the backlinks panel reads
    /// these (which notes link here) rather than @Querying independently.
    let entries: [NoteIndexEntry]
    let onNavigate: (NoteRef) -> Void
    /// Resolves a wikilink target to a same-project note (nil when it dangles) —
    /// drives the preview's link colour. Built once per NotesView body evaluation.
    let resolveWikilink: (String) -> NoteRef?
    /// Handles a wikilink tap in the preview: navigate to the target, or offer to
    /// create it when unresolved. NotesView owns the decision.
    let onWikilinkTap: (String) -> Void

    @Environment(NoteIndexService.self) private var noteIndex

    @State private var text = ""
    @State private var diskText = ""      // content at load — the dirty-check baseline
    @State private var mode: EditorMode = .source
    @State private var loadFailed = false

    private enum EditorMode { case source, preview }

    private var isDirty: Bool { text != diskText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.Palette.hairline)
            if loadFailed {
                missingState
            } else {
                if mode == .source {
                    sourceEditor
                } else {
                    MarkdownPreviewView(
                        content: Frontmatter.parse(text).body,
                        resolve: resolveWikilink,
                        onWikilinkTap: onWikilinkTap
                    )
                }
                BacklinksPanel(current: ref, entries: entries, onNavigate: onNavigate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.bg)
        // Save the OLD note before the ref-keyed .task reloads: onChange(old,new)
        // fires while state still holds the old note's text, so we can flush edits
        // that would otherwise be dropped when switching notes.
        .onChange(of: ref) { oldRef, _ in
            save(to: oldRef, content: text, ifDifferentFrom: diskText)
        }
        .task(id: ref) {
            let io = FileVaultIO(rootPath: ref.workingDirectory)
            if let loaded = io.read(ref.relativePath) {
                text = loaded
                diskText = loaded
                loadFailed = false
            } else {
                text = ""
                diskText = ""
                loadFailed = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(noteTitle)
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            if isDirty {
                Circle()
                    .fill(Theme.Palette.warning)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 12)

            Picker("", selection: $mode) {
                Text("Source").tag(EditorMode.source)
                Text("Preview").tag(EditorMode.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)

            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Source editor

    private var sourceEditor: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.bg)
            .autocorrectionDisabled()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private var missingState: some View {
        VStack {
            Spacer()
            Text("This note is missing from disk.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Title derivation

    /// frontmatter title → first `#{1,6} ` heading → filename stem. Recomputed per
    /// keystroke (text is @State, read by the header), so it parses frontmatter ONCE
    /// and scans lines directly rather than running the full block parser.
    private var noteTitle: String {
        let parsed = Frontmatter.parse(text)
        if let fmTitle = parsed.title, !fmTitle.isEmpty {
            return fmTitle
        }
        if let heading = firstHeading(parsed.body) {
            return heading
        }
        return ((ref.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Cheap early-exit scan for the first `#{1,6} ` line. Deliberately does NOT
    /// skip code fences — a fenced `# comment` before any real heading is a
    /// vanishingly rare title position, not worth a full parse per keystroke.
    private func firstHeading(_ body: String) -> String? {
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard hashes >= 1, hashes <= 6 else { continue }
            let rest = trimmed.dropFirst(hashes)
            guard rest.hasPrefix(" ") else { continue }
            let title = rest.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }

    // MARK: - Save

    private func save() {
        save(to: ref, content: text, ifDifferentFrom: diskText)
    }

    /// Snapshot-before-save (spec addendum #5), then write and reindex. Guarded by a
    /// dirty check so switching between clean notes never rewrites disk.
    private func save(to ref: NoteRef, content: String, ifDifferentFrom baseline: String) {
        guard content != baseline else { return }
        let io = FileVaultIO(rootPath: ref.workingDirectory)
        // Snapshot is belt-and-braces — a failed snapshot must not block the save.
        if let prior = io.read(ref.relativePath) { try? io.snapshot(ref.relativePath, prior) }
        // Failed write must stay dirty — the dot is the only honesty signal.
        do { try io.write(ref.relativePath, content) } catch { return }
        // Only advance the in-view baseline when saving the note still on screen;
        // a save-on-switch targets the OLD ref while state already holds the new one.
        if ref == self.ref { diskText = content }
        noteIndex.reindex(project: ref.project, workingDirectory: ref.workingDirectory)
    }
}
