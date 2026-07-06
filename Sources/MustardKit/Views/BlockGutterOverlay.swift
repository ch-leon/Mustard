import SwiftUI

/// Hover gutter over the live editor (Craft spec, 2b Task 9): a narrow leading
/// strip that surfaces `+` (insert via slash menu) and `⠿` (drag-reorder) for the
/// hovered block. Pure geometry + dispatch — block rects arrive from the text
/// view's layout manager, the drop slot maps straight to `BlockReorder.move`'s
/// after-removal indexing, and both actions route through `MarkdownEditorProxy`.
/// The overlay's transparent regions never intercept clicks meant for the text.
struct BlockGutterOverlay: View {
    let rects: [MarkdownBlockRect]
    /// `(from, to)` in moveable-block indices — after-removal semantics.
    let onMove: (Int, Int) -> Void
    /// Open the slash menu anchored at this block's start.
    let onInsert: (Int) -> Void

    @State private var hoveredIndex: Int?
    @State private var dragFromIndex: Int?
    @State private var dropSlot: Int?

    private static let gutterWidth: CGFloat = 28
    private static let coordinateSpaceName = "mustardBlockGutter"

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(rects, id: \.index) { block in
                    handleCell(block)
                }
                if dragFromIndex != nil, let slot = dropSlot {
                    insertionLine(width: geometry.size.width)
                        .offset(x: 0, y: insertionLineY(slot: slot) - 1)
                }
            }
        }
        // Fully-typed coordinate-space API (macOS 14): the bare `.named(...)`
        // implicit member is ambiguous between the CoordinateSpace and
        // CoordinateSpaceProtocol overloads of DragGesture.init.
        .coordinateSpace(NamedCoordinateSpace.named(Self.coordinateSpaceName))
        .animation(Theme.Motion.settle, value: hoveredIndex)
    }

    // MARK: - Per-block handles

    private func handleCell(_ block: MarkdownBlockRect) -> some View {
        let isActive = hoveredIndex == block.index || dragFromIndex == block.index
        return HStack(alignment: .top, spacing: 2) {
            Button {
                onInsert(block.index)
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(isActive ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Insert here")

            Text("⠿")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                .help("Drag to reorder")
                // Deliberately NOT NSTextView's native text drag: this gesture
                // reorders whole blocks via BlockReorder, not characters.
                .gesture(dragGesture(for: block))
        }
        .padding(.top, 2)
        .opacity(isActive ? 1 : 0)
        .frame(width: Self.gutterWidth, height: max(block.rect.height, 18), alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredIndex = block.index
            } else if hoveredIndex == block.index {
                hoveredIndex = nil
            }
        }
        .offset(x: 0, y: block.rect.minY)
    }

    // MARK: - Drag → drop slot

    private func dragGesture(for block: MarkdownBlockRect) -> some Gesture {
        DragGesture(minimumDistance: 2.0,
                    coordinateSpace: NamedCoordinateSpace.named(Self.coordinateSpaceName))
            .onChanged { value in
                dragFromIndex = block.index
                dropSlot = slot(forY: value.location.y, excluding: block.index)
            }
            .onEnded { value in
                let from = block.index
                let to = slot(forY: value.location.y, excluding: from)
                dragFromIndex = nil
                dropSlot = nil
                if to != from { onMove(from, to) }
            }
    }

    /// The insertion slot for a drop at `y`: the count of remaining blocks whose
    /// midline sits above it — exactly `BlockReorder.move`'s `to` (the slot after
    /// removing the dragged block).
    private func slot(forY y: CGFloat, excluding dragged: Int) -> Int {
        rects.filter { $0.index != dragged && $0.rect.midY < y }.count
    }

    /// Boundary y for the insertion line: the top of the block currently at the
    /// slot, or the bottom of the last block for the end slot.
    private func insertionLineY(slot: Int) -> CGFloat {
        guard let dragged = dragFromIndex else { return 0 }
        let others = rects.filter { $0.index != dragged }
        guard !others.isEmpty else { return 0 }
        if slot < others.count { return others[slot].rect.minY }
        return others[others.count - 1].rect.maxY
    }

    private func insertionLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.Palette.accent)
            .frame(width: max(width - 8, 0), height: 2)
            .padding(.leading, 4)
            .allowsHitTesting(false)
    }
}
