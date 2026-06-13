# Mustard — Foundation Implementation Plan (Plan 1 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a fresh native macOS app (`Mustard`) with a SwiftData model layer and a "Things 3 calm" today timeline where tasks can be captured, scheduled to a time, completed, and carried forward — all on local data, no external accounts.

**Architecture:** Native SwiftUI, multiplatform-ready (macOS target first; iOS target added in a later plan). Persistence is SwiftData with a `ModelContainer`; the schema is CloudKit-compatible from day one (all relationships optional, no unique constraints) so the CloudKit plan is a capability flip, not a migration. Pure logic (carry-forward, day bucketing, ordering) lives in plain testable types separate from views, so it can be unit-tested with XCTest while views are verified visually.

**Tech Stack:** Swift 6 / SwiftUI, SwiftData, XCTest, Xcode 26. Source-controlled in a fresh git repo at `~/Documents/Cavehole/Mustard`.

> **Execution deviation (2026-06-12):** built as a **Swift Package** (library `MustardKit` with models/logic/views + thin executable `Mustard` + `MustardTests`), not a GUI-created `.xcodeproj` — this lets the agent create the project autonomously; `swift test`/`swift build` replace the `xcodebuild` commands, and an app bundle is assembled by `build-app.sh` (same approach as TriageHub). An Xcode project (or manual entitlements) becomes necessary only when the CloudKit plan lands. Design-token namespace is `Theme` (not `Mustard.`) to avoid clashing with the module name.

**Out of scope (later plans):** CloudKit sync · Google Calendar · the agent loop (recommendations/review queues, `claude -p` runner via `claude setup-token`) · the notch surface · the always-on hover panel · iOS target.

**Design language (Things 3 calm), fixed for every view in this plan:**
- Warm off-white window background `#FBFAF7`; surfaces/dividers `#EFEBE2`; hairline borders `#E7E3DA`.
- Primary text `#2B2A26`; secondary `#9A968B`; tertiary/time-gutter `#B0ACA1`.
- Single accent (focus/primary actions) blue `#2D7FF9`; agent/recommend hue purple `#7F77DD`; done/output green `#1D9E75` (used sparingly, reserved for later plans).
- Generous spacing (16–18px vertical rhythm), large readable type (15px body, 13px meta), hairline dividers — no boxes around timeline rows. Density comes from hierarchy, not cramming.

---

## File Structure

```
Mustard/                                  (fresh git repo + Xcode project)
  Mustard.xcodeproj
  Mustard/
    MustardApp.swift                       app entry; builds the ModelContainer
    Models/
      Area.swift                        SwiftData @Model: top-level grouping
      TaskList.swift                    SwiftData @Model: list within an area
      MustardTask.swift                    SwiftData @Model: the task (owner, status, schedule)
      Enums.swift                       TaskStatus, TaskOwner (Codable, String-backed)
    Logic/
      DayPlanner.swift                  pure functions: bucket tasks by day, order, carry-forward
      DesignTokens.swift                Things-3-calm colors + type as Color/Font extensions
    Views/
      TodayView.swift                   the today timeline screen
      TimelineRow.swift                 one scheduled task row
      QuickCaptureField.swift           inline capture (⌘N / always-visible field)
    PreviewData.swift                   in-memory sample container for #Preview + manual runs
  MustardTests/
    DayPlannerTests.swift               unit tests for DayPlanner
    ModelTests.swift                    unit tests for model creation + status transitions
```

Models, Logic, Views, and Tests are separated by responsibility. `DayPlanner` and the models hold all the logic XCTest will cover; the three view files are kept small and verified by building + looking.

---

## Task 1: Create the Xcode project and git repo (human-led)

**This task is done by you in Xcode — I can't create an `.xcodeproj` or set capabilities from the CLI.** Exact steps:

