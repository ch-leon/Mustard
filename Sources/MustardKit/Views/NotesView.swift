import SwiftUI
import SwiftData

/// Identity of one note on disk — the selection currency for the Notes surface.
public struct NoteRef: Equatable, Hashable {
    public let project: String
    public let workingDirectory: String
    public let relativePath: String
    public init(project: String, workingDirectory: String, relativePath: String) {
        self.project = project
        self.workingDirectory = workingDirectory
        self.relativePath = relativePath
    }
}

/// The Notes surface (BAK-149): a project-grouped folder-tree sidebar with a
/// filename/title filter, and a placeholder detail pane (the editor is Task 6).
public struct NotesView: View {
    @Query private var entries: [NoteIndexEntry]
    @Environment(NoteIndexService.self) private var noteIndex
    @State private var selected: NoteRef?
    @State private var filter = ""
    @State private var expanded: Set<String> = []
    @State private var creating: CreateTarget?
    @State private var newNoteTitle = ""

    public init() {}

    /// The project the create sheet is currently targeting. `SourceConfig` isn't
    /// Identifiable, so key `.sheet(item:)` by the project string.
    private struct CreateTarget: Identifiable {
        let config: SourceConfig
        var id: String { config.project }
    }

    /// Enabled sources with a real working directory — the projects we can browse.
    private var sources: [SourceConfig] {
        SourceSettingsStore.loadOrMigrate().sources
            .filter { $0.enabled && !$0.workingDirectory.isEmpty }
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(Theme.Palette.sidebar)
            Divider().overlay(Theme.Palette.hairline)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $creating) { target in
            createNoteSheet(target)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterField
            Divider().overlay(Theme.Palette.hairline)
            if sources.isEmpty {
                emptyState("Add a project in Agent → Sources to browse notes.")
            } else if entries.isEmpty {
                emptyState("No notes indexed yet — ⌘K → Reindex notes now.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sources, id: \.project) { source in
                            projectSection(source)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField("Filter notes", text: $filter)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.Palette.hairline, lineWidth: 0.5)
        )
        .padding(12)
    }

    @ViewBuilder
    private func projectSection(_ source: SourceConfig) -> some View {
        let leaves: [(relativePath: String, title: String)] = entries
            .filter { $0.project == source.project }
            .map { ($0.relativePath, $0.title) }
        let tree = NoteTree.filter(NoteTree.build(leaves), query: filter)

        HStack(spacing: 4) {
            Text(source.project)
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer(minLength: 0)
            Button {
                newNoteTitle = ""
                creating = CreateTarget(config: source)
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("New note in \(source.project)")
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 4)

        folderContents(tree, source: source, depth: 0)
    }

    /// Renders a folder's notes and subfolders (the root folder's own row is not
    /// drawn — its children hang directly under the project header). Returns
    /// `AnyView` to break the folder/leaf mutual recursion, which otherwise makes
    /// the opaque return type reference itself.
    private func folderContents(_ folder: NoteTreeFolder, source: SourceConfig, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 2) {
                ForEach(folder.subfolders) { sub in
                    folderRow(sub, source: source, depth: depth)
                }
                ForEach(folder.notes) { leaf in
                    leafRow(leaf, source: source, depth: depth)
                }
            }
        )
    }

    private func folderRow(_ folder: NoteTreeFolder, source: SourceConfig, depth: Int) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: folder, in: source)) {
            folderContents(folder, source: source, depth: depth + 1)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(Theme.Fonts.meta)
                    .frame(width: 16)
                Text(folder.name)
                    .font(Theme.Fonts.body)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .contentShape(Rectangle())
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    private func leafRow(_ leaf: NoteTreeLeaf, source: SourceConfig, depth: Int) -> some View {
        let ref = NoteRef(project: source.project, workingDirectory: source.workingDirectory,
                          relativePath: leaf.relativePath)
        let isSelected = selected == ref
        return Button {
            selected = ref
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(Theme.Fonts.meta)
                    .frame(width: 16)
                Text(leaf.title)
                    .font(Theme.Fonts.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(depth) * 14)
    }

    /// While a filter query is active, folders are force-expanded (matches are only
    /// useful visible); with no filter they collapse to a calm resting state.
    /// Expansion state is keyed by project-qualified path — `folder.path` is
    /// project-relative, so two projects both containing e.g. `guides/` must not
    /// share one expansion bit.
    private func expansionBinding(for folder: NoteTreeFolder, in source: SourceConfig) -> Binding<Bool> {
        let key = "\(source.project)/\(folder.path)"
        let filtering = NoteTree.isActiveQuery(filter)
        return Binding(
            get: { filtering || expanded.contains(key) },
            set: { newValue in
                if newValue { expanded.insert(key) } else { expanded.remove(key) }
            }
        )
    }

    // MARK: - New note ("+" — BAK-153)

    /// A calm title prompt. An empty title is allowed — it falls back to "Untitled"
    /// via `NoteCreation` (filename and stub heading agree), so Create is never
    /// disabled.
    @ViewBuilder
    private func createNoteSheet(_ target: CreateTarget) -> some View {
        NewNoteSheet(project: target.config.project, title: $newNoteTitle,
                     onCancel: { creating = nil },
                     onCreate: { create(in: target) })
    }

    private func create(in target: CreateTarget) {
        let io = FileVaultIO(rootPath: target.config.workingDirectory)
        let rel = NoteCreation.relativePath(title: newNoteTitle, existing: io.notePaths())
        // write() creates the notes/ folder if absent (FileVaultIO, Task 1). If the
        // write throws (try?), the reindex simply finds nothing new and selection of
        // a missing file shows the editor's calm missing state — acceptable per style.
        try? io.write(rel, NoteCreation.stub(title: newNoteTitle))
        noteIndex.reindex(project: target.config.project, workingDirectory: target.config.workingDirectory)
        // Setting `selected` flushes NoteEditorView's save-on-switch for any open
        // note (desired) and opens the new one.
        selected = NoteRef(project: target.config.project,
                           workingDirectory: target.config.workingDirectory, relativePath: rel)
        newNoteTitle = ""
        creating = nil
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail (the note editor — BAK-150)

    @ViewBuilder
    private var detail: some View {
        if let selected {
            NoteEditorView(
                ref: selected,
                entries: entries.filter { $0.project == selected.project },
                onNavigate: { self.selected = $0 }
            )
        } else {
            Text("Select a note")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The calm "New note" prompt (BAK-153). Kept a small dedicated view so `@FocusState`
/// autofocuses the field on present; return submits, Escape/Cancel dismisses.
private struct NewNoteSheet: View {
    let project: String
    @Binding var title: String
    let onCancel: () -> Void
    let onCreate: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New note in \(project)")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            TextField("Note title", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($focused)
                .onSubmit(onCreate)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.Palette.hairline, lineWidth: 0.5)
                )
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.Palette.surface)
        .onAppear { focused = true }
    }
}
