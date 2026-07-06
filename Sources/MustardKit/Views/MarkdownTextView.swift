import SwiftUI
import AppKit
import os

/// UI state for the caret-anchored slash menu (2b Task 7), published by the
/// coordinator through a binding so NoteEditorView can render the overlay.
/// `anchor` is in the editor overlay's coordinate space (top-left origin).
struct SlashMenuState: Equatable {
    var query: String
    /// The "/" + query text in the document — replaced wholesale on commit.
    /// Zero-length for the gutter's "+" path (pure insert at a block start).
    var triggerRange: NSRange
    var anchor: CGRect
    var selectedIndex: Int = 0
}

/// One moveable block's on-screen geometry (2b Task 9), in the editor overlay's
/// coordinate space. `index` matches `BlockReorder.move`'s moveable indexing
/// (frontmatter excluded), so the gutter can hand hit-test results straight through.
struct MarkdownBlockRect: Equatable {
    let index: Int
    let rect: CGRect
}

/// Imperative bridge from NoteEditorView's SwiftUI overlays (slash menu rows,
/// block gutter) into the text-view coordinator. SwiftUI can't hold the NSView;
/// this weak handle routes picks and drags into the ONE undo-safe splice path
/// without any overlay owning AppKit state. Main-thread by convention (every
/// caller is a SwiftUI action) — not @MainActor-annotated so `@State` in a
/// nonisolated view init can construct it.
final class MarkdownEditorProxy {
    weak var coordinator: MarkdownTextView.Coordinator?

    func pick(_ command: SlashCommand) { coordinator?.performSlashCommand(command) }
    func moveBlock(from: Int, to: Int) { coordinator?.moveBlock(from: from, to: to) }
    func openSlashMenu(atBlock index: Int) { coordinator?.openSlashMenu(atBlock: index) }
}

/// Custom attribute grounding the subpage-card drawing (2b Task 10). The card is
/// a `drawBackground` effect keyed off this attribute — deliberately NOT an
/// NSTextAttachment, which would replace characters and break the text == source
/// invariant. The value is the wikilink target (unused by drawing, useful in debug).
extension NSAttributedString.Key {
    static let mustardSubpageCard = NSAttributedString.Key("mustard.subpageCard")
}

