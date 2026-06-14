import SwiftUI
import SwiftData

/// Edit/inspect a single task — opened from Today, Board, or Week.
/// Binds directly to the SwiftData model so edits persist live.
public struct TaskDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: MustardTask

    @Query private var allTasks: [MustardTask]
    @Query private var lists: [TaskList]
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var bodyPreview = false

    private static let estimates = [15, 30, 45, 60, 90, 120]

    public init(task: MustardTask) {
        self.task = task
        _isScheduled = State(initialValue: task.scheduledAt != nil)
        _scheduledDate = State(initialValue: task.scheduledAt ?? Self.defaultSlot())
        _hasDue = State(initialValue: task.dueAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Self.defaultSlot())
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

                    VStack(alignment: .leading, spacing: 12) {
                        PropertyRow(label: "Status") {
                            Picker("", selection: $task.status) {
                                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Priority") {
                            Picker("", selection: $task.priority) {
                                ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Assignee") {
                            Picker("", selection: $task.owner) {
                                ForEach(TaskOwner.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().pickerStyle(.segmented).fixedSize()
                        }
                        PropertyRow(label: "Due") {
                            HStack {
                                Toggle("", isOn: $hasDue).labelsHidden().toggleStyle(.switch)
                                    .onChange(of: hasDue) { _, on in task.dueAt = on ? dueDate : nil }
                                if hasDue {
                                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .onChange(of: dueDate) { _, d in task.dueAt = d }
                                }
                            }
                        }
                        PropertyRow(label: "Scheduled") {
                            HStack {
                                Toggle("", isOn: $isScheduled).labelsHidden().toggleStyle(.switch)
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
                        PropertyRow(label: "Estimate") {
                            Picker("", selection: $task.estimateMinutes) {
                                ForEach(Self.estimates, id: \.self) { Text("\($0)m").tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Parent") {
                            ParentPicker(task: task, candidates: allTasks)
                        }
                        PropertyRow(label: "Recurrence") {
                            Picker("", selection: Binding(
                                get: { task.recurrence },
                                set: { task.recurrence = $0 }
                            )) {
                                Text("None").tag(Recurrence?.none)
                                ForEach(Recurrence.allCases) { Text($0.label).tag(Recurrence?.some($0)) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Tags") {
                            TagChipInput(tags: $task.tags)
                        }
                        PropertyRow(label: "Blocked by") {
                            TextField("reason (optional)", text: $task.blockedReason)
                                .textFieldStyle(.plain).font(Theme.Fonts.meta)
                        }
                        PropertyRow(label: "In") {
                            Picker("", selection: $task.list) {
                                Text("None").tag(TaskList?.none)
                                ForEach(lists) { list in
                                    Text(list.name).tag(TaskList?.some(list))
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    .padding(14)
                    .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                    subtasksSection
                    bodySection
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

    private var subtasksSection: some View {
        let progress = task.subtaskProgress
        return VStack(alignment: .leading, spacing: 8) {
            Text("SUBTASKS (\(progress.done)/\(progress.total))")
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            ForEach(task.subtasks ?? []) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.status == .done ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(sub.status == .done ? Theme.Palette.done : Theme.Palette.textTertiary)
                    Text(sub.title).font(Theme.Fonts.meta)
                        .strikethrough(sub.status == .done, color: Theme.Palette.textTertiary)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            Button {
                let child = MustardTask(title: "New subtask")
                child.parent = task
                context.insert(child)
            } label: {
                Label("Add subtask", systemImage: "plus").font(Theme.Fonts.meta)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BODY").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Picker("", selection: $bodyPreview) {
                    Text("edit").tag(false)
                    Text("preview").tag(true)
                }.labelsHidden().pickerStyle(.segmented).fixedSize().controlSize(.small)
            }
            if bodyPreview {
                Text(markdownBody)
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            } else {
                TextEditor(text: $task.notes)
                    .font(Theme.Fonts.body).frame(minHeight: 90, maxHeight: 220).padding(6)
                    .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
            }
        }
    }

    private var markdownBody: AttributedString {
        (try? AttributedString(
            markdown: task.notes,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(task.notes)
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
