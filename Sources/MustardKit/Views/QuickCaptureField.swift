import SwiftUI
import SwiftData

public struct QuickCaptureField: View {
    @Environment(\.modelContext) private var context
    /// When set, captured tasks are scheduled onto this day at 9:00.
    var scheduleOnto: Date?
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(scheduleOnto: Date? = nil) {
        self.scheduleOnto = scheduleOnto
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: capture) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            TextField("Add a task…", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($focused)
                .onSubmit(capture)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func capture() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { focused = true; return }
        let task = MustardTask(title: trimmed)
        if let day = scheduleOnto {
            task.scheduledAt = Calendar.current.date(
                bySettingHour: 9, minute: 0, second: 0, of: day)
            task.status = .planned
        }
        context.insert(task)
        text = ""
        focused = true
    }
}
