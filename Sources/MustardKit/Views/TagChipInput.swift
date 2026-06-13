import SwiftUI

/// Editable tag chips backed by a `[String]` binding. Type + Return adds; ✕ removes.
struct TagChipInput: View {
    @Binding var tags: [String]
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).font(Theme.Fonts.meta)
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.Palette.surface, in: Capsule())
            }
            TextField("+ tag", text: $draft)
                .textFieldStyle(.plain).font(Theme.Fonts.meta)
                .frame(width: 70)
                .onSubmit(add)
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { draft = ""; return }
        tags.append(t)
        draft = ""
    }
}
