import SwiftUI
import SwiftData

/// "Blocked by" picker (BAK-107): search a task by title to set as this task's
/// dependency. Excludes self and already-done tasks. (A task with an unfinished
/// `blockedByTask` reads as blocked; `isBlocked` only looks one level deep, so a
/// mutual A↔B dependency can't recurse.)
struct BlockedByPicker: View {
    @Bindable var task: MustardTask
    let candidates: [MustardTask]
    @State private var query = ""

    private var matches: [MustardTask] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return candidates.filter { other in
            other !== task
                && other.stage != .done
                && other.title.localizedCaseInsensitiveContains(q)
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let blocker = task.blockedByTask {
                HStack(spacing: 6) {
                    Text(blocker.title).font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button { task.blockedByTask = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                TextField("search by title…", text: $query)
                    .textFieldStyle(.plain).font(Theme.Fonts.meta)
                ForEach(matches) { match in
                    Button {
                        task.blockedByTask = match
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
