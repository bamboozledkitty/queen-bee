import Foundation
import QueenBeeCore

/// An agent's settings saved under a name, to make more agents like it in any flow.
nonisolated struct AgentRole: Codable, Identifiable, Equatable, Sendable {
    var id = Flow.newID()
    var name: String
    var instructions = ""
    var model = ""
    var effort = ""
    var permissionMode = ""

    init(from card: Card) {
        name = card.name
        instructions = card.instructions ?? ""
        model = card.model ?? ""
        effort = card.effort ?? ""
        permissionMode = card.permissionMode ?? ""
    }

    /// The role's settings as a change to a card. Its name is left to the card.
    var patch: CardPatch {
        var patch = CardPatch()
        patch.instructions = instructions
        patch.model = model
        patch.effort = effort
        patch.permissionMode = permissionMode
        return patch
    }

    /// Whether a card still has exactly what the role holds.
    func matches(_ card: Card) -> Bool {
        instructions == (card.instructions ?? "") && model == (card.model ?? "")
            && effort == (card.effort ?? "") && permissionMode == (card.permissionMode ?? "")
    }
}