/// The live Craft-style editing surface for Notes (spec 2026-07-06, Phase 2a): one
/// always-editable NSTextView whose STRING is byte-identical to the note on disk.
/// Styling is applied purely as NSTextStorage ATTRIBUTES over `NoteDecoration`'s
/// spans — this view never rewrites text, so markdown-as-truth holds structurally.
/// The only text mutations 2b adds — slash-menu insertions and block reorders —
/// splice `SlashMenu.insertion` / `BlockReorder.move` output through
/// `insertText(_:replacementRange:)`, the canonical undoable channel.
///
/// `resolveWikilink` colours links (accent when the target resolves, tertiary when
/// it dangles); a click routes the raw target through `onWikilinkTap` — NotesView
/// keeps owning resolution and the create-from-dangling flow, exactly as it did for
/// the old preview.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var resolveWikilink: (String) -> NoteRef? = { _ in nil }
    var onWikilinkTap: (String) -> Void = { _ in }
    /// Slash menu presentation state, owned by NoteEditorView (which renders the
    /// overlay); the coordinator writes trigger detection into it and reads the
    /// selection for key handling. Defaults to an inert constant so callers that
    /// don't mount the menu never see it.
    var slashMenu: Binding<SlashMenuState?> = Binding<SlashMenuState?>.constant(nil)
    /// Moveable-block geometry publication for the hover gutter (2b Task 9).
    var onBlockRectsChange: ([MarkdownBlockRect]) -> Void = { _ in }
    var proxy: MarkdownEditorProxy? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, constructed EXPLICITLY (plan Decision 1). `NSTextView(frame:)`
        // vends a TextKit-2 view on macOS 13+, and any later access to
        // `.layoutManager` silently downgrades TK2 → TK1 mid-session — an entire
        // class of heisenbugs we opt out of by building the classic
        // storage → layout manager → container stack by hand. TK1's stable
        // glyph-range geometry is also what the 2b block gutter reads
        // (`boundingRect(forGlyphRange:in:)`).
        let textStorage = NSTextStorage()
        // CardLayoutManager only ADDS background drawing for subpage-card ranges;
        // all layout behaviour is inherited.
        let layoutManager = CardLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        let textView = NSTextView(frame: .zero, textContainer: textContainer)

        // Attributes come from us, not the pasteboard — and every automatic
        // substitution is off because it would REWRITE markdown syntax under the
        // user's hands (smart quotes corrupt `"` in code and YAML).
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.font = Theme.NSFonts.reading
        textView.textColor = Theme.NSPalette.textPrimary
        textView.backgroundColor = Theme.NSPalette.bg
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 20, height: 14)
        // Our wikilink spans carry their own colour/underline; empty this so
        // AppKit's default link styling (system blue) doesn't paint over them.
        textView.linkTextAttributes = [NSAttributedString.Key.cursor: NSCursor.pointingHand]
        textView.typingAttributes = context.coordinator.baseAttributes

        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]

        textView.delegate = context.coordinator
        // Layout completion is the gutter's geometry heartbeat (Task 9): block
        // rects are only published once TK1 has settled the glyphs they map.
        layoutManager.delegate = context.coordinator
        context.coordinator.textView = textView
        proxy?.coordinator = context.coordinator

        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        context.coordinator.isProgrammaticUpdate = false
        context.coordinator.applyDecorations(scopedTo: nil)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        // Scrolling moves every block rect in overlay space without triggering
        // layout — observe the clip view so the gutter tracks the scroll.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // First responder is claimed on the next runloop tick — never synchronously
        // during a SwiftUI view update (AppKit reentrancy warnings). ⌘S stays with
        // the SwiftUI Save button's window-level key equivalent, which fires before
        // the field editor.
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        proxy?.coordinator = context.coordinator
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Write the binding into AppKit ONLY when it genuinely differs (external
        // replace: note switch, disk reload). Unconditional writes would round-trip
        // every keystroke SwiftUI → AppKit and teleport the caret.
        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            let selected = textView.selectedRange()
            textView.string = text
            // Preserve (clamp) the selection across the replace.
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, length), length: 0))
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.applyDecorations(scopedTo: nil)
        }

        // Backup focus grab for the rare case the window wasn't attached yet in
        // makeNSView's async hop.
        if !context.coordinator.didFocus, let window = textView.window {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.fullPassTask?.cancel()
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        /// Guards the binding echo: true while WE are mutating the text view, so
        /// `textDidChange` never round-trips a programmatic write into the binding.
        var isProgrammaticUpdate = false
        var didFocus = false
        var fullPassTask: Task<Void, Never>?
        /// True while a slash command or block move is splicing text — trigger
        /// detection and selection-change refresh stand down so the menu doesn't
        /// flicker open mid-splice.
        private var isPerformingEdit = false
        private var rectPublishScheduled = false
        private var lastPublishedRects: [MarkdownBlockRect] = []

        /// Large-note fallback (spec "never block typing"): above this many UTF-16
        /// units decoration is skipped entirely — plain editable text. 200k units
        /// ≈ a 200 KB ASCII note, far past anything hand-written; per-keystroke
        /// block scans and attribute passes stop being provably cheap there.
        static let plainTextFallbackLimit = 200_000

        private static let log = Logger(subsystem: "au.com.codeheroes.mustard", category: "notes")
        private var loggedFallback = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: Theme.NSFonts.reading, .foregroundColor: Theme.NSPalette.textPrimary]
        }

        // MARK: Text changes → binding + invalidation

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Invalidation strategy (plan Task 4): a synchronous pass over ONLY the
            // block under the caret keeps keystroke latency flat; the debounced
            // full pass below catches edits that change block TOPOLOGY (typing a
            // ``` fence, deleting the blank line that separated two blocks, editing
            // frontmatter fences) which the scoped pass can't see.
            applyDecorations(scopedTo: caretBlock(in: textView))
            scheduleFullPass()
            refreshSlashMenu()
        }

        /// The partition block containing the caret in the NEW string (recomputing
        /// `NoteDecoration.blocks` is a single cheap line scan).
        private func caretBlock(in textView: NSTextView) -> NoteDecoration.Block? {
            let source = textView.string
            let blocks = NoteDecoration.blocks(source)
            let caret = textView.selectedRange().location
            return blocks.first { NSLocationInRange(caret, $0.range) } ?? blocks.last
        }

        private func scheduleFullPass() {
            fullPassTask?.cancel()
            fullPassTask = Task { @MainActor [weak self] in
                // ~150 ms: settles between keystrokes, cancelled by the next edit.
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                self?.applyDecorations(scopedTo: nil)
            }
        }

        // MARK: Decoration application (attributes ONLY — undo-safe)

        /// Applies `NoteDecoration` spans as text attributes — for one block (the
        /// per-keystroke fast path) or the whole document (nil).
        ///
        /// Undo safety: these are attribute-only edits written straight to
        /// `textStorage`, bypassing `shouldChangeText`/`didChangeText` — so they
        /// never enter NSTextView's undo stack and never dirty the SwiftUI binding.
        /// The `isProgrammaticUpdate` guard is belt-and-braces on top: if anything
        /// ever does re-fire `textDidChange` from here, it must not echo into the
        /// binding as a phantom user edit.
        func applyDecorations(scopedTo block: NoteDecoration.Block?) {
            guard let textView, let storage = textView.textStorage else { return }
            let source = textView.string
            let ns = source as NSString

            guard ns.length <= Self.plainTextFallbackLimit else {
                if !loggedFallback {
                    loggedFallback = true
                    Self.log.info("Note exceeds \(Self.plainTextFallbackLimit) UTF-16 units — decoration off, plain text editing")
                }
                return
            }
            loggedFallback = false

            let targets = block.map { [$0] } ?? NoteDecoration.blocks(source)
            isProgrammaticUpdate = true
            storage.beginEditing()
            for target in targets {
                // Stale-range guard: a scoped block was computed from this same
                // string, but never trust a range against a storage we don't own.
                guard target.range.upperBound <= storage.length else { continue }
                storage.setAttributes(baseAttributes, range: target.range)
                // Layering order: line-level kinds ground the range, inline content
                // styles on top, markers de-emphasize last.
                for span in NoteDecoration.spans(source, in: target)
                    .sorted(by: { Self.priority($0.kind) < Self.priority($1.kind) }) {
                    apply(span, to: storage)
                }
            }
            storage.endEditing()
            isProgrammaticUpdate = false
        }

        private static func priority(_ kind: NoteDecoration.Kind) -> Int {
            switch kind {
            case .frontmatter, .codeBlock, .heading, .listMarker, .subpageCard: return 0
            case .bold, .italic, .inlineCode, .wikilink: return 1
            case .marker: return 2
            }
        }

        private func apply(_ span: NoteDecoration.Span, to storage: NSTextStorage) {
            let range = span.range
            switch span.kind {
            case .frontmatter:
                storage.addAttributes([.font: Theme.NSFonts.frontmatter,
                                       .foregroundColor: Theme.NSPalette.textTertiary], range: range)
            case .heading(let level):
                storage.addAttributes([.font: Self.headingFont(level),
                                       .foregroundColor: Theme.NSPalette.textPrimary], range: range)
            case .marker:
                storage.addAttributes([.font: Theme.NSFonts.marker,
                                       .foregroundColor: Theme.NSPalette.textTertiary], range: range)
            case .bold:
                storage.addAttribute(.font, value: Theme.NSFonts.readingBold, range: range)
            case .italic:
                storage.addAttribute(.font, value: Theme.NSFonts.readingItalic, range: range)
            case .inlineCode:
                storage.addAttributes([.font: Theme.NSFonts.code,
                                       .backgroundColor: Theme.NSPalette.surface], range: range)
            case .codeBlock:
                storage.addAttributes([.font: Theme.NSFonts.code,
                                       .backgroundColor: Theme.NSPalette.surface], range: range)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: Theme.NSPalette.textTertiary, range: range)
            case .wikilink(let target, _):
                var attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: parent.resolveWikilink(target) != nil
                        ? Theme.NSPalette.accent : Theme.NSPalette.textTertiary,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .cursor: NSCursor.pointingHand,
                ]
                if let url = WikilinkURL.url(for: target) { attributes[.link] = url }
                storage.addAttributes(attributes, range: range)
            case .subpageCard(let target):
                // Attribute-only ground for CardLayoutManager.drawBackground —
                // no character is added or replaced (no NSTextAttachment).
                storage.addAttribute(NSAttributedString.Key.mustardSubpageCard,
                                     value: target, range: range)
            }
        }

        private static func headingFont(_ level: Int) -> NSFont {
            switch level {
            case 1: return Theme.NSFonts.docH1
            case 2: return Theme.NSFonts.docH2
            default: return Theme.NSFonts.docH3
            }
        }

        // MARK: Link clicks

        /// Wikilink clicks route to the host's existing navigate / create-from-
        /// dangling flow (save-on-switch still fires because navigation goes
        /// through NotesView's `selected`). Foreign URLs fall through to AppKit.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, let target = WikilinkURL.target(from: url) else { return false }
            parent.onWikilinkTap(target)
            return true
        }

        // MARK: Slash menu — trigger detection (2b Task 7)

        /// Recomputes the slash-menu state from the caret's line prefix. Runs on
        /// every text change; also on selection change WHILE OPEN (so arrowing or
        /// clicking out of the trigger closes it) — but a pure selection change
        /// never OPENS the menu, so clicking into old "/query" text is calm.
        private func refreshSlashMenu(allowOpen: Bool = true) {
            guard !isPerformingEdit else { return }
            guard let textView else { return }
            let wasOpen = parent.slashMenu.wrappedValue != nil
            guard allowOpen || wasOpen else { return }

            let selection = textView.selectedRange()
            let ns = textView.string as NSString
            guard selection.length == 0, selection.location <= ns.length,
                  let query = triggerQuery(ns, caret: selection.location),
                  !SlashMenu.items(query: query.text).isEmpty
            else {
                if wasOpen { parent.slashMenu.wrappedValue = nil }
                return
            }

            let previous = parent.slashMenu.wrappedValue
            let keptIndex = (previous?.query == query.text) ? (previous?.selectedIndex ?? 0) : 0
            let itemCount = SlashMenu.items(query: query.text).count
            parent.slashMenu.wrappedValue = SlashMenuState(
                query: query.text,
                triggerRange: query.range,
                anchor: overlayRect(forCharacterAt: query.range.location) ?? CGRect.zero,
                selectedIndex: min(keptIndex, itemCount - 1)
            )
        }

        /// The active trigger at the caret: `SlashMenu.activeQuery` over the line
        /// prefix, plus the trigger's document range ("/"+query, from line start).
        private func triggerQuery(_ ns: NSString, caret: Int) -> (text: String, range: NSRange)? {
            let start = lineStart(ns, before: caret)
            let prefix = ns.substring(with: NSRange(location: start, length: caret - start))
            guard let query = SlashMenu.activeQuery(linePrefix: prefix) else { return nil }
            return (text: query, range: NSRange(location: start, length: caret - start))
        }

        /// Manual backward scan for the line start — sidesteps `getLineStart`'s
        /// undocumented caret-at-end edge (caret == length is routine here).
        private func lineStart(_ ns: NSString, before location: Int) -> Int {
            var index = min(location, ns.length)
            while index > 0 {
                let unit = ns.character(at: index - 1)
                if unit == 10 || unit == 13 { break }   // \n or \r
                index -= 1
            }
            return index
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Close-only path: never opens (allowOpen false).
            guard parent.slashMenu.wrappedValue != nil else { return }
            refreshSlashMenu(allowOpen: false)
        }

        /// ↑/↓/⏎/Esc are intercepted ONLY while the slash menu is open — never
        /// steal arrows or return during normal editing (plan risk register).
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard var menu = parent.slashMenu.wrappedValue else { return false }
            let items = SlashMenu.items(query: menu.query)
            guard !items.isEmpty else { return false }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                menu.selectedIndex = min(menu.selectedIndex + 1, items.count - 1)
                parent.slashMenu.wrappedValue = menu
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                menu.selectedIndex = max(menu.selectedIndex - 1, 0)
                parent.slashMenu.wrappedValue = menu
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                performSlashCommand(items[min(menu.selectedIndex, items.count - 1)])
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.slashMenu.wrappedValue = nil
                return true
            }
            return false
        }

        // MARK: Slash menu — execution (the undo-safe splice)

        /// Commits one slash command: replaces the trigger text with the command's
        /// byte-pinned template via `insertText(_:replacementRange:)` — the ONE
        /// channel every 2b text mutation uses, so it lands in the undo stack as a
        /// single user-visible operation and fires `textDidChange` → binding →
        /// dirty dot, exactly like typing.
        func performSlashCommand(_ command: SlashCommand) {
            guard let textView, let menu = parent.slashMenu.wrappedValue else { return }

            // Sub-page inserts a DANGLING [[Untitled]] link — no file is created
            // here. The deep-review panel showed why: creating the file before an
            // undoable splice makes ⌘Z asymmetric (text reverts, file persists)
            // and every undo→retry cycle minted an orphan "Untitled N". A slash
            // command is now pure text; the existing confirmed
            // create-from-dangling flow (click → "Create note?") owns creation.
            let insertion = SlashMenu.insertion(for: command.kind, noteTitle: nil)
            isPerformingEdit = true
            // Isolate from adjacent typing so ⌘Z removes exactly this insertion.
            textView.breakUndoCoalescing()
            textView.insertText(insertion.text, replacementRange: menu.triggerRange)
            textView.breakUndoCoalescing()
            textView.setSelectedRange(NSRange(location: menu.triggerRange.location + insertion.caretOffset,
                                              length: 0))
            isPerformingEdit = false
            parent.slashMenu.wrappedValue = nil
            textView.window?.makeFirstResponder(textView)
        }

        /// The gutter's "+" path: open the menu anchored at a block's start with an
        /// empty query and a zero-length trigger (a pure insert — commit splices at
        /// the block's first character, which is always a line start).
        func openSlashMenu(atBlock index: Int) {
            guard let textView else { return }
            let moveable = NoteDecoration.blocks(textView.string).filter { !$0.isFrontmatter }
            guard index >= 0, index < moveable.count else { return }
            let location = moveable[index].range.location
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            parent.slashMenu.wrappedValue = SlashMenuState(
                query: "",
                triggerRange: NSRange(location: location, length: 0),
                anchor: overlayRect(forCharacterAt: location) ?? CGRect.zero,
                selectedIndex: 0
            )
        }

        // MARK: Block reorder (2b Task 9)

        /// Applies `BlockReorder.move` as ONE undoable edit. The whole-document
        /// splice goes through `insertText(_:replacementRange:)` — the same
        /// canonical channel as slash insertions — wrapped in an explicit undo
        /// group and bracketed by `breakUndoCoalescing` so ⌘Z restores the previous
        /// order in exactly one step, never merged with surrounding typing. The
        /// SwiftUI binding updates through the normal `textDidChange` path, so the
        /// dirty dot and ⌘S semantics hold with zero new save code.
        func moveBlock(from: Int, to: Int) {
            guard let textView else { return }
            let current = textView.string
            let moved = BlockReorder.move(current, from: from, to: to)
            guard moved != current else { return }

            let fullRange = NSRange(location: 0, length: (current as NSString).length)
            let savedSelection = textView.selectedRange()
            let clipView = textView.enclosingScrollView?.contentView
            let savedScrollOrigin = clipView?.bounds.origin

            isPerformingEdit = true
            textView.breakUndoCoalescing()
            textView.undoManager?.beginUndoGrouping()
            textView.insertText(moved, replacementRange: fullRange)
            textView.undoManager?.endUndoGrouping()
            textView.breakUndoCoalescing()
            isPerformingEdit = false

            // A whole-document splice invalidates every block — the caret-scoped
            // pass that ran inside textDidChange can't cover it, and waiting for
            // the 150 ms debounce would flash undecorated text.
            applyDecorations(scopedTo: nil)

            // Restore caret (clamped) and scroll — a reorder must not teleport
            // the viewport (plan: "caret and scroll don't jump").
            let newLength = (moved as NSString).length
            textView.setSelectedRange(NSRange(location: min(savedSelection.location, newLength),
                                              length: 0))
            if let clipView, let savedScrollOrigin {
                clipView.scroll(to: savedScrollOrigin)
                textView.enclosingScrollView?.reflectScrolledClipView(clipView)
            }
        }

        // MARK: Block rect publication (2b Task 9)

        /// TK1 layout heartbeat: once layout settles, recompute block geometry.
        func layoutManager(_ layoutManager: NSLayoutManager,
                           didCompleteLayoutFor textContainer: NSTextContainer?,
                           atEnd layoutFinishedFlag: Bool) {
            guard layoutFinishedFlag else { return }
            schedulePublishBlockRects()
        }

        @objc func clipViewBoundsDidChange(_ notification: Notification) {
            schedulePublishBlockRects()
        }

        /// Coalesces to one publication per runloop turn — layout/scroll callbacks
        /// arrive in bursts, and each publication is a SwiftUI state write. Also
        /// hops off the layout pass itself (mutating SwiftUI state mid-layout is
        /// reentrancy roulette).
        private func schedulePublishBlockRects() {
            guard !rectPublishScheduled else { return }
            rectPublishScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rectPublishScheduled = false
                self.publishBlockRects()
            }
        }

        private func publishBlockRects() {
            guard let textView,
                  let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            let source = textView.string
            var rects: [MarkdownBlockRect] = []
            // Large-note fallback: no decoration → no handles; typing still works.
            if (source as NSString).length <= Self.plainTextFallbackLimit {
                let moveable = NoteDecoration.blocks(source).filter { !$0.isFrontmatter }
                for (index, block) in moveable.enumerated() {
                    guard block.range.upperBound <= (source as NSString).length else { continue }
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range,
                                                              actualCharacterRange: nil)
                    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let origin = textView.textContainerOrigin
                    rect.origin.x += origin.x
                    rect.origin.y += origin.y
                    let inScrollView = scrollView.convert(rect, from: textView)
                    rects.append(MarkdownBlockRect(index: index,
                                                   rect: flipToOverlay(inScrollView, in: scrollView)))
                }
            }
            if rects != lastPublishedRects {
                lastPublishedRects = rects
                parent.onBlockRectsChange(rects)
            }
        }

        // MARK: Overlay-space geometry

        /// Caret/character rect in the editor overlay's space (top-left origin) —
        /// the scroll view IS the representable's bounds, so SwiftUI overlays and
        /// these rects share one coordinate system.
        private func overlayRect(forCharacterAt location: Int) -> CGRect? {
            guard let textView,
                  let scrollView = textView.enclosingScrollView,
                  let window = textView.window
            else { return nil }
            let screenRect = textView.firstRect(forCharacterRange: NSRange(location: location, length: 0),
                                                actualRange: nil)
            let windowRect = window.convertFromScreen(screenRect)
            let inScrollView = scrollView.convert(windowRect, from: nil)
            return flipToOverlay(inScrollView, in: scrollView)
        }

        /// AppKit's unflipped views put y at the bottom; SwiftUI overlays measure
        /// from the top. One flip, one place.
        private func flipToOverlay(_ rect: CGRect, in view: NSView) -> CGRect {
            guard !view.isFlipped else { return rect }
            return CGRect(x: rect.minX,
                          y: view.bounds.height - rect.maxY,
                          width: rect.width,
                          height: rect.height)
        }
    }
}

