# Notch — Expanded View Redesign & External-Monitor Targeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the notch's hover-expanded panel with a triage summary card + full today-agenda (tasks and meetings merged, chronological, with a progress bar and tappable rows), and fix the notch to prefer an external monitor over the built-in notch screen when one is connected.

**Architecture:** Two new pure, TDD'd logic units (`DayPlanner.agenda` merges tasks+events into one chronological list; `NotchScreenPicker` decides which screen wins) plug into the existing `NotchController`/`NotchView` pair. A small `@Observable` bridge (`NotchNavigation`) lets the notch's separate `NSPanel` ask the main window to open a task or the Agent console, mirroring how `AgentService` is already environment-shared across both.

**Tech Stack:** Swift, SwiftUI, SwiftData, AppKit (`NSScreen`, `NSPanel`), XCTest.

**Reference:** `docs/superpowers/specs/2026-07-02-notch-expanded-redesign-design.md` (design), `docs/plans/2026-06-13-mustard-notch.md` (original notch plan).

---

### Task 1: `DayPlanner.agenda` — merge tasks + events into one chronological list

**Files:**
- Modify: `Sources/MustardKit/Logic/DayPlanner.swift`
- Test: `Tests/MustardTests/DayPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MustardTests/DayPlannerTests.swift` (inside the existing `DayPlannerTests` class, using its existing `cal`/`at(_:)` helpers):

```swift
    func test_agenda_mergesTasksAndEventsChronologically_untimedLast() {
        let day = at("2026-06-12T00:00:00Z")

        let review = MustardTask(title: "Review PR", scheduledAt: at("2026-06-12T09:30:00Z"))
        review.isTimed = true

        let standup = MustardTask(title: "Team stand-up", scheduledAt: at("2026-06-12T09:00:00Z"))
        standup.isTimed = true
        standup.markDone()

        let anytime = MustardTask(title: "Reply to ACME", scheduledAt: at("2026-06-12T00:00:00Z"))
        anytime.isTimed = false

        let elsewhere = MustardTask(title: "Tomorrow's task", scheduledAt: at("2026-06-13T09:00:00Z"))
        elsewhere.isTimed = true

        let sync = CalendarEvent(
            title: "Design sync", start: at("2026-06-12T11:00:00Z"), end: at("2026-06-12T11:30:00Z")
        )
        let allDay = CalendarEvent(
            title: "Company holiday", start: at("2026-06-12T00:00:00Z"), end: at("2026-06-13T00:00:00Z"),
            isAllDay: true
        )

        let result = DayPlanner.agenda(
            tasks: [review, standup, anytime, elsewhere], events: [sync, allDay], day: day, calendar: cal
        )

        XCTAssertEqual(
            result.map(\.title),
            ["Team stand-up", "Review PR", "Design sync", "Reply to ACME", "Company holiday"]
        )
    }

    func test_agenda_tagLabelAndColorComeFromTaskListArea() {
        let day = at("2026-06-12T00:00:00Z")
        let area = Area(name: "DLA SDK", colorHex: "#378ADD")
        let list = TaskList(name: "SDK work", area: area)
        let task = MustardTask(title: "Review DLA SDK pull request", scheduledAt: at("2026-06-12T09:30:00Z"))
        task.isTimed = true
        task.list = list

        let result = DayPlanner.agenda(tasks: [task], events: [], day: day, calendar: cal)

        XCTAssertEqual(result.first?.tagLabel, "DLA SDK")
        XCTAssertEqual(result.first?.tagColorHex, "#378ADD")
    }

    func test_agenda_eventsCarryJoinURL_andAreNeverDone() {
        let day = at("2026-06-12T00:00:00Z")
        let meeting = CalendarEvent(
            title: "Design sync", start: at("2026-06-12T11:00:00Z"), end: at("2026-06-12T11:30:00Z"),
            joinURL: "https://meet.example.com/design-sync"
        )

        let result = DayPlanner.agenda(tasks: [], events: [meeting], day: day, calendar: cal)

        XCTAssertEqual(result.first?.joinURL, "https://meet.example.com/design-sync")
        XCTAssertEqual(result.first?.isDone, false)
    }

    func test_agenda_taskIsDoneReflectsStage() {
        let day = at("2026-06-12T00:00:00Z")
        let task = MustardTask(title: "Draft notes", scheduledAt: at("2026-06-12T14:00:00Z"))
        task.isTimed = true
        task.markDone()

        let result = DayPlanner.agenda(tasks: [task], events: [], day: day, calendar: cal)

        XCTAssertEqual(result.first?.isDone, true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DayPlannerTests`
