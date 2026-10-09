import AppKit
import QueenBeeCore

/// Where things sit on a card, in canvas points. Card views and the link layer both
/// read these, so a link always ends on the dot it belongs to.
enum CanvasGeometry {
    static let titleHeight: CGFloat = 30
    static let portRowHeight: CGFloat = 24
    static let portRadius: CGFloat = 6
    static let cornerRadius: CGFloat = 10
    static let resizeHandle: CGFloat = 18

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

    /// The curve a link follows between two points, leaving and arriving horizontally.
    static func linkPath(from a: CGPoint, to b: CGPoint) -> CGPath {
        let reach = max(50, abs(b.x - a.x) / 2)
        let path = CGMutablePath()
        path.move(to: a)
        path.addCurve(to: b, control1: CGPoint(x: a.x + reach, y: a.y), control2: CGPoint(x: b.x - reach, y: b.y))
        return path
    }

    static func icon(for kind: CardKind) -> String {
        switch kind {
        case .agent: "terminal"
        case .start: "play.fill"
        case .ifElse: "arrow.triangle.branch"
        case .switchCard: "arrow.triangle.swap"
        case .and: "arrow.triangle.merge"
        case .or: "bolt.fill"
        case .prompt: "pencil"
        case .loop: "repeat"
        case .end: "stop.fill"
        case .note: "note.text"
        }
    }
}

enum Palette {
    static let canvas = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.93, alpha: 1) }
    static let gridDot = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.12) }
    static let card = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.17, alpha: 1) : NSColor.white }
    static let cardTitle = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.96, alpha: 1) }
    static let cardBorder = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.16) }
    static let link = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.42, alpha: 1) }
    static let terminalBackground = NSColor(white: 0.08, alpha: 1)
    static let terminalForeground = NSColor(white: 0.92, alpha: 1)
    static let accent = NSColor.controlAccentColor
    static let warning = NSColor.systemOrange
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
