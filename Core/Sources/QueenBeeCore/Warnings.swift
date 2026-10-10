import Foundation

/// One short warning per card whose wiring would leave a run stuck, keyed by card id.
/// A card with several problems shows the first, so fixing them one at a time walks through the rest.
public func warnings(for flow: Flow) -> [String: String] {
    let circling = logicCardsInACircle(in: flow)
    var found: [String: String] = [:]
    for card in flow.cards {
        if let warning = warning(for: card, in: flow, circling: circling.contains(card.id)) {
            found[card.id] = warning
        }
    }
    return found
}

private func warning(for card: Card, in flow: Flow, circling: Bool) -> String? {
    let outgoing = flow.links(from: card.id)
    let incoming = flow.links(into: card.id)
    func nothing(on port: String) -> Bool { !outgoing.contains { $0.port == port } }
    func blank(_ text: String?) -> Bool { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    switch card.kind {
    case .agent, .note:
        return nil
    case .start:
        if outgoing.isEmpty { return "Link it to an agent" }
        if blank(card.command) { return "Write the command" }
        return nil
    case .ifElse:
        if nothing(on: "yes") { return "Nothing on Yes" }
        if nothing(on: "no") { return "Nothing on No" }
        if blank(card.value) { return "Set its condition" }
    case .loop:
        if nothing(on: "again") { return "Nothing on Again" }
        if blank(card.value) { return "Set its condition" }
    case .switchCard:
        if (card.branches ?? []).isEmpty { return "Add a branch" }
    case .and:
        // An And waits for one message per card that links in, so two links from one card are one input.
        if Set(incoming.map(\.from)).count < 2 { return "Needs 2+ inputs" }
    case .approval:
        if nothing(on: "approved") { return "Nothing on Approved" }
    case .script:
        if blank(card.command) { return "Write the command" }
        if nothing(on: "pass") { return "Nothing on Pass" }
    case .or, .prompt, .end:
        break
    }

    if incoming.isEmpty { return "Nothing links in" }
    if circling { return "Circles with no agent" }
    return nil
}

/// Logic cards that can reach themselves without passing through an agent. A message entering such a circle
/// would go round until the engine's arrival limit drops it, because only an agent's turn breaks up a run.
private func logicCardsInACircle(in flow: Flow) -> Set<String> {
    let passesMessagesOn: Set<CardKind> = [.ifElse, .switchCard, .and, .or, .prompt, .loop]
    let logic = Set(flow.cards.filter { passesMessagesOn.contains($0.kind) }.map(\.id))
    var next: [String: [String]] = [:]
    for link in flow.links where logic.contains(link.from) && logic.contains(link.to) {
        next[link.from, default: []].append(link.to)
    }

    var circling: Set<String> = []
    for id in logic {
        var seen: Set<String> = []
        var stack = next[id] ?? []
        while let current = stack.popLast() {
            if current == id { circling.insert(id); break }
            if seen.insert(current).inserted { stack.append(contentsOf: next[current] ?? []) }
        }
    }
    return circling
}