Expected: FAIL — `agenda` is not a member of `DayPlanner`, and `AgendaItem` is undefined.

- [ ] **Step 3: Implement `AgendaItem` and `DayPlanner.agenda`**

In `Sources/MustardKit/Logic/DayPlanner.swift`, add the `AgendaItem` type above `DayPlanner` and the `agenda` function inside the `DayPlanner` enum:

```swift
/// One row of the merged today-agenda (notch §6a redesign): a task or an
/// event, whichever it wraps, with the display fields already resolved so
/// views don't need to branch on `kind` except to decide tap/toggle targets.
public struct AgendaItem: Identifiable {
    public enum Kind {
        case task(MustardTask)
        case event(CalendarEvent)
    }

    public let id: String
    public let kind: Kind
    /// `nil` means untimed — sorts last, rendered as "Any".
    public let time: Date?
    public let title: String
    public let isDone: Bool
    public let tagLabel: String?
    public let tagColorHex: String?
    public let joinURL: String?
}
```

Then, inside `public enum DayPlanner { ... }`, add (after `dayProgress`):

```swift
    /// Merges today's tasks and events into one chronological agenda: timed
    /// items ascending by time, then untimed tasks and all-day events (in
    /// their original relative order). Tasks reuse `tasksForDay`'s day
    /// filtering; events are today's events with no additional filtering —
    /// they have no done state to filter on.
    public static func agenda(
        tasks: [MustardTask], events: [CalendarEvent], day: Date, calendar: Calendar = .current
    ) -> [AgendaItem] {
        let taskItems = tasksForDay(tasks, day: day, calendar: calendar).map { task in
            AgendaItem(
                id: "task:\(task.uid)",
                kind: .task(task),
                time: task.isTimed ? task.scheduledAt : nil,
                title: task.title,
                isDone: task.stage == .done,
                tagLabel: task.list?.area?.name,
                tagColorHex: task.list?.area?.colorHex,
                joinURL: nil
            )
        }
        let eventItems = events
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .map { event -> AgendaItem in
                AgendaItem(
                    id: "event:\(event.externalId.isEmpty ? event.title : event.externalId)",
                    kind: .event(event),
                    time: event.isAllDay ? nil : event.start,
                    title: event.title,
                    isDone: false,
                    tagLabel: nil,
                    tagColorHex: nil,
                    joinURL: event.joinURL
                )
            }
        let all = taskItems + eventItems
        let timed = all.filter { $0.time != nil }.sorted { $0.time! < $1.time! }
        let untimed = all.filter { $0.time == nil }
        return timed + untimed
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DayPlannerTests`
Expected: PASS (all `DayPlannerTests`, including the 4 new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/DayPlanner.swift Tests/MustardTests/DayPlannerTests.swift
git commit -m "feat(notch): add DayPlanner.agenda merging tasks and events

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `NotchScreenPicker` — prefer external monitor over the built-in notch

**Files:**
- Create: `Sources/MustardKit/Logic/NotchScreenPicker.swift`
- Test: `Tests/MustardTests/NotchScreenPickerTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `Tests/MustardTests/NotchScreenPickerTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class NotchScreenPickerTests: XCTestCase {
    func test_choose_prefersExternalOverNotch_whenBothConnected() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: false)
        let external = NotchScreenDescriptor(id: "external", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch, external]), external)
    }

    func test_choose_fallsBackToNotchScreen_whenItsTheOnlyDisplay() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch]), notch)
    }

    func test_choose_fallsBackToMain_whenNoNotchAndNoExternal() {
        let onlyScreen = NotchScreenDescriptor(id: "single", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [onlyScreen]), onlyScreen)
    }

    func test_choose_returnsNil_whenNoScreens() {
        XCTAssertNil(NotchScreenPicker.choose(from: []))
    }

    func test_choose_multipleExternals_picksFirstNonNotch() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: false)
        let externalA = NotchScreenDescriptor(id: "a", hasNotch: false, isMain: false)
        let externalB = NotchScreenDescriptor(id: "b", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch, externalA, externalB]), externalA)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchScreenPickerTests`
Expected: FAIL — `NotchScreenDescriptor`/`NotchScreenPicker` do not exist.

- [ ] **Step 3: Implement the picker**

Create `Sources/MustardKit/Logic/NotchScreenPicker.swift`:

```swift
import Foundation

/// Lightweight, testable stand-in for `NSScreen` so screen-selection policy
/// can be unit tested without a live display list.
public struct NotchScreenDescriptor: Equatable {
    public let id: AnyHashable
    public let hasNotch: Bool
    public let isMain: Bool

