import SwiftUI
import SwiftData

/// Pick a parent task by title. Filters out the task itself and any choice that
/// would create a cycle (TaskHierarchy). Clearing sets parent = nil.
struct ParentPicker: View {
    @Bindable var task: MustardTask
    let candidates: [MustardTask]
    @State private var query = ""

    private var matches: [MustardTask] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return candidates.filter { other in
            other !== task
                && other.title.localizedCaseInsensitiveContains(q)
                && !TaskHierarchy.wouldCreateCycle(assigning: other, to: task)
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let parent = task.parent {
                HStack(spacing: 6) {
                    Text(parent.title).font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button { task.parent = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                TextField("search by title…", text: $query)
                    .textFieldStyle(.plain).font(Theme.Fonts.meta)
                ForEach(matches) { match in
                    Button {
                        task.parent = match
                        query = ""
                    } label: {
                        Text(match.title).font(Theme.Fonts.meta)
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
