import CoreGraphics

/// Where a card being dragged settles. It lines up with a nearby card when one of its edges
/// or its middle comes close to that card's, and otherwise sits on the grid.
public enum Snapping {
    /// A line to draw while a card is lined up with another: across both of them.
    public struct Guide: Equatable, Sendable {
        /// True for an up-and-down line at an x, false for a side-to-side line at a y.
        public var isVertical: Bool
        public var position: CGFloat
        public var start: CGFloat
        public var end: CGFloat
    }

    public static func snap(_ rect: CGRect, to others: [CGRect], grid: CGFloat, tolerance: CGFloat) -> (origin: CGPoint, guides: [Guide]) {
        var origin = rect.origin
        var guides: [Guide] = []

        if let hit = nearest([rect.minX, rect.midX, rect.maxX], others.map { ($0, [$0.minX, $0.midX, $0.maxX]) }, tolerance) {
            origin.x += hit.shift
            guides.append(Guide(isVertical: true, position: hit.line, start: min(rect.minY, hit.other.minY), end: max(rect.maxY, hit.other.maxY)))
        } else if grid > 0 {
            origin.x = (rect.minX / grid).rounded() * grid
        }
        if let hit = nearest([rect.minY, rect.midY, rect.maxY], others.map { ($0, [$0.minY, $0.midY, $0.maxY]) }, tolerance) {
            origin.y += hit.shift
            guides.append(Guide(isVertical: false, position: hit.line, start: min(rect.minX, hit.other.minX), end: max(rect.maxX, hit.other.maxX)))
        } else if grid > 0 {
            origin.y = (rect.minY / grid).rounded() * grid
        }
        return (origin, guides)
    }

    /// The smallest move that puts one of `mine` on one of another card's lines, if any is within reach.
    private static func nearest(_ mine: [CGFloat], _ theirs: [(CGRect, [CGFloat])], _ tolerance: CGFloat) -> (shift: CGFloat, line: CGFloat, other: CGRect)? {
        var best: (shift: CGFloat, line: CGFloat, other: CGRect)?
        for (other, lines) in theirs {
            for line in lines {
                for value in mine where abs(line - value) <= tolerance && abs(line - value) < abs(best?.shift ?? .infinity) {
                    best = (line - value, line, other)
                }
            }
        }
        return best
    }
}