// MARK: - Subpage-card drawing (2b Task 10)

/// TK1 layout manager that draws a Craft-style card BEHIND any range carrying the
/// `.mustardSubpageCard` attribute (set by the decoration pass for lines that are
/// exactly one bare wikilink). Drawing only — characters, caret movement, selection
/// and undo are untouched; the caret can enter the line and edit the raw `[[...]]`.
final class CardLayoutManager: NSLayoutManager {

    /// `doc.text` tinted to the tertiary token, rendered once. Bridged from
    /// `Theme.NSPalette` — never fresh hex.
    private static let cardIcon: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: NSFont.Weight.regular)
        guard let symbol = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let size = symbol.size
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            Theme.NSPalette.textTertiary.set()
            rect.fill(using: NSCompositingOperation.sourceAtop)
            return true
        }
    }()

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(NSAttributedString.Key.mustardSubpageCard,
                                   in: charRange,
                                   options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            var rect = self.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y

            // Card chrome: slight outset, extra leading room for the glyph.
            var cardRect = rect.insetBy(dx: -4.0, dy: -2.0)
            let iconGutter: CGFloat = 18.0
            cardRect.origin.x -= iconGutter
            cardRect.size.width += iconGutter

            let path = NSBezierPath(roundedRect: cardRect,
                                    xRadius: Theme.Metrics.rLg,
                                    yRadius: Theme.Metrics.rLg)
            Theme.NSPalette.bg.setFill()
            path.fill()
            Theme.NSPalette.hairline.setStroke()
            path.lineWidth = 1.0
            path.stroke()

            if let icon = CardLayoutManager.cardIcon {
                let iconRect = NSRect(x: cardRect.minX + 6.0,
                                      y: cardRect.midY - icon.size.height / 2.0,
                                      width: icon.size.width,
                                      height: icon.size.height)
                icon.draw(in: iconRect,
                          from: NSRect.zero,
                          operation: NSCompositingOperation.sourceOver,
                          fraction: 1.0,
                          respectFlipped: true,
                          hints: nil)
            }
        }
    }
}
