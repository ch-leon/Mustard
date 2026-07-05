import SwiftUI

/// Raw-markdown note editor for the Notes surface (BAK-150): a plain monospaced
/// Source editor with a Preview toggle, a dirty indicator, and a snapshot-guarded
/// save to the vault. Syntax highlighting is out of scope (Phase C) — Source is a
/// plain `TextEditor`.
///
/// `onNavigate` is accepted now for Task 9 (wikilink navigation) but not yet called.
struct NoteEditorView: View {
    let ref: NoteRef
    let onNavigate: (NoteRef) -> Void

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
            } else if mode == .source {
                sourceEditor
            } else {
                MarkdownPreviewView(
                    content: Frontmatter.parse(text).body,
                    resolve: { _ in nil },          // real resolver arrives in Task 9
                    onWikilinkTap: { _ in }         // navigation arrives in Task 9
                )
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
            .disabled(loadFailed)
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

    /// frontmatter title → first `# ` heading → filename stem.
    private var noteTitle: String {
        if let fmTitle = Frontmatter.parse(text).title, !fmTitle.isEmpty {
            return fmTitle
        }
        if let heading = firstHeading(Frontmatter.parse(text).body) {
            return heading
        }
        return ((ref.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func firstHeading(_ body: String) -> String? {
        for block in MarkdownBlocks.parse(body) {
            if case let .heading(_, runs) = block {
                let text = runs.map { run -> String in
                    switch run {
                    case let .text(s): return s
                    case let .wikilink(target, alias): return alias ?? target
                    }
                }.joined()
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
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
        if let prior = io.read(ref.relativePath) { try? io.snapshot(ref.relativePath, prior) }
        try? io.write(ref.relativePath, content)
        // Only advance the in-view baseline when saving the note still on screen;
        // a save-on-switch targets the OLD ref while state already holds the new one.
        if ref == self.ref { diskText = content }
        noteIndex.reindex(project: ref.project, workingDirectory: ref.workingDirectory)
    }
}
