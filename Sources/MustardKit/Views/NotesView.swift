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
    @State private var selected: NoteRef?
    @State private var filter = ""
    @State private var expanded: Set<String> = []

    public init() {}

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

        Text(source.project)
            .font(.system(size: 10, weight: .semibold)).tracking(0.06)
            .foregroundStyle(Theme.Palette.textTertiary)
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
        DisclosureGroup(isExpanded: expansionBinding(for: folder)) {
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
    private func expansionBinding(for folder: NoteTreeFolder) -> Binding<Bool> {
        let filtering = !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Binding(
            get: { filtering || expanded.contains(folder.id) },
            set: { newValue in
                if newValue { expanded.insert(folder.id) } else { expanded.remove(folder.id) }
            }
        )
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

    // MARK: - Detail (placeholder — Task 6 replaces this with the editor)

    @ViewBuilder
    private var detail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 8) {
                Text(title(for: selected))
                    .font(Theme.Fonts.header)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(selected.relativePath)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)
        } else {
            Text("Select a note")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The indexed title for a ref, falling back to the filename stem.
    private func title(for ref: NoteRef) -> String {
        entries.first { $0.project == ref.project && $0.relativePath == ref.relativePath }?.title
            ?? (ref.relativePath as NSString).lastPathComponent
    }
}
