import CoreGraphics

/// Lays a flow out left to right in the order its links run, the way a wiring diagram reads.
public enum Tidy {
    public static let columnGap: CGFloat = 96
    public static let rowGap: CGFloat = 48

    /// A new top-left corner for each card, keyed by id. The layout keeps the flow's top-left
    /// where it was. Notes carry no links, so they are left where they are.
    public static func layout(_ flow: Flow, grid: CGFloat = 24) -> [String: CGPoint] {
        let cards = flow.cards.filter { $0.kind != .note }
        guard !cards.isEmpty else { return [:] }
        let ids = Set(cards.map(\.id))
        var next: [String: [String]] = [:], before: [String: [String]] = [:]
        for link in flow.links where ids.contains(link.from) && ids.contains(link.to) && link.from != link.to {
            next[link.from, default: []].append(link.to)
            before[link.to, default: []].append(link.from)
        }

        // Walk from the cards a run starts at. A link back to a card already on the path is a
        // loop, and is left out when deciding columns so the loop's body still reads left to right.
        var column: [String: Int] = [:]
        var onPath: Set<String> = []
        var forward: [String: [String]] = [:]
        func visit(_ id: String) {
            onPath.insert(id)
            for target in next[id] ?? [] where !onPath.contains(target) {
                if !(forward[id] ?? []).contains(target) { forward[id, default: []].append(target) }
                let wanted = (column[id] ?? 0) + 1
                if wanted > (column[target] ?? -1) {
                    column[target] = wanted
                    visit(target)
                }
            }
            onPath.remove(id)
        }
        let starts = cards.filter { $0.kind == .start } + cards.filter { $0.kind != .start && (before[$0.id] ?? []).isEmpty }
        for card in starts where column[card.id] == nil {
            column[card.id] = 0
            visit(card.id)
        }
        // Whatever is left is only reachable round a circle with no way in: start it in the first column.
        for card in cards where column[card.id] == nil {
            column[card.id] = 0
            visit(card.id)
        }

        let origin = CGPoint(x: cards.map(\.x).min() ?? 0, y: cards.map(\.y).min() ?? 0)
        func snapped(_ value: CGFloat) -> CGFloat { grid > 0 ? (value / grid).rounded() * grid : value }

        var placed: [String: CGPoint] = [:]
        var x = snapped(origin.x)
        for index in 0...(column.values.max() ?? 0) {
            var members = cards.filter { column[$0.id] == index }
            guard !members.isEmpty else { continue }
            // Cards sit level with what feeds them, so links run straight where they can.
            func feedY(_ card: Card) -> CGFloat {
                let feeders = (before[card.id] ?? []).compactMap { placed[$0]?.y }
                return feeders.isEmpty ? CGFloat(card.y) : feeders.reduce(0, +) / CGFloat(feeders.count)
            }
            members.sort { feedY($0) < feedY($1) }
            var y = snapped(origin.y)
            for card in members {
                let wanted = max(y, snapped(index == 0 ? y : feedY(card)))
                placed[card.id] = CGPoint(x: x, y: wanted)
                y = snapped(wanted + CGFloat(card.height) + rowGap)
            }
            x = snapped(x + CGFloat(members.map(\.width).max() ?? 0) + columnGap)
        }
        return placed
    }
}
