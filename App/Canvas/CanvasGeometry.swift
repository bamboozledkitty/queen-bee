import AppKit
import QueenBeeCore

/// Where things sit on a card, in canvas points. Card views and the link layer both
/// read these, so a link always ends on the dot it belongs to.
enum CanvasGeometry {
    static let titleHeight: CGFloat = 28
    static let portRowHeight: CGFloat = 22
    static let portRadius: CGFloat = 5
    static let resizeHandle: CGFloat = 16
    static let gridStep: CGFloat = 24

    static func frame(of card: Card) -> CGRect {
        CGRect(x: card.x, y: card.y, width: card.width, height: card.height)
    }

    /// The input dot's centre, on the card's left edge beside its title.
    static func inputPoint(of card: Card) -> CGPoint {
        CGPoint(x: card.x, y: card.y + titleHeight / 2)
    }

    /// An output dot's centre on the card's right edge: one output sits beside the
    /// title; named outputs get a row each at the card's foot.
    static func outputPoint(of card: Card, port: String) -> CGPoint {
        let all = ports(of: card)
        guard all.count > 1, let i = all.firstIndex(of: port) else {
            return CGPoint(x: card.x + card.width, y: card.y + titleHeight / 2)
        }
        let fromBottom = CGFloat(all.count - i)
        return CGPoint(x: card.x + card.width, y: card.y + card.height - fromBottom * portRowHeight + portRowHeight / 2)
    }

    /// The corner points of a link's right-angled route. Links that leave the same card are
    /// given a lane each, so two that loop back don't run on top of one another.
    static func route(of link: Link, in flow: Flow) -> [CGPoint]? {
        guard let from = flow.card(link.from), let to = flow.card(link.to) else { return nil }
        let siblings = flow.links(from: link.from)
        let lane = siblings.firstIndex { $0.id == link.id } ?? 0
        return LinkRouter.route(from: outputPoint(of: from, port: link.port), to: inputPoint(of: to),
                                source: frame(of: from), target: frame(of: to), lane: lane)
    }

    static func icon(for kind: CardKind) -> String {
        switch kind {
        case .agent: "terminal"
        case .start: "play"
        case .ifElse: "arrow.triangle.branch"
        case .switchCard: "arrow.triangle.swap"
        case .and: "arrow.triangle.merge"
        case .or: "bolt"
        case .prompt: "pencil"
        case .loop: "repeat"
        case .end: "flag"
        case .note: "note.text"
        case .approval: "checkmark.seal"
        case .script: "chevron.left.forwardslash.chevron.right"
        }
    }
}
