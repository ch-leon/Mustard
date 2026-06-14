import SwiftUI
import SwiftData

/// The AREAS section of the root sidebar: areas with their nested lists, an
/// area-less group, and an Unfiled bucket. Owns its own queries so counts stay
/// live as tasks change. CRUD is inline (calm — no modal sheets).
struct AreaSidebarSection: View {
    @Environment(\.modelContext) private var context
    @Binding var screen: MustardScreen
    @Binding var selectedScope: ListScope?

    @Query private var areas: [Area]
    @Query private var lists: [TaskList]
    @Query private var tasks: [MustardTask]

    @State private var editingID: PersistentIdentifier?
    @State private var draftName = ""
    @State private var areaPendingDelete: Area?
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(AreaOrganizer.sortedAreas(areas)) { area in
                areaRow(area)
                ForEach(AreaOrganizer.sortedLists(area.lists ?? [])) { list in
                    listRow(list, indented: true)
                }
            }
            ForEach(AreaOrganizer.areaLessLists(lists)) { list in
                listRow(list, indented: false)
            }
            unfiledRow
        }
        .confirmationDialog(
            "Delete area?", isPresented: deleteDialogBinding, presenting: areaPendingDelete
        ) { area in
            Button("Delete area", role: .destructive) { deleteArea(area) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its lists are kept and unfiled from the area.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("AREAS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            Menu {
                Button("New area") { addArea() }
                Button("New list") { addList(into: nil) }
            } label: {
                Image(systemName: "plus").font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.top, 18).padding(.bottom, 4)
    }

    private func areaRow(_ area: Area) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: area.colorHex)).frame(width: 8, height: 8)
            if editingID == area.persistentModelID {
                renameField { area.name = $0 }
            } else {
                Text(area.name.isEmpty ? "Untitled area" : area.name)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            countLabel(AreaOrganizer.openCount(for: area, in: tasks))
            Button { addList(into: area) } label: {
                Image(systemName: "plus").font(.system(size: 9))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .contextMenu {
            Button("Rename") { beginRename(area.persistentModelID, area.name) }
            Button("Add list") { addList(into: area) }
            Button("Delete", role: .destructive) { confirmDeleteArea(area) }
        }
    }

    private func listRow(_ list: TaskList, indented: Bool) -> some View {
        let isSelected = screen == .lists && selectedScope == .list(list)
        return HStack(spacing: 8) {
            if editingID == list.persistentModelID {
                renameField { list.name = $0 }
            } else {
                Text(list.name.isEmpty ? "Untitled list" : list.name)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            countLabel(AreaOrganizer.openCount(for: list, in: tasks))
        }
        .padding(.vertical, 5)
        .padding(.leading, indented ? 26 : 10).padding(.trailing, 10)
        .background(isSelected ? Theme.Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { selectedScope = .list(list); screen = .lists }
        .contextMenu {
            Button("Rename") { beginRename(list.persistentModelID, list.name) }
            Button("Delete", role: .destructive) { deleteList(list) }
        }
    }

    private var unfiledRow: some View {
        let isSelected = screen == .lists && selectedScope == .unfiled
        return HStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 12)).frame(width: 16)
                .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            Text("Unfiled")
                .font(Theme.Fonts.body)
                .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            Spacer()
            countLabel(AreaOrganizer.unfiledCount(tasks))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isSelected ? Theme.Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { selectedScope = .unfiled; screen = .lists }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func countLabel(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)").font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func renameField(commit: @escaping (String) -> Void) -> some View {
        TextField("Name", text: $draftName)
            .textFieldStyle(.plain)
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .focused($renameFocused)
            .onAppear { renameFocused = true }
            .onSubmit {
                let name = draftName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { commit(name) }
                editingID = nil
            }
    }

    // MARK: - Actions

    private func beginRename(_ id: PersistentIdentifier, _ name: String) {
        draftName = name
        editingID = id
    }

    private func addArea() {
        let area = Area(name: "New Area")
        context.insert(area)
        beginRename(area.persistentModelID, area.name)
    }

    private func addList(into area: Area?) {
        let list = TaskList(name: "New List", area: area)
        context.insert(list)
        beginRename(list.persistentModelID, list.name)
    }

    private func deleteList(_ list: TaskList) {
        if selectedScope == .list(list) { selectedScope = .unfiled }
        context.delete(list)
    }

    private func confirmDeleteArea(_ area: Area) {
        if (area.lists ?? []).isEmpty {
            deleteArea(area)
        } else {
            areaPendingDelete = area
        }
    }

    private func deleteArea(_ area: Area) {
        context.delete(area)
        areaPendingDelete = nil
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { areaPendingDelete != nil }, set: { if !$0 { areaPendingDelete = nil } })
    }
}