- [ ] **Step 1: New project**
  - Xcode → File → New → Project → **macOS** tab → **App** → Next.
  - Product Name: `Mustard`
  - Team: your Apple Developer team
  - Organization Identifier: `com.cavehole` (→ bundle id `com.cavehole.Mustard`)
  - Interface: **SwiftUI**; Language: **Swift**
  - Storage: **SwiftData**  ✅ (this generates a `ModelContainer` and a sample `Item` model)
  - **Untick** "Host in CloudKit" for now (CloudKit is a later plan).
  - Include Tests: **✅** (creates the `MustardTests` target).
  - Save to: `~/Documents/Cavehole/Mustard`. **Tick "Create Git repository on my Mac."**

- [ ] **Step 2: Delete the template sample model**
  - Delete the generated `Item.swift` and remove its references from `MustardApp.swift`/`ContentView.swift` (we replace these in later tasks). Leave the project building with an empty `ContentView { Text("Mustard") }`.

- [ ] **Step 3: Confirm it builds and runs**
  - Press ⌘R. A blank window titled Mustard appears.

- [ ] **Step 4: First commit**
  ```bash
  cd ~/Documents/Cavehole/Mustard
  git add -A && git commit -m "chore: bootstrap Mustard macOS SwiftData app"
  ```

- [ ] **Step 5: Tell me the path is ready** so I can take over file creation. From here, I create/edit files under `~/Documents/Cavehole/Mustard/Mustard/` and you press ⌘U / ⌘R to run tests/app (or I run `xcodebuild` against the scheme).

**Verification command** (I will run this to confirm the scheme exists before proceeding):
```bash
xcodebuild -list -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj
```
Expected: a scheme named `Mustard` and a test target `MustardTests`.

---

## Task 2: Enums (TaskStatus, TaskOwner)

**Files:**
- Create: `Mustard/Models/Enums.swift`

- [ ] **Step 1: Write the enums**
```swift
import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case inbox, planned, inProgress, done, someday
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .done: "Done"
        case .someday: "Someday"
        }
    }
    var isOpen: Bool { self != .done && self != .someday }
}

enum TaskOwner: String, Codable, CaseIterable, Identifiable {
    case me, agent
    var id: String { rawValue }
    var label: String { self == .me ? "Me" : "Agent" }
}
```

- [ ] **Step 2: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Models/Enums.swift && git commit -m "feat: task status and owner enums"
```

---

## Task 3: SwiftData models (Area, TaskList, MustardTask)

**Files:**
- Create: `Mustard/Models/Area.swift`, `Mustard/Models/TaskList.swift`, `Mustard/Models/MustardTask.swift`

CloudKit-compatibility rules baked in now (so the later CloudKit plan is just a capability flip): **every relationship is optional, every stored property has a default or is optional, no `@Attribute(.unique)`.**

- [ ] **Step 1: Area**
```swift
import Foundation
import SwiftData

@Model
final class Area {
    var name: String = ""
    var colorHex: String = "#2D7FF9"
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \TaskList.area)
    var lists: [TaskList]? = []

    init(name: String = "", colorHex: String = "#2D7FF9") {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = .now
    }
}
```

- [ ] **Step 2: TaskList**
```swift
import Foundation
import SwiftData

@Model
final class TaskList {
    var name: String = ""
    var createdAt: Date = Date.now
    var area: Area?
    @Relationship(deleteRule: .cascade, inverse: \MustardTask.list)
    var tasks: [MustardTask]? = []

    init(name: String = "", area: Area? = nil) {
        self.name = name
        self.area = area
        self.createdAt = .now
    }
}
```

- [ ] **Step 3: MustardTask**
```swift
import Foundation
import SwiftData

