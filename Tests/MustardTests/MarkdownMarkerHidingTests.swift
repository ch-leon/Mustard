import XCTest
import AppKit
import SwiftUI
@testable import MustardKit

/// Marker hiding must survive real layout passes. `setNotShownAttribute` is transient
/// typesetter state — TextKit wipes it whenever layout regenerates (first display,
/// resize, scroll), which is why markers stayed visible in the running app while the
/// pure NoteDecoration logic was correct. The durable mechanism marks hidden-marker
/// glyphs `.null` during glyph generation (NSLayoutManagerDelegate), so every layout
/// pass re-establishes hiding by construction.
@MainActor
final class MarkdownMarkerHidingTests: XCTestCase {
    private let source = """
    ---
    title: probe
    ---

    # A heading

    **Bold lead** and a paragraph.

    ## Second heading
    """

    private struct Editor {
        let coordinator: MarkdownTextView.Coordinator
        let layoutManager: NSLayoutManager
        let container: NSTextContainer
        let textView: NSTextView
        let window: NSWindow
    }

    /// Build the exact stack makeNSView builds, hosted in an offscreen window, and
    /// run the makeNSView(empty) → updateNSView(document) sequence the app runs.
    private func makeEditor(_ text: String) -> Editor {
        let parent = MarkdownTextView(text: .constant(text))
        let coordinator = MarkdownTextView.Coordinator(parent)

        let textStorage = NSTextStorage()
        let layoutManager = CardLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 600), textContainer: container)
        textView.isRichText = false
        textView.font = Theme.NSFonts.reading
        textView.delegate = coordinator
        layoutManager.delegate = coordinator
        coordinator.textView = textView

        coordinator.isProgrammaticUpdate = true
        textView.string = ""
        coordinator.isProgrammaticUpdate = false
        coordinator.applyDecorations(scopedTo: nil)
        coordinator.refreshMarkerVisibility(fullRecompute: true)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        scrollView.documentView = textView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(scrollView)

        coordinator.isProgrammaticUpdate = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.isProgrammaticUpdate = false
        coordinator.applyDecorations(scopedTo: nil)
        coordinator.refreshMarkerVisibility(fullRecompute: true)

        return Editor(coordinator: coordinator, layoutManager: layoutManager,
                      container: container, textView: textView, window: window)
    }

    private func isHidden(_ editor: Editor, _ needle: String, markerLength: Int) -> Bool {
        let ns = editor.textView.string as NSString
        let range = ns.range(of: needle)
        precondition(range.location != NSNotFound, "needle missing from fixture")
        let glyph = editor.layoutManager.glyphRange(
            forCharacterRange: NSRange(location: range.location, length: markerLength),
            actualCharacterRange: nil)
        guard glyph.length > 0 else { return true }   // zero glyphs generated = fully hidden
        return editor.layoutManager.notShownAttribute(forGlyphAt: glyph.location)
    }

    func test_markersStayHiddenAfterFullLayoutAndDisplay() {
        let editor = makeEditor(source)

        editor.layoutManager.ensureLayout(for: editor.container)
        editor.textView.display()

        XCTAssertTrue(isHidden(editor, "# A heading", markerLength: 1),
                      "heading marker must stay hidden after a real layout pass")
        XCTAssertTrue(isHidden(editor, "**Bold", markerLength: 2),
                      "bold marker must stay hidden after a real layout pass")
        XCTAssertTrue(isHidden(editor, "## Second", markerLength: 2),
                      "H2 marker must stay hidden after a real layout pass")
    }

    func test_focusedBlockRevealsItsMarkersAcrossRelayout() {
        let editor = makeEditor(source)
        editor.layoutManager.ensureLayout(for: editor.container)

        // Simulate focused editing: caret inside the H1 block with editor focus.
        let ns = editor.textView.string as NSString
        let heading = ns.range(of: "# A heading")
        editor.window.makeFirstResponder(editor.textView)
        editor.coordinator.hasFocus = true
        editor.textView.setSelectedRange(NSRange(location: heading.location + 4, length: 0))
        editor.coordinator.refreshMarkerVisibility(fullRecompute: true)
        editor.layoutManager.ensureLayout(for: editor.container)

        XCTAssertFalse(isHidden(editor, "# A heading", markerLength: 1),
                       "the caret block's markers must be revealed")
        XCTAssertTrue(isHidden(editor, "## Second", markerLength: 2),
                      "other blocks stay hidden across the relayout")
    }
}