    public init(id: AnyHashable, hasNotch: Bool, isMain: Bool) {
        self.id = id
        self.hasNotch = hasNotch
        self.isMain = isMain
    }
}

/// Decides which screen the notch panel renders on: prefer a connected
/// external (non-notch) display over the built-in notch screen, so the
/// panel follows the monitor actually in use instead of staying stuck on
/// the laptop's physical notch whenever the lid is open.
public enum NotchScreenPicker {
    public static func choose(from screens: [NotchScreenDescriptor]) -> NotchScreenDescriptor? {
        if screens.count > 1, let external = screens.first(where: { !$0.hasNotch }) {
            return external
        }
        if let notch = screens.first(where: { $0.hasNotch }) {
            return notch
        }
        if let main = screens.first(where: { $0.isMain }) {
            return main
        }
        return screens.first
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotchScreenPickerTests`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/NotchScreenPicker.swift Tests/MustardTests/NotchScreenPickerTests.swift
git commit -m "feat(notch): add NotchScreenPicker for external-monitor targeting

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Wire `NotchScreenPicker` into `NotchController`

**Files:**
- Modify: `Sources/MustardKit/Views/NotchSurface.swift:22-24`

- [ ] **Step 1: Replace the `screen` computed property**

In `Sources/MustardKit/Views/NotchSurface.swift`, replace:

```swift
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
```

with:

```swift
    private var screen: NSScreen? {
        let screens = NSScreen.screens
        let descriptors = screens.enumerated().map { index, screen in
            NotchScreenDescriptor(
                id: index,
                hasNotch: screen.safeAreaInsets.top > 0,
                isMain: screen == NSScreen.main
            )
        }
        guard let chosen = NotchScreenPicker.choose(from: descriptors),
              let index = chosen.id as? Int else { return NSScreen.main }
        return screens[index]
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `swift test`
Expected: all existing tests still PASS (this change has no dedicated test — `NSScreen` isn't mockable — but the picker it delegates to is already covered by Task 2).

- [ ] **Step 4: Commit**

```bash
git add Sources/MustardKit/Views/NotchSurface.swift
git commit -m "fix(notch): prefer external monitor over built-in notch screen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `NotchNavigation` — cross-panel navigation bridge

**Files:**
- Create: `Sources/MustardKit/Views/NotchNavigation.swift`

- [ ] **Step 1: Create the bridge**

Create `Sources/MustardKit/Views/NotchNavigation.swift`:

```swift
import Foundation
import Observation

/// Cross-panel navigation bridge: the notch (its own `NSPanel`) sets a
/// pending request here; `RootView` (the main window) observes it, brings
/// the window forward, and opens the right screen or sheet. Environment-
/// injected into both the notch and the root window, the same way
/// `AgentService` already is (see `MustardApp`).
@MainActor
@Observable
public final class NotchNavigation {
    public var pendingTask: MustardTask?
    public var openAgentConsole = false

    public init() {}
}
```

This is plumbing (a shared state holder), not decision logic, so it has no
dedicated unit test — it's exercised end-to-end by the manual verification
in Task 6.

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Views/NotchNavigation.swift
git commit -m "feat(notch): add NotchNavigation cross-panel bridge

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Redesign `NotchView.expandedContent`

**Files:**
- Modify: `Sources/MustardKit/Views/NotchSurface.swift`

- [ ] **Step 1: Grow the expanded panel size**

Replace:

```swift
    private let expandedSize = NSSize(width: 420, height: 300)
```

with:

```swift
    private let expandedSize = NSSize(width: 420, height: 460)
```

- [ ] **Step 2: Update the file header comment**

Replace the file's top doc comment:

```swift
/// The notch surface (spec §6a): a black, notch-hugging panel at the top
/// of the built-in display. Idle: thin strip rotating focus → waiting count.
/// Hover: expands into the agent tray + quick capture. Intentionally dark —
/// it extends the physical notch — unlike the rest of the app.
```

with:

```swift
/// The notch surface (spec §6a): a black, notch-hugging panel anchored to
/// whichever screen is active (external monitor preferred — see
/// `NotchScreenPicker`). Idle: thin strip rotating focus → waiting count.
/// Hover: expands into a triage summary card + today's agenda + quick
/// capture. Intentionally dark — it extends the physical notch — unlike
/// the rest of the app.
```

- [ ] **Step 3: Add the `NotchNavigation` environment and drop the now-unused meetings computed property**

In `NotchView`, add the environment property alongside the existing ones:

```swift
    @Environment(AgentService.self) private var agent
    @Environment(NotchNavigation.self) private var nav
```

Remove the now-unused `todayMeetings` computed property (superseded by the
merged agenda):

```swift
    private var todayMeetings: [CalendarEvent] {
        events.filter { Calendar.current.isDateInToday($0.start) }
    }
```

Keep `nextMeeting` / `nextMeetingLabel` — the idle strip still uses them.

- [ ] **Step 4: Add the agenda/progress/triage computed properties and the toggle/open helpers**

Add these alongside the existing `pending`/`needsReviewCount` computed
properties in `NotchView`:

```swift
    private var todayAgenda: [AgendaItem] {
        DayPlanner.agenda(tasks: tasks, events: events, day: .now)
    }

    private var todayProgress: (done: Int, total: Int) {
        DayPlanner.dayProgress(tasks, day: .now)
    }

    private var triageApprovals: Int { pending.count }
    private var triageReviews: Int { needsReviewCount }
    private var triageTotal: Int { triageApprovals + triageReviews }

    private var triageSubline: String {
        var parts: [String] = []
        if triageApprovals > 0 {
            parts.append("\(triageApprovals) approval\(triageApprovals == 1 ? "" : "s")")
        }
        if triageReviews > 0 {
            parts.append("\(triageReviews) review\(triageReviews == 1 ? "" : "s") waiting")
        }
        return parts.joined(separator: " · ")
    }

    private func toggleDone(_ task: MustardTask) {
        if task.stage == .done {
            task.stage = .planned
            task.completedAt = nil
        } else {
            TaskCompletion.complete(task, in: context)
        }
    }

    private func openDetail(_ item: AgendaItem) {
        if case .task(let task) = item.kind {
            nav.pendingTask = task
        }
    }
```

- [ ] **Step 5: Replace `expandedContent` and add the new subviews**

Replace the entire existing `expandedContent` computed property (from
`private var expandedContent: some View {` through its closing `}`) with:

```swift
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 30)

            Text("Agent")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            if triageTotal > 0 {
                triageCard
            }

            agendaSection

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            captureBar
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var triageCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#AFA9EC"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "#7F77DD").opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(triageTotal) item\(triageTotal == 1 ? "" : "s") to triage")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                Text(triageSubline)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Button {
                nav.openAgentConsole = true
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#AFA9EC"))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var agendaSection: some View {
        let items = todayAgenda
        let progress = todayProgress
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY · \(Date.now.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.08)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.done) of \(progress.total) done")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            if progress.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(Color(hex: "#5DCAA5"))
                            .frame(width: geo.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                    }
                }
                .frame(height: 3)
            }
            if items.isEmpty {
                Text("Nothing scheduled today")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(items) { item in
                            AgendaRow(item: item, onToggleDone: toggleDone, onOpen: { openDetail(item) })
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
    }

    private var captureBar: some View {
        HStack(spacing: 8) {
            TextField("Add to inbox…", text: $captureText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .focused($captureFocused)
                .onSubmit(capture)
            Button("Add", action: capture)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(hex: "#534AB7"), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.bottom, 12)
    }
```

- [ ] **Step 6: Add the `AgendaRow` subview**

Add this new type at the bottom of `NotchSurface.swift`, after the closing
brace of `NotchView`:

```swift
/// One row of the notch's TODAY agenda. Tasks toggle done via their status
/// circle and open `TaskDetailSheet` on row tap; events have no done state
/// or detail view — their circle is a static indicator and only "Join" is
/// interactive.
private struct AgendaRow: View {
    let item: AgendaItem
    var onToggleDone: (MustardTask) -> Void
    var onOpen: () -> Void

    private var timeLabel: String {
        guard let time = item.time else { return "Any" }
        return time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 34, alignment: .leading)

            statusIcon

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(item.isDone ? .white.opacity(0.4) : .white.opacity(0.9))
                    .strikethrough(item.isDone)
                    .lineLimit(1)
                if let tag = item.tagLabel {
                    Text(tag)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: item.tagColorHex ?? "#B0ACA1"))
                }
            }
            Spacer(minLength: 0)
            if let joinURL = item.joinURL, let url = URL(string: joinURL) {
                Link("Join", destination: url)
                    .font(.system(size: 11)).foregroundStyle(Color(hex: "#6E9FFF"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.kind {
        case .task(let task):
            Button {
                onToggleDone(task)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(item.isDone ? .white.opacity(0.3) : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
        case .event:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
```

- [ ] **Step 7: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 8: Run the full test suite**

Run: `swift test`
Expected: all tests PASS (no logic changed here beyond wiring — this task
is view-only, verified by build + eyes per project convention).

- [ ] **Step 9: Commit**

```bash
git add Sources/MustardKit/Views/NotchSurface.swift
git commit -m "feat(notch): redesign expanded view with triage card + today agenda

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Wire `NotchNavigation` through `MustardApp` and `RootView`

**Files:**
- Modify: `Sources/Mustard/MustardApp.swift`
- Modify: `Sources/MustardKit/Views/RootView.swift`

- [ ] **Step 1: Add `NotchNavigation` state to `MustardApp`**

In `Sources/Mustard/MustardApp.swift`, add a new `@State` alongside the
existing ones:

```swift
    @State private var agent: AgentService
    @State private var calendar: GoogleCalendarService
    @State private var hoverPanel: HoverPanel?
    @State private var notch: NotchController?
    @State private var notchNav = NotchNavigation()
```

- [ ] **Step 2: Inject it into `RootView` and the notch content**

Replace:

```swift
            RootView()
                .environment(agent)
                .environment(calendar)
```

with:

```swift
            RootView()
                .environment(agent)
                .environment(calendar)
                .environment(notchNav)
```

Replace:

```swift
                    if notch == nil {
                        let controller = NotchController { onHover in
                            AnyView(
                                NotchView(onHoverChange: onHover)
                                    .environment(agent)
                                    .modelContainer(container)
                            )
                        }
                        controller.show()
                        notch = controller
                    }
```

with:

```swift
                    if notch == nil {
                        let controller = NotchController { onHover in
                            AnyView(
                                NotchView(onHoverChange: onHover)
                                    .environment(agent)
                                    .environment(notchNav)
                                    .modelContainer(container)
                            )
                        }
                        controller.show()
                        notch = controller
                    }
```

- [ ] **Step 3: React to `NotchNavigation` in `RootView`**

In `Sources/MustardKit/Views/RootView.swift`, add the `AppKit` import at
the top:

```swift
import SwiftUI
import SwiftData
import AppKit
```

Add the environment property and a new selection `@State` alongside the
existing ones in `RootView`:

```swift
    @State private var screen: MustardScreen = .today
    @State private var selectedScope: ListScope?
    @State private var showCommandBar = false
    @State private var sourcePanel = SourcePanelController()
    @State private var selectedTaskFromNotch: MustardTask?
    @Environment(NotchNavigation.self) private var notchNav
```

Add these modifiers to the end of the modifier chain on `body` (after the
existing `.preferredColorScheme(.light)`):

```swift
        .preferredColorScheme(.light)
        .sheet(item: $selectedTaskFromNotch) { TaskDetailSheet(task: $0) }
        .onChange(of: notchNav.pendingTask) { _, task in
            guard let task else { return }
            NSApp.activate(ignoringOtherApps: true)
            selectedTaskFromNotch = task
            notchNav.pendingTask = nil
        }
        .onChange(of: notchNav.openAgentConsole) { _, shouldOpen in
            guard shouldOpen else { return }
            NSApp.activate(ignoringOtherApps: true)
            screen = .agent
            notchNav.openAgentConsole = false
        }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Manual verification (build + eyes — required by project convention)**

```bash
./build-app.sh
open build/Mustard.app
```

Confirm, and report back to Leon:
- The notch's expanded (hover) view shows: "Agent" header, the triage
  summary card (when there are pending recs / needs-review tasks) with a
  working "Open ↗" that brings the main window forward on the Agent tab,
  and the TODAY agenda with a progress bar.
- Tapping a task row opens `TaskDetailSheet` in the main window; tapping a
  task's status circle toggles it done without opening the sheet; tapping
  "Join" on a meeting row opens its URL.
- With only the built-in display connected, the notch still hugs the
  physical notch. With an external monitor connected, the notch appears on
  the external monitor instead.

- [ ] **Step 7: Commit**

```bash
git add Sources/Mustard/MustardApp.swift Sources/MustardKit/Views/RootView.swift
git commit -m "feat(notch): wire NotchNavigation into RootView and MustardApp

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Note the redesign in the original notch plan doc

**Files:**
- Modify: `docs/plans/2026-06-13-mustard-notch.md`

- [ ] **Step 1: Append a superseding note**

Add this line to the end of `docs/plans/2026-06-13-mustard-notch.md`:

```markdown

**2026-07-02 update:** the hover-expanded panel described above (focus row +
3 meetings + inline recommendation Approve/Deny) was replaced by the triage
summary card + full today-agenda redesign in
`docs/superpowers/plans/2026-07-02-notch-expanded-redesign.md`. Screen
selection also changed to prefer an external monitor over the built-in
notch display when one is connected.
```

- [ ] **Step 2: Commit**

```bash
git add docs/plans/2026-06-13-mustard-notch.md
git commit -m "docs(notch): note expanded-view redesign supersedes original plan

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