@Model
final class MustardTask {
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = TaskStatus.inbox.rawValue
    var ownerRaw: String = TaskOwner.me.rawValue
    var scheduledAt: Date?
    var estimateMinutes: Int = 30
    var createdAt: Date = Date.now
    var completedAt: Date?
    var list: TaskList?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }
    var owner: TaskOwner {
        get { TaskOwner(rawValue: ownerRaw) ?? .me }
        set { ownerRaw = newValue.rawValue }
    }

    init(title: String = "", owner: TaskOwner = .me, scheduledAt: Date? = nil) {
        self.title = title
        self.ownerRaw = owner.rawValue
        self.scheduledAt = scheduledAt
        self.createdAt = .now
    }

    /// Mark done, stamping completion time. Idempotent.
    func markDone(now: Date = .now) {
        status = .done
        completedAt = now
    }
}
```
Enums are stored as `…Raw` strings with typed accessors — SwiftData/CloudKit persist primitives cleanly, and the computed property keeps call sites type-safe.

- [ ] **Step 4: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Models && git commit -m "feat: SwiftData models (Area, TaskList, MustardTask)"
```

---

## Task 4: Model unit tests

**Files:**
- Create: `MustardTests/ModelTests.swift`

- [ ] **Step 1: Write failing tests** (in-memory container, no disk)
```swift
import XCTest
import SwiftData
@testable import Mustard

final class ModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, configurations: config
        )
        return ModelContext(container)
    }

    func test_newTask_defaultsToInboxOwnedByMe() throws {
        let task = MustardTask(title: "Draft notes")
        XCTAssertEqual(task.status, .inbox)
        XCTAssertEqual(task.owner, .me)
        XCTAssertNil(task.scheduledAt)
    }

    func test_markDone_setsStatusAndCompletedAt() throws {
        let task = MustardTask(title: "x")
        let when = Date(timeIntervalSince1970: 1_000_000)
        task.markDone(now: when)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, when)
    }

    func test_insertAndFetch_roundTrips() throws {
        let ctx = try makeContext()
        ctx.insert(MustardTask(title: "Persisted"))
        let fetched = try ctx.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Persisted")
    }

    func test_statusAccessor_survivesRawRoundTrip() throws {
        let task = MustardTask(title: "x")
        task.status = .inProgress
        XCTAssertEqual(task.statusRaw, "inProgress")
        XCTAssertEqual(task.status, .inProgress)
    }
}
```

- [ ] **Step 2: Run, expect failure** (until models compile into the test target)
  Run in Xcode (⌘U) or:
  ```bash
  xcodebuild test -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS' -only-testing:MustardTests/ModelTests
  ```
  Expected first run: FAIL/most likely build error if any model member is mistyped — fix until green.

- [ ] **Step 3: Make it pass** — tests pass once Tasks 2–3 are correct; no new code expected. If a test fails, fix the model, not the test.

- [ ] **Step 4: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add MustardTests/ModelTests.swift && git commit -m "test: model defaults, done-stamping, persistence round-trip"
```

---

## Task 5: DayPlanner logic + tests (TDD)

**Files:**
- Create: `Mustard/Logic/DayPlanner.swift`
- Create: `MustardTests/DayPlannerTests.swift`

`DayPlanner` is pure (no SwiftData, no views): it takes tasks + a reference date and answers "what shows on this day, in what order" and "what should carry forward."

- [ ] **Step 1: Write failing tests first**
```swift
import XCTest
@testable import Mustard

final class DayPlannerTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: iso)!
    }

    func test_tasksForDay_returnsOnlySameDayScheduled_sortedByTime() {
        let day = at("2026-06-12T00:00:00Z")
        let a = MustardTask(title: "late", scheduledAt: at("2026-06-12T15:00:00Z"))
        let b = MustardTask(title: "early", scheduledAt: at("2026-06-12T09:00:00Z"))
        let other = MustardTask(title: "tomorrow", scheduledAt: at("2026-06-13T09:00:00Z"))
        let result = DayPlanner.tasksForDay([a, b, other], day: day, calendar: cal)
        XCTAssertEqual(result.map(\.title), ["early", "late"])
    }

    func test_unscheduled_returnsOpenTasksWithNoDate() {
        let scheduled = MustardTask(title: "s", scheduledAt: at("2026-06-12T09:00:00Z"))
        let open = MustardTask(title: "open")
        let done = MustardTask(title: "done"); done.markDone()
        let result = DayPlanner.unscheduled([scheduled, open, done])
        XCTAssertEqual(result.map(\.title), ["open"])
    }

    func test_carryForward_movesIncompletePastTasksToToday_preservingTimeOfDay() {
        let today = at("2026-06-12T00:00:00Z")
        let stale = MustardTask(title: "stale", scheduledAt: at("2026-06-10T14:30:00Z"))
        let doneStale = MustardTask(title: "doneStale", scheduledAt: at("2026-06-10T14:30:00Z"))
        doneStale.markDone()
        DayPlanner.carryForward([stale, doneStale], to: today, calendar: cal)

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: stale.scheduledAt!)
        XCTAssertEqual(comps.day, 12)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(doneStale.scheduledAt, at("2026-06-10T14:30:00Z"))
    }
}
```

- [ ] **Step 2: Run, expect failure** — `DayPlanner` undefined.
  ```bash
  xcodebuild test -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS' -only-testing:MustardTests/DayPlannerTests
  ```
  Expected: build failure "cannot find 'DayPlanner' in scope".

- [ ] **Step 3: Implement minimally**
```swift
import Foundation

