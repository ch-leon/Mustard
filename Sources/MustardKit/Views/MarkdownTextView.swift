import SwiftUI
import AppKit
import os

/// The live Craft-style editing surface for Notes (spec 2026-07-06, Phase 2a): one
/// always-editable NSTextView whose STRING is byte-identical to the note on disk.
/// Styling is applied purely as NSTextStorage ATTRIBUTES over `NoteDecoration`'s
/// spans — this view never rewrites text, so markdown-as-truth holds structurally.
///
/// `resolveWikilink` colours links (accent when the target resolves, tertiary when
/// it dangles); a click routes the raw target through `onWikilinkTap` — NotesView
/// keeps owning resolution and the create-from-dangling flow, exactly as it did for
/// the old preview.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var resolveWikilink: (String) -> NoteRef? = { _ in nil }
    var onWikilinkTap: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, constructed EXPLICITLY (plan Decision 1). `NSTextView(frame:)`
        // vends a TextKit-2 view on macOS 13+, and any later access to
        // `.layoutManager` silently downgrades TK2 → TK1 mid-session — an entire
        // class of heisenbugs we opt out of by building the classic
        // storage → layout manager → container stack by hand. TK1's stable
        // glyph-range geometry is also what 2b's block gutter will need.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: .greatestFiniteMagnitude))
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
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.typingAttributes = context.coordinator.baseAttributes

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        context.coordinator.isProgrammaticUpdate = false
        context.coordinator.applyDecorations(scopedTo: nil)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

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
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        /// Guards the binding echo: true while WE are mutating the text view, so
        /// `textDidChange` never round-trips a programmatic write into the binding.
        var isProgrammaticUpdate = false
        var didFocus = false
        var fullPassTask: Task<Void, Never>?

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
            case .frontmatter, .codeBlock, .heading, .listMarker: return 0
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
    }
}
