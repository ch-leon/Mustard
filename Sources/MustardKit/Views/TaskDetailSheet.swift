import SwiftUI
import SwiftData

/// Edit/inspect a single task — opened from Today, Board, or Week.
/// Binds directly to the SwiftData model so edits persist live.
public struct TaskDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AgentService.self) private var agent
    @Bindable var task: MustardTask
    @Query private var areas: [Area]
    @Query private var lists: [TaskList]
    @Query private var allTasks: [MustardTask]
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var bodyPreview = false
    @State private var newLinkURL = ""
    /// BAK-95: inline feedback when a hand-off is blocked because the task has no area.
    @State private var gateHint: String?

    /// The Stage/Assignee pickers can hand a task to the agent, but the bridge routes by
    /// area — so, like the "Ask agent" buttons, block a hand-off on an area-less task.
    private static let handOffMessage = "Give this task a List (client area) before handing it to the agent — the bridge routes agent work by area."
    private func gateHandOff() -> Bool {
        guard !PersonalBoard.canHandOffToAgent(task) else { gateHint = nil; return true }
        gateHint = Self.handOffMessage
        return false
    }

    private static let estimates = [15, 30, 45, 60, 90, 120]
    /// Actions the agent can execute for a queued task (excludes create_task/fyi/ignore,
    /// which aren't agent-execute outcomes). Offered in the Action picker.
    private static let agentActions: [RecommendationAction] = [.draftEmail, .draftSlack, .ticket, .vaultNote]

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

                    agentContext

                    VStack(alignment: .leading, spacing: 12) {
                        PropertyRow(label: "Stage") {
                            Picker("", selection: Binding(
                                get: { task.stage },
                                set: { newStage in
                                    // Moving into an agent lane is a hand-off — gate it.
                                    // Same four stages the board drop guard treats as agent.
                                    let agentLanes: [TaskStage] = [.forAgent, .needsApproval, .queued, .needsReview]
                                    if agentLanes.contains(newStage), !gateHandOff() { return }
                                    task.stage = newStage
                                }
                            )) {
                                ForEach(TaskStage.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Priority") {
                            Picker("", selection: $task.priority) {
                                ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Assignee") {
                            Picker("", selection: Binding(
                                get: { task.owner },
                                set: { newOwner in
                                    if newOwner == .agent, !gateHandOff() { return }
                                    task.owner = newOwner
                                }
                            )) {
                                ForEach(TaskOwner.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().pickerStyle(.segmented).fixedSize()
                                .tint(task.owner == .agent ? Theme.Palette.agent : Theme.Palette.accent)
                        }
                        if let gateHint {
                            HStack(spacing: 6) {
                                Image(systemName: "lock").font(.system(size: 11))
                                Text(gateHint).font(Theme.Fonts.meta)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.Palette.warnText)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        PropertyRow(label: "Action") {
                            // What the agent does when it executes this task. A queued
                            // task must have one set or the bridge can't route it (BAK-89).
                            Picker("", selection: Binding(
                                get: { task.actionType },
                                set: { task.actionType = $0 }
                            )) {
                                Text("None").tag(RecommendationAction?.none)
                                ForEach(Self.agentActions) { Text($0.label).tag(RecommendationAction?.some($0)) }
                            }.labelsHidden().fixedSize()
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
                                        task.isTimed = on
                                        if on, task.stage == .inbox { task.stage = .planned }
                                    }
                                if isScheduled {
                                    // Picking a specific time anchors the task to the week's time axis.
                                    DatePicker("", selection: $scheduledDate)
                                        .labelsHidden()
                                        .onChange(of: scheduledDate) { _, d in
                                            task.scheduledAt = d
                                            task.isTimed = true
                                        }
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
                        PropertyRow(label: "Blocked by") {
                            BlockedByPicker(task: task, candidates: allTasks)
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
                                ForEach(AreaOrganizer.sortedAreas(areas)) { area in
                                    Section(area.name.isEmpty ? "Untitled area" : area.name) {
                                        ForEach(AreaOrganizer.sortedLists(area.lists ?? [])) { list in
                                            Text(list.name.isEmpty ? "Untitled list" : list.name)
                                                .tag(TaskList?.some(list))
                                        }
                                    }
                                }
                                let loose = AreaOrganizer.areaLessLists(lists)
                                if !loose.isEmpty {
                                    Section("No area") {
                                        ForEach(loose) { list in
                                            Text(list.name.isEmpty ? "Untitled list" : list.name)
                                                .tag(TaskList?.some(list))
                                        }
                                    }
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    .padding(14)
                    .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                    subtasksSection
                    linksSection
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
            SourceLinkButton(task: task)
            Button("Done") { dismiss() }.controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // Stage-adaptive footer (BAK-136): Delete stays leading (this sheet is also the
    // editor); the stage-specific matrix sits trailing. Forward gate actions reuse
    // PersonalBoard.approveTarget/move — no forked state machine.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                context.delete(task); dismiss()
            } label: { Label("Delete task", systemImage: "trash") }
            .controlSize(.small)
            Spacer()
            stageActions
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var stageActions: some View {
        switch task.stage {
        case .needsApproval:
            Button("I'll do it") { takeOver() }.controlSize(.small)
            Button("Deny", role: .destructive) { context.delete(task); dismiss() }.controlSize(.small)
            Button(task.isGated ? "Approve & run" : "Approve") { approveGate() }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.agent).controlSize(.small)
        case .needsReview:
            Button("Request changes") { PersonalBoard.move(task, to: .queued) }.controlSize(.small)
            Button("Discard", role: .destructive) { context.delete(task); dismiss() }.controlSize(.small)
            Button("Accept output") { TaskCompletion.complete(task, in: context); dismiss() }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.done).controlSize(.small)
        case .queued:
            Button("Hold") { PersonalBoard.move(task, to: .needsApproval) }.controlSize(.small)
            Button("Move to review") { PersonalBoard.move(task, to: .needsReview) }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.agent).controlSize(.small)
        case .forAgent:
            Button("Take back") { takeOver() }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.accent).controlSize(.small)
        case .inbox where task.isProposed:
            Button("I'll do it") { takeOver() }.controlSize(.small)
            Button("Schedule") { scheduleTomorrow() }.controlSize(.small)
            Button("Dismiss", role: .destructive) { context.delete(task); dismiss() }.controlSize(.small)
            Button("Approve") { PersonalBoard.move(task, to: .needsApproval) }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.agent).controlSize(.small)
        case .done:
            EmptyView()
        default:
            // Your own open tasks (inbox/planned/scheduled/inProgress/blocked).
            if task.owner == .me && task.delegation == nil {
                Button { agent.delegate(task) } label: { Label("Hand to ✦ agent", systemImage: "cpu") }
                    .tint(Theme.Palette.agent).controlSize(.small)
                    .help("Hand this task to the agent — it proposes how to do it, then runs per your trust level.")
            }
            Button("Mark done") { TaskCompletion.complete(task, in: context); dismiss() }
                .buttonStyle(.borderedProminent).tint(Theme.Palette.done).controlSize(.small)
        }
    }

    /// Take a task back to yourself as planned work.
    private func takeOver() {
        task.owner = .me
        if task.stage.isOpen { task.stage = .planned }
    }

    /// Approve a gate using the shared state machine (needsApproval → queued/needsReview).
    private func approveGate() {
        if let target = PersonalBoard.approveTarget(for: task) { PersonalBoard.move(task, to: target) }
    }

    /// Schedule a proposed task for tomorrow 9am as your own planned/scheduled work.
    private func scheduleTomorrow() {
        task.owner = .me
        let cal = Calendar.current
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) {
            task.scheduledAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
        task.isTimed = false
        task.stage = .scheduled
    }

    // Links referenced by the task (BAK-91) — e.g. a Shortcut story / Jira issue carried
    // from a create_task rec, or one added by hand. Show, open, remove, add.
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINKS")
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            ForEach(task.links, id: \.url) { link in
                HStack(spacing: 8) {
                    Button {
                        if let u = URL(string: link.url) { openURL(u) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.system(size: 11))
                            Text(link.label).font(Theme.Fonts.meta)
                            Text(link.url).font(Theme.Fonts.meta)
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.accent)
                    Spacer(minLength: 0)
                    Button { task.links.removeAll { $0.url == link.url } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                    .help("Remove link")
                }
            }
            HStack(spacing: 6) {
                TextField("Add a link (URL)…", text: $newLinkURL)
                    .textFieldStyle(.plain).font(Theme.Fonts.meta).onSubmit(addLink)
                Button(action: addLink) {
                    Image(systemName: "plus").font(Theme.Fonts.meta)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Append a manually-entered link (http/https only), de-duplicated, labelled by host.
    private func addLink() {
        let trimmed = newLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        defer { newLinkURL = "" }
        guard !task.links.contains(where: { $0.url == trimmed }) else { return }
        task.links.append(TaskLink(label: TaskLinkExtractor.label(for: url), url: trimmed))
    }

    /// Read-only agent-context (BAK-137): the approval-panel info — stage badge, gated
    /// notice, confidence, WHY, and the proposed draft — surfaced when the task carries
    /// agent context. (No separate read/edit mode: the sheet shows context + remains editable.)
    @ViewBuilder private var agentContext: some View {
        let conf = task.confidence
        let why = task.delegation?.reasoning ?? ""
        let draft = task.delegation?.draft ?? ""
        if conf != nil || !why.isEmpty || !draft.isEmpty || task.isGated {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(task.stage.label.uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                        .foregroundStyle(stageBadgeColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(stageBadgeColor.opacity(0.14), in: Capsule())
                    Spacer()
                }
                if task.isGated {
                    HStack(spacing: 6) {
                        Image(systemName: "lock").font(.system(size: 11))
                        Text("Gated action — always reviewed by you, whatever the trust level.")
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.Palette.agentText)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Palette.agentTintLight, in: RoundedRectangle(cornerRadius: 8))
                }
                if let conf {
                    HStack(spacing: 8) {
                        Text("CONFIDENCE").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(String(format: "%.2f", conf))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.confidenceColor(conf))
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(i < Int((conf * 5).rounded(.down)) ? Theme.confidenceColor(conf) : Theme.Palette.confidenceUnfilled)
                                    .frame(width: 16, height: 5)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if !why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WHY").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(why).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                if !draft.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DRAFT").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(draft).font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var stageBadgeColor: Color {
        task.owner == .agent ? Theme.Palette.agentText : Theme.Palette.textSecondary
    }

    private var subtasksSection: some View {
        let progress = task.subtaskProgress
        return VStack(alignment: .leading, spacing: 8) {
            Text("SUBTASKS (\(progress.done)/\(progress.total))")
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            ForEach(task.subtasks ?? []) { sub in
                HStack(spacing: 8) {
                    Button {
                        if sub.stage == .done { sub.stage = .planned; sub.completedAt = nil }
                        else { sub.markDone() }
                    } label: {
                        Image(systemName: sub.stage == .done ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(sub.stage == .done ? Theme.Palette.done : Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    Text(sub.title).font(Theme.Fonts.meta)
                        .strikethrough(sub.stage == .done, color: Theme.Palette.textTertiary)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Button { context.delete(sub) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove subtask")
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
