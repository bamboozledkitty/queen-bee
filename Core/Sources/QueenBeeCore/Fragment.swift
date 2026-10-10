import Foundation

/// A piece of a flow that can be copied: some cards and the links that run between them.
public struct FlowFragment: Codable, Equatable, Sendable {
    public var cards: [Card]
    public var links: [Link]
    /// Groups whose every card is in the fragment. Nil on a pasteboard written before groups.
    public var groups: [CardGroup]?

    public init(cards: [Card], links: [Link], groups: [CardGroup]? = nil) {
        self.cards = cards
        self.links = links
        self.groups = groups
    }
}

extension Flow {
    /// The cards with these ids, in canvas order, and the links whose two ends are both among them.
    public func fragment(of ids: Set<String>) -> FlowFragment {
        let whole = (groups ?? []).filter { group in group.cardIDs.allSatisfy(ids.contains) }
        return FlowFragment(cards: cards.filter { ids.contains($0.id) },
                            links: links.filter { ids.contains($0.from) && ids.contains($0.to) },
                            groups: whole.isEmpty ? nil : whole)
    }

    /// Adds a copy of `fragment`, moved by `dx` and `dy`. Each copy gets a new id and a name no
    /// other card has, and starts without a session, so it never shares one with its original.
    /// A fragment can come off the pasteboard, so it is held to the same rules as any other edit:
    /// a permission mode or effort the app doesn't offer is dropped, and a link is only kept if
    /// it could have been made by hand.
    @discardableResult
    public mutating func insert(_ fragment: FlowFragment, dx: Double = 0, dy: Double = 0) -> [Card] {
        var newIDs: [String: String] = [:]
        var made: [Card] = []
        for original in fragment.cards {
            var card = original
            card.id = Flow.newID()
            card.name = uniqueName(Self.nameWithoutNumber(original.name))
            card.x += dx
            card.y += dy
            card.sessionID = nil
            // A copy never brings a schedule with it: the person sets that on each card themselves.
            card.trigger = nil
            if let mode = card.permissionMode, !Card.permissionModes.contains(mode) { card.permissionMode = nil }
            if let effort = card.effort, !Card.effortLevels.contains(effort) { card.effort = nil }
            card.width = max(card.width, Card.minimumWidth(for: card))
            card.height = max(card.height, Card.minimumHeight(for: card))
            newIDs[original.id] = card.id
            cards.append(card)
            made.append(card)
        }
        for link in fragment.links {
            guard let from = newIDs[link.from], let to = newIDs[link.to] else { continue }
            _ = try? addLink(from: from, port: link.port, to: to, maxPasses: link.maxPasses)
        }
        for group in fragment.groups ?? [] {
            let members = group.cardIDs.compactMap { newIDs[$0] }
            if members.count >= 2 { _ = try? addGroup(name: group.name, cardIDs: members) }
        }
        return made
    }

    /// "Writer 2" gives "Writer", so a copy of a copy is "Writer 3" and not "Writer 2 2".
    static func nameWithoutNumber(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count > 1, let last = parts.last, Int(last) != nil else { return name }
        return parts.dropLast().joined(separator: " ")
    }
}
