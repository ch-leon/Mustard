# Well-formed Tasks from Meetings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn raw meeting action-item lines into well-formed tasks — concise title, proper description, meeting reference, correct due date, topic tags — instead of one giant title.

**Architecture:** The vault-side `sync-meeting` skill emits a contract-stable line carrying a skill-authored `desc:`. Mustard's pure `MeetingTaskParser` splits the action clause into the title and extracts `desc`/`owner`/`due:`/`#tags`/`[T:"…"]`; `MeetingTaskSync` composes notes and populates `dueAt`/`tags`, and heals already-imported giant-title tasks once.

**Tech Stack:** Swift, SwiftData, XCTest. Spec: `docs/specs/2026-06-30-meeting-task-creation-design.md`.

---

### Task 1: Parser — split title, extract fields

**Files:**
- Modify: `Sources/MustardKit/Logic/MeetingTaskParser.swift`
- Test: `Tests/MustardTests/MeetingTaskParserTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `MeetingTaskParserTests`:

```swift
func test_skillLine_titleIsActionClauseOnly() {
    let note = """
    ## Code Heroes tasks
    - [ ] Move credentials to production — desc: "Promote the traffic-controller and dangerous-goods-driver credentials.", owner: Code Heroes, due: 2026-07-15 #task #creds #ch — [T: "targeting production imminently"]
    """
    let t = MeetingTaskParser.parse(note, notePath: "DL/m.md")[0]
    XCTAssertEqual(t.title, "Move credentials to production")
    XCTAssertEqual(t.desc, "Promote the traffic-controller and dangerous-goods-driver credentials.")
    XCTAssertEqual(t.owner, "Code Heroes")
    XCTAssertEqual(t.dueText, "2026-07-15")
    XCTAssertEqual(t.due, at("2026-07-15T00:00:00Z"))
    XCTAssertEqual(t.tags, ["creds"])
    XCTAssertEqual(t.transcriptQuote, "targeting production imminently")
}

func test_dueTextForms_nonDateLeavesDueNil() {
    let note = """
    ## Code Heroes tasks
    - [ ] Progress the launch — owner: Code Heroes, due: not stated #task #ch — [T: "q"]
    - [ ] Ship it — owner: Code Heroes, due: imminent #task #ch — [T: "q2"]
    """
    let ts = MeetingTaskParser.parse(note, notePath: "DL/m.md")
    XCTAssertEqual(ts[0].dueText, "not stated"); XCTAssertNil(ts[0].due)
    XCTAssertEqual(ts[1].dueText, "imminent");   XCTAssertNil(ts[1].due)
}

func test_wikilinkStrippedFromTitle_andOwner() {
    let note = """
    ## Code Heroes tasks
    - [ ] Request [[Kamil]] to send the SDK spec — owner: [[Leon Creed-Baker]], due: not stated #task #ch — [T: "q"]
    """
    let t = MeetingTaskParser.parse(note, notePath: "DL/m.md")[0]
    XCTAssertEqual(t.title, "Request Kamil to send the SDK spec")
    XCTAssertEqual(t.owner, "Leon Creed-Baker")
}

