import AppKit
import QueenBeeCore

/// Draws every link as a curve, under the cards. It never takes a click itself,
/// so it can't block a card or a gesture: the canvas asks it which link a point is on.
final class LinkLayerView: NSView {
    var flow: Flow? { didSet { needsDisplay = true } }
    var selectedLinkID: String? { didSet { needsDisplay = true } }
    /// A link being dragged out of a port, not made yet.
    var pending: (from: CGPoint, to: CGPoint)? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func endpoints(of link: Link, in flow: Flow) -> (CGPoint, CGPoint)? {
        guard let from = flow.card(link.from), let to = flow.card(link.to) else { return nil }
        return (CanvasGeometry.outputPoint(of: from, port: link.port), CanvasGeometry.inputPoint(of: to))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        if let flow {
            for link in flow.links {
                guard let (a, b) = endpoints(of: link, in: flow) else { continue }
                let selected = link.id == selectedLinkID
                stroke(CanvasGeometry.linkPath(from: a, to: b), in: ctx,
                       color: selected ? Palette.accent : Palette.link, width: selected ? 3 : 2, dashed: false)
                arrowhead(at: b, in: ctx, color: selected ? Palette.accent : Palette.link)
            }
        }
        if let pending {
            stroke(CanvasGeometry.linkPath(from: pending.from, to: pending.to), in: ctx,
                   color: Palette.accent, width: 2, dashed: true)
        }
    }

    private func stroke(_ path: CGPath, in ctx: CGContext, color: NSColor, width: CGFloat, dashed: Bool) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        if dashed { ctx.setLineDash(phase: 0, lengths: [6, 5]) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A small triangle pointing into the target's input dot.
    private func arrowhead(at tip: CGPoint, in ctx: CGContext, color: NSColor) {
        let x = tip.x - CanvasGeometry.portRadius - 1
        ctx.saveGState()
        ctx.move(to: CGPoint(x: x, y: tip.y))
        ctx.addLine(to: CGPoint(x: x - 9, y: tip.y - 5))
        ctx.addLine(to: CGPoint(x: x - 9, y: tip.y + 5))
        ctx.closePath()
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// The link whose curve passes within a few points of `point`.
    func linkID(at point: CGPoint) -> String? {
        guard let flow else { return nil }
        for link in flow.links.reversed() {
            guard let (a, b) = endpoints(of: link, in: flow) else { continue }
            let band = CanvasGeometry.linkPath(from: a, to: b)
                .copy(strokingWithWidth: 12, lineCap: .round, lineJoin: .round, miterLimit: 1)
            if band.contains(point) { return link.id }
        }
        return nil
    }
}
