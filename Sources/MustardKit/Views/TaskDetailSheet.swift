import SwiftUI
import SwiftData

/// Edit/inspect a single task — opened from Today, Board, or Week.
/// Binds directly to the SwiftData model so edits persist live.
public struct TaskDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: MustardTask

    @State private var isScheduled: Bool
    @State private var scheduledDate: Date

    private static let estimates = [15, 30, 45, 60, 90, 120]

    public init(task: MustardTask) {
        self.task = task
        _isScheduled = State(initialValue: task.scheduledAt != nil)
        _scheduledDate = State(initialValue: task.scheduledAt ?? Self.defaultSlot())
    }

    private static func defaultSlot() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.Palette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Title") {
                        TextField("Title", text: $task.title)
                            .textFieldStyle(.plain).font(Theme.Fonts.title)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    field("Notes") {
                        TextEditor(text: $task.notes)
                            .font(Theme.Fonts.body).frame(minHeight: 90, maxHeight: 200)
                            .padding(6)
                            .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
                    }
                    HStack(alignment: .top, spacing: 24) {
                        field("Status") {
                            Picker("", selection: $task.status) {
                                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        field("Owner") {
                            Picker("", selection: $task.owner) {
                                ForEach(TaskOwner.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).fixedSize()
                        }
                        field("Estimate") {
                            Picker("", selection: $task.estimateMinutes) {
                                ForEach(Self.estimates, id: \.self) { Text("\($0)m").tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    field("Schedule") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Scheduled", isOn: $isScheduled)
                                .toggleStyle(.switch).font(Theme.Fonts.meta)
                                .onChange(of: isScheduled) { _, on in
                                    task.scheduledAt = on ? scheduledDate : nil
                                    if on, task.status == .inbox { task.status = .planned }
                                }
                            if isScheduled {
                                DatePicker("", selection: $scheduledDate)
                                    .labelsHidden()
                                    .onChange(of: scheduledDate) { _, d in task.scheduledAt = d }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider().overlay(Theme.Palette.hairline)
            footer
        }
        .frame(width: 460, height: 560)
        .background(Theme.Palette.bg)
    }

    private var header: some View {
        HStack {
            Text("Task").font(Theme.Fonts.header).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button("Done") { dismiss() }.controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                context.delete(task)
                dismiss()
            } label: {
                Label("Delete task", systemImage: "trash")
            }
            .controlSize(.small)
            Spacer()
            if task.status != .done {
                Button("Mark done") { TaskCompletion.complete(task, in: context); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Theme.Palette.done).controlSize(.small)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            content()
        }
    }
}