func test_plainLine_noEmDash_backwardCompatible() {
    let note = """
    ## Code Heroes tasks
    - [ ] Email Kamil the SDK spec 📅 2026-06-20
    """
    let t = MeetingTaskParser.parse(note, notePath: "m.md")[0]
    XCTAssertEqual(t.title, "Email Kamil the SDK spec")
    XCTAssertEqual(t.due, at("2026-06-20T00:00:00Z"))
    XCTAssertNil(t.desc); XCTAssertNil(t.transcriptQuote); XCTAssertEqual(t.tags, [])
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter MeetingTaskParserTests`
Expected: FAIL — `ParsedMeetingTask` has no `desc`/`owner`/`dueText`/`tags`/`transcriptQuote`.

- [ ] **Step 3: Extend `ParsedMeetingTask`**

Replace the struct in `MeetingTaskParser.swift`:

```swift
public struct ParsedMeetingTask: Equatable {
    public let title: String
    public let isDone: Bool
    public let due: Date?
    /// Skill-authored 1–2 sentence description (nil on plain/legacy lines).
    public let desc: String?
    /// Owner annotation with wikilink brackets stripped (nil if absent).
    public let owner: String?
    /// Raw `due:` text — "imminent" / "not stated" / ISO date (nil if absent).
    public let dueText: String?
    /// Transcript citation from `[T: "…"]` (nil if absent).
    public let transcriptQuote: String?
    /// Topic tags, `#` stripped, structural `#task`/`#ch` removed.
    public let tags: [String]
    /// The original line verbatim — kept so the sync can re-locate it for write-back.
    public let rawLine: String
    public let notePath: String
    /// Stable identity for dedup + line-locating (see `originKey`).
    public let originKey: String
}
```

- [ ] **Step 4: Update `parse` + add extractors**

In `parse(_:notePath:)`, replace the `out.append(...)` call with:

```swift
out.append(
    ParsedMeetingTask(
        title: extractTitle(rawLine),
        isDone: isChecked(rawLine),
        due: dueDate(rawLine),
        desc: quotedField(rawLine, label: "desc"),
        owner: stripWikilinks(field(rawLine, label: "owner")),
        dueText: field(rawLine, label: "due"),
        transcriptQuote: transcriptQuote(rawLine),
        tags: tags(rawLine),
        rawLine: rawLine,
        notePath: notePath,
        originKey: originKey(notePath: notePath, line: rawLine)
    )
)
```

Replace `extractTitle` and add the helpers:

```swift
/// Action clause = text before the first em-dash separator (the skill guarantees
/// the action contains no `—`). Plain Obsidian-Tasks lines have no `—` → whole line.
static func extractTitle(_ line: String) -> String {
    var s = line.replacingOccurrences(of: checkboxPrefix, with: "", options: .regularExpression)
    if let i = s.firstIndex(of: "\u{2014}") { s = String(s[..<i]) }
    s = s.replacingOccurrences(of: donePattern, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: duePattern, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: blockIdSuffix, with: "", options: .regularExpression)
    s = stripWikilinks(s) ?? ""
    s = s.replacingOccurrences(of: #"#[\w-]+"#, with: "", options: .regularExpression)
    var kept = String.UnicodeScalarView()
    for scalar in s.unicodeScalars where !metaEmoji.contains(scalar) { kept.append(scalar) }
    return collapseWhitespace(String(kept))
}

/// `label: value` where value runs to the next comma, `#`, em-dash, or end.
static func field(_ line: String, label: String) -> String? {
    guard let r = line.range(of: "\(label):\\s*([^,#\u{2014}]+)", options: .regularExpression) else { return nil }
    let raw = String(line[r]).replacingOccurrences(of: "\(label):", with: "")
    let v = raw.trimmingCharacters(in: .whitespaces)
    return v.isEmpty ? nil : v
}

/// `label: "value"` — the quoted form used by `desc:`.
static func quotedField(_ line: String, label: String) -> String? {
    guard let r = line.range(of: "\(label):\\s*\"([^\"]*)\"", options: .regularExpression),
          let q = line[r].range(of: "\"[^\"]*\"", options: .regularExpression) else { return nil }
    let v = String(line[r][q]).dropFirst().dropLast()
    return v.isEmpty ? nil : String(v)
}

static func transcriptQuote(_ line: String) -> String? {
    guard let r = line.range(of: #"\[T:\s*"[^"]*"\]"#, options: .regularExpression),
          let q = line[r].range(of: "\"[^\"]*\"", options: .regularExpression) else { return nil }
    let v = String(line[r][q]).dropFirst().dropLast()
    return v.isEmpty ? nil : String(v)
}

/// `#tags` minus the structural `#task`/`#ch`, leading `#` stripped.
static func tags(_ line: String) -> [String] {
    let skip: Set<String> = ["task", "ch"]
    var out: [String] = []
    var idx = line.startIndex
    while let r = line.range(of: #"#[\w-]+"#, options: .regularExpression, range: idx..<line.endIndex) {
        let tag = String(line[r].dropFirst())
        if !skip.contains(tag.lowercased()) { out.append(tag) }
        idx = r.upperBound
    }
    return out
}

/// Strip `[[wikilink]]` → inner text. Returns nil only for nil input.
static func stripWikilinks(_ s: String?) -> String? {
    guard let s else { return nil }
    return s.replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
}
```

Replace `dueDate` to read the `due:` text form first, `📅` as fallback:

```swift
static func dueDate(_ line: String) -> Date? {
    if let r = line.range(of: #"due:\s*\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
       let dr = line[r].range(of: isoDate, options: .regularExpression) {
        return dateFormatter.date(from: String(line[r][dr]))
    }
    if let r = line.range(of: duePattern, options: .regularExpression),
       let dr = line[r].range(of: isoDate, options: .regularExpression) {
        return dateFormatter.date(from: String(line[r][dr]))
    }
    return nil
}
```

- [ ] **Step 5: Run, verify pass**

Run: `swift test --filter MeetingTaskParserTests`
Expected: PASS (new tests + the existing fixtures via the no-em-dash fallback).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Logic/MeetingTaskParser.swift Tests/MustardTests/MeetingTaskParserTests.swift
git commit -m "feat(meeting): parse action clause, desc, owner, due:, tags from meeting lines (BAK-82)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Sync — compose notes, set tags + dueAt

**Files:**
- Modify: `Sources/MustardKit/Agent/MeetingTaskSync.swift`
- Test: `Tests/MustardTests/MeetingTaskSyncTests.swift`

- [ ] **Step 1: Write failing test**

Add to `MeetingTaskSyncTests` (a pure unit on `composeNotes`, no store):

```swift
func test_composeNotes_descMeetingOwnerDue() {
    let p = ParsedMeetingTask(
        title: "Move credentials to production", isDone: false,
        due: nil, desc: "Promote the creds to prod.", owner: "Code Heroes",
        dueText: "imminent", transcriptQuote: "targeting production imminently",
        tags: ["creds"], rawLine: "-", notePath: "DL/meetings/2026/04/2026-04-17-x.md",
        originKey: "k")
    let notes = MeetingTaskSync.composeNotes(p, subtitle: "DLA/DLV Feature Showcase")
    XCTAssertEqual(notes, """
    Promote the creds to prod.

    From: DLA/DLV Feature Showcase (2026-04-17)
    Context: "targeting production imminently"
    Owner: Code Heroes · Due: imminent
    """)
}

func test_composeNotes_fallsBackToQuoteWhenNoDesc() {
    let p = ParsedMeetingTask(
        title: "Ship it", isDone: false, due: nil, desc: nil, owner: nil,
        dueText: nil, transcriptQuote: "we will ship", tags: [],
        rawLine: "-", notePath: "DL/m.md", originKey: "k")
    let notes = MeetingTaskSync.composeNotes(p, subtitle: "Standup")
    XCTAssertEqual(notes, "we will ship\n\nFrom: Standup")
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter MeetingTaskSyncTests`
Expected: FAIL — `composeNotes` does not exist.

- [ ] **Step 3: Add `composeNotes` + populate in `makeTask`**

Add to `MeetingTaskSync` (static, pure, testable):

```swift
/// Notes body = description (or transcript quote fallback), then a provenance
/// footer referencing the meeting, the quote, and owner/due.
static func composeNotes(_ p: ParsedMeetingTask, subtitle: String) -> String {
    let body = (p.desc?.isEmpty == false ? p.desc! : (p.transcriptQuote ?? "")).trimmingCharacters(in: .whitespaces)
    var footer: [String] = []
    var from = subtitle
    if let d = noteDate(p.notePath) { from += from.isEmpty ? d : " (\(d))" }
    if !from.isEmpty { footer.append("From: \(from)") }
    if let q = p.transcriptQuote, !q.isEmpty, q != body { footer.append("Context: \"\(q)\"") }
    var meta: [String] = []
    if let o = p.owner, !o.isEmpty { meta.append("Owner: \(o)") }
    if let d = p.dueText, !d.isEmpty { meta.append("Due: \(d)") }
    if !meta.isEmpty { footer.append(meta.joined(separator: " · ")) }
    var out: [String] = []
    if !body.isEmpty { out.append(body) }
    if !footer.isEmpty { if !out.isEmpty { out.append("") }; out.append(contentsOf: footer) }
    return out.joined(separator: "\n")
}

/// Best-effort `YYYY-MM-DD` lifted from the meeting note path.
static func noteDate(_ path: String) -> String? {
    guard let r = path.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
    return String(path[r])
}
```

In `makeTask`, after `task.dueAt = p.due`, add:

```swift
task.notes = Self.composeNotes(p, subtitle: subtitle)
task.tags = p.tags
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter MeetingTaskSyncTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/MeetingTaskSync.swift Tests/MustardTests/MeetingTaskSyncTests.swift
git commit -m "feat(meeting): compose task notes + tags from parsed meeting line (BAK-82)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Heal already-imported giant-title tasks

**Files:**
- Modify: `Sources/MustardKit/Agent/MeetingTaskSync.swift:71` (the matched-by-originKey branch in `importTasks`)
- Test: `Tests/MustardTests/MeetingTaskSyncTests.swift`

- [ ] **Step 1: Write failing test**

Add (use the suite's existing in-memory `ModelContext`/stub-IO helper — mirror the
nearest existing test in the file for setup):

```swift
func test_import_healsLegacyGiantTitleTaskOnce() throws {
    // A note whose line now parses to a concise title.
    let line = "- [ ] Email Kamil — desc: \"Send the SDK spec to Kamil.\", owner: [[Leon Creed-Baker]], due: not stated #task #sdk #ch — [T: \"send Kamil the spec\"]"
    let note = "# Sync 2026-06-16\n\n## Code Heroes tasks\n\(line)\n"
    let io = StubIO(files: ["DL/m.md": note])      // mirror existing StubIO usage
    let sync = MeetingTaskSync(context: context, io: io)

    // Seed a legacy task: giant title (the raw action+meta), empty notes, same originKey.
    let legacy = MustardTask(title: line, owner: .me)
    legacy.source = "meeting"; legacy.sourceURL = "DL/m.md"; legacy.notes = ""
    legacy.originKey = MeetingTaskParser.originKey(notePath: "DL/m.md", line: line)
    context.insert(legacy)

    sync.importTasks()
    XCTAssertEqual(legacy.title, "Email Kamil")
    XCTAssertTrue(legacy.notes.contains("Send the SDK spec to Kamil."))
    XCTAssertEqual(legacy.tags, ["sdk"])

    // Idempotent: a manual notes edit survives a second sweep.
    legacy.notes = "manually edited"; legacy.title = "Email Kamil"
    sync.importTasks()
    XCTAssertEqual(legacy.notes, "manually edited")
}
```

> If the existing suite names its stub IO differently, match that name; the assertions are what matter.

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter MeetingTaskSyncTests/test_import_healsLegacyGiantTitleTaskOnce`
Expected: FAIL — legacy title unchanged, notes empty.

- [ ] **Step 3: Add heal in the matched branch**

In `importTasks`, the `if let task = byKey[parsed.originKey] {` branch, insert at the
top of the block (before the done/undone reconciliation):

```swift
// Heal legacy giant-title imports once: only when notes was never populated and
// the freshly-parsed concise title differs. Gated to live (non-archived) meeting
// tasks so manual edits and pruned rows are never clobbered.
if task.source == "meeting", task.notes.isEmpty, task.title != parsed.title {
    task.title = parsed.title
    task.notes = Self.composeNotes(parsed, subtitle: subtitle)
    task.tags = parsed.tags
    if task.dueAt == nil { task.dueAt = parsed.due }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter MeetingTaskSyncTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/MeetingTaskSync.swift Tests/MustardTests/MeetingTaskSyncTests.swift
git commit -m "feat(meeting): heal legacy giant-title tasks on import (BAK-82)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: sync-meeting skill — emit `desc:` + contract note (local-only)

**Files:**
- Modify: `/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work/.claude/skills/sync-meeting/SKILL.md` (Step 4 + Step 6 task-line template)

> **Not committed/pushed.** That repo holds tracked secrets and is never pushed
> (see memory). This is a local skill edit only.

- [ ] **Step 1: Update the task-line template (Step 6)**

Replace the two example task lines under `## Code Heroes tasks` with:

```markdown
- [ ] <concise action — NO em-dash in this clause> — desc: "<1–2 sentence description of what needs doing>", owner: [[Leon Creed-Baker]], due: <YYYY-MM-DD or "not stated"> #task #<topic> #ch — [T: "quote"]
- [ ] Request [[Name]] to <action they own but missed by being absent> — desc: "<1–2 sentence description>", owner: [[Leon Creed-Baker]], due: <…> #task #<topic> #ch — [T: "quote"]
```

- [ ] **Step 2: Add a contract rule (Step 4, near Citations)**

Add a bullet:

```markdown
- **Task-line contract (Mustard parses these):** the **action clause before the
  first ` — ` must be a concise, standalone title and MUST NOT contain an em-dash
  `—`** (use hyphens/colons). Put the elaboration in `desc: "…"` (1–2 sentences,
  what needs doing). Mustard uses the action as the task title, `desc:` as the
  description, `due:` as the due date, non-`#task`/`#ch` tags as task tags, and the
  `[T: "…"]` quote as context.
```

- [ ] **Step 3: Verify (manual)**

No automated test (prompt change). Confirm the edited lines read correctly and the
contract bullet is present.

---

### Task 5: Full verification

- [ ] **Step 1: Whole suite**

Run: `swift test`
Expected: PASS (all suites, including the pre-existing 73).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: State evidence**

Report the `swift test` summary line and `swift build` result. Do not claim the
view "looks right" — Leon confirms the board visually after the next sweep heals
existing tasks.