enum DayPlanner {
    static func tasksForDay(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> [MustardTask] {
        tasks
            .filter { task in
                guard let when = task.scheduledAt else { return false }
                return calendar.isDate(when, inSameDayAs: day)
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    static func unscheduled(_ tasks: [MustardTask]) -> [MustardTask] {
        tasks.filter { $0.scheduledAt == nil && $0.status.isOpen }
    }

    /// Move open tasks scheduled before `today` onto `today`, keeping their time-of-day.
    static func carryForward(_ tasks: [MustardTask], to today: Date, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: today)
        for task in tasks {
            guard task.status.isOpen, let when = task.scheduledAt,
                  when < startOfToday else { continue }
            let time = calendar.dateComponents([.hour, .minute], from: when)
            task.scheduledAt = calendar.date(
                bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: startOfToday
            )
        }
    }
}
```

- [ ] **Step 4: Run, expect pass**
  ```bash
  xcodebuild test -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS' -only-testing:MustardTests/DayPlannerTests
  ```
  Expected: 3 tests pass.

- [ ] **Step 5: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Logic/DayPlanner.swift MustardTests/DayPlannerTests.swift
git commit -m "feat: DayPlanner day-bucketing, unscheduled filter, carry-forward (TDD)"
```

---

## Task 6: Design tokens

**Files:**
- Create: `Mustard/Logic/DesignTokens.swift`

- [ ] **Step 1: Write the tokens** (the locked Things-3-calm palette + type)
```swift
import SwiftUI

extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
        var rgb: UInt64 = 0; s.scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

enum Mustard {
    enum Palette {
        static let bg = Color(hex: "#FBFAF7")
        static let surface = Color(hex: "#EFEBE2")
        static let hairline = Color(hex: "#E7E3DA")
        static let textPrimary = Color(hex: "#2B2A26")
        static let textSecondary = Color(hex: "#9A968B")
        static let textTertiary = Color(hex: "#B0ACA1")
        static let accent = Color(hex: "#2D7FF9")
        static let agent = Color(hex: "#7F77DD")
        static let done = Color(hex: "#1D9E75")
    }
    enum Type_ {
        static let body = Font.system(size: 15)
        static let title = Font.system(size: 15, weight: .medium)
        static let meta = Font.system(size: 13)
        static let gutter = Font.system(size: 13)
    }
}
```

- [ ] **Step 2: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Logic/DesignTokens.swift && git commit -m "feat: Things-3-calm design tokens"
```

---

## Task 7: Preview/sample data container

**Files:**
- Create: `Mustard/PreviewData.swift`

- [ ] **Step 1: Write the in-memory sample container** (drives `#Preview` and lets you run the app with content before any persistence UI exists)
```swift
import SwiftData
import Foundation

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, configurations: config
        )
        let ctx = container.mainContext
        let cal = Calendar.current
        func today(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: .now)!
        }
        let work = Area(name: "Code Heroes", colorHex: "#2D7FF9")
        ctx.insert(work)
        let standup = MustardTask(title: "Team standup", scheduledAt: today(9, 30))
        let focus = MustardTask(title: "Draft DLA 5.2 release notes", scheduledAt: today(10, 0))
        focus.estimateMinutes = 90
        let sync = MustardTask(title: "Thales SDK sync", scheduledAt: today(11, 30))
        let loose = MustardTask(title: "Reply to Kamil re: BLE issue")
        for t in [standup, focus, sync, loose] { ctx.insert(t) }
        return container
    }()
}
```

- [ ] **Step 2: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/PreviewData.swift && git commit -m "chore: in-memory preview/sample data"
```

---

## Task 8: TimelineRow view

**Files:**
- Create: `Mustard/Views/TimelineRow.swift`

View tasks are verified by building + looking (SwiftUI views aren't unit-tested here). Code is complete — no placeholders.

- [ ] **Step 1: Write the row**
```swift
import SwiftUI

struct TimelineRow: View {
    let task: MustardTask
    var onToggleDone: () -> Void

    private var timeText: String {
        guard let when = task.scheduledAt else { return "" }
        return when.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeText)
                .font(Mustard.Type_.gutter)
                .foregroundStyle(Mustard.Palette.textTertiary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 1)

            Button(action: onToggleDone) {
                Image(systemName: task.status == .done ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(task.status == .done ? Mustard.Palette.done : Mustard.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(task.status == .done ? Mustard.Type_.body : Mustard.Type_.title)
                    .foregroundStyle(task.status == .done ? Mustard.Palette.textSecondary : Mustard.Palette.textPrimary)
                    .strikethrough(task.status == .done, color: Mustard.Palette.textTertiary)
                if task.estimateMinutes != 30 || task.owner == .agent {
                    HStack(spacing: 6) {
                        if task.owner == .agent {
                            Label("Agent", systemImage: "cpu")
                                .foregroundStyle(Mustard.Palette.agent)
                        }
                        Text("\(task.estimateMinutes) min")
                            .foregroundStyle(Mustard.Palette.textSecondary)
                    }
                    .font(Mustard.Type_.meta)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**
  ```bash
  xcodebuild build -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS'
  ```
  Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Views/TimelineRow.swift && git commit -m "feat: timeline row (Things-3-calm)"
```

---

## Task 9: QuickCaptureField view

**Files:**
- Create: `Mustard/Views/QuickCaptureField.swift`

- [ ] **Step 1: Write the capture field** (inserts a new task; if a day is in context, schedules it at 9:00 that day, else leaves it unscheduled in the inbox)
```swift
import SwiftUI
import SwiftData

struct QuickCaptureField: View {
    @Environment(\.modelContext) private var context
    /// When set, captured tasks are scheduled onto this day at 9:00.
    var scheduleOnto: Date?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(Mustard.Palette.textTertiary)
            TextField("Add a task…", text: $text)
                .textFieldStyle(.plain)
                .font(Mustard.Type_.body)
                .focused($focused)
                .onSubmit(capture)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func capture() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
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
```

- [ ] **Step 2: Build**
  ```bash
  xcodebuild build -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS'
  ```
  Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Views/QuickCaptureField.swift && git commit -m "feat: quick capture field"
```

---

## Task 10: TodayView (the screen) + wire into the app

**Files:**
- Create: `Mustard/Views/TodayView.swift`
- Modify: `Mustard/MustardApp.swift`

- [ ] **Step 1: Write TodayView**
```swift
import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [MustardTask]
    private let today = Date.now

    private var scheduled: [MustardTask] { DayPlanner.tasksForDay(allTasks, day: today) }
    private var unscheduled: [MustardTask] { DayPlanner.unscheduled(allTasks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(scheduled) { task in
                    TimelineRow(task: task) { toggle(task) }
                    Divider().overlay(Mustard.Palette.hairline)
                }
                if scheduled.isEmpty {
                    Text("Nothing scheduled yet")
                        .font(Mustard.Type_.meta)
                        .foregroundStyle(Mustard.Palette.textTertiary)
                        .padding(.vertical, 16)
                }
                QuickCaptureField(scheduleOnto: today)

                if !unscheduled.isEmpty {
                    Text("INBOX")
                        .font(Mustard.Type_.meta)
                        .foregroundStyle(Mustard.Palette.textTertiary)
                        .padding(.top, 24).padding(.bottom, 4)
                    ForEach(unscheduled) { task in
                        TimelineRow(task: task) { toggle(task) }
                        Divider().overlay(Mustard.Palette.hairline)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Mustard.Palette.bg)
        .onAppear { DayPlanner.carryForward(allTasks, to: today) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Today").font(.system(size: 22, weight: .medium))
                .foregroundStyle(Mustard.Palette.textPrimary)
            Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Mustard.Type_.body)
                .foregroundStyle(Mustard.Palette.textSecondary)
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private func toggle(_ task: MustardTask) {
        if task.status == .done { task.status = .planned; task.completedAt = nil }
        else { task.markDone() }
    }
}
```

- [ ] **Step 2: Wire it into the app** — replace `MustardApp.swift` body
```swift
import SwiftUI
import SwiftData

@main
struct MustardApp: App {
    var body: some Scene {
        WindowGroup {
            TodayView()
                .frame(minWidth: 520, minHeight: 480)
        }
        .modelContainer(for: [Area.self, TaskList.self, MustardTask.self])
    }
}
```

- [ ] **Step 3: Build**
  ```bash
  xcodebuild build -project ~/Documents/Cavehole/Mustard/Mustard.xcodeproj -scheme Mustard -destination 'platform=macOS'
  ```
  Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run and verify visually (you)** — ⌘R. Confirm: warm off-white window; "Today" + date header; an empty timeline with the capture field. Type a task + Enter → it appears scheduled at 9:00 with a tappable circle; clicking the circle strikes it through in green. Quit and relaunch → the task is still there (SwiftData persisted it to disk).

- [ ] **Step 5: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Views/TodayView.swift Mustard/MustardApp.swift
git commit -m "feat: TodayView timeline wired to SwiftData persistence"
```

---

## Task 11: Preview hook + manual seed verification

**Files:**
- Modify: `Mustard/Views/TodayView.swift` (append a preview)

- [ ] **Step 1: Add a preview using the sample container**
```swift
#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
```

- [ ] **Step 2: Open the Xcode canvas (you)** on `TodayView.swift` → confirm the sample day renders (standup 9:30, focus block 10:00, Thales 11:30) in the calm style, with "Reply to Kamil…" under INBOX.

- [ ] **Step 3: Commit**
```bash
cd ~/Documents/Cavehole/Mustard
git add Mustard/Views/TodayView.swift && git commit -m "chore: TodayView preview with sample data"
```

---

## Definition of done (Plan 1)

- `xcodebuild test … -only-testing:MustardTests` is green (ModelTests + DayPlannerTests).
- `xcodebuild build … -scheme Mustard` succeeds.
- Running the app: capture a task, see it on today's timeline at 9:00, complete it (green strike-through), relaunch and it persists.
- All work committed to the `Mustard` repo.

---

## Self-review notes

- **Spec coverage (this slice):** §5 native SwiftUI + SwiftData ✓; §7 task fields (title, notes, status, owner, scheduledAt, estimate) ✓; §10 today timeline + capture + carry-forward ✓; §3 "calm but dense" via Things-3 tokens ✓. CloudKit (§5), Google Calendar (§9), agent layer (§8), notch/hover (§6) are explicitly deferred to later plans — schema is CloudKit-shaped so that flip is non-breaking.
- **Placeholders:** none — every step has complete code or an exact command + expected output. The only human-led task (1) is human because Xcode project/capability creation genuinely cannot be done from the CLI.
- **Type consistency:** `MustardTask`, `TaskStatus`, `TaskOwner`, `DayPlanner.tasksForDay/unscheduled/carryForward`, `Mustard.Palette.*`, `Mustard.Type_.*` are used identically across Tasks 2–11. `markDone(now:)` signature matches its test and its TodayView call site.
