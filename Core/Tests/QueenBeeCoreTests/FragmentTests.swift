import CoreGraphics
import Testing
@testable import QueenBeeCore

@Suite struct FragmentTests {
    private func sample() throws -> Flow {
        var flow = Flow(name: "Sample")
        let writer = try flow.addCard(kind: .agent, name: "Writer", x: 0, y: 0)
        let reviewer = try flow.addCard(kind: .agent, name: "Reviewer", x: 700, y: 0)
        let done = try flow.addCard(kind: .end, name: "Done", x: 1400, y: 0)
        try flow.addLink(from: writer.id, to: reviewer.id, maxPasses: 7)
        try flow.addLink(from: reviewer.id, to: done.id)
        return flow
    }

    @Test func fragmentKeepsOnlyLinksBetweenItsCards() throws {
        let flow = try sample()
        let ids = Set(flow.cards.prefix(2).map(\.id))
        let fragment = flow.fragment(of: ids)
        #expect(fragment.cards.map(\.name) == ["Writer", "Reviewer"])
        #expect(fragment.links.count == 1)
    }

    @Test func insertGivesCopiesNewIdsNamesAndPlaces() throws {
        var flow = try sample()
        flow.cards[0].sessionID = "abc"
        let fragment = flow.fragment(of: Set(flow.cards.prefix(2).map(\.id)))
        let made = flow.insert(fragment, dx: 24, dy: 48)
        #expect(made.map(\.name) == ["Writer 2", "Reviewer 2"])
        #expect(Set(made.map(\.id)).isDisjoint(with: fragment.cards.map(\.id)))
        #expect(made[0].x == 24 && made[0].y == 48)
        #expect(made[0].sessionID == nil)
        let copied = flow.links.filter { $0.from == made[0].id && $0.to == made[1].id }
        #expect(copied.count == 1 && copied[0].maxPasses == 7)
        #expect(flow.cards.count == 5 && flow.links.count == 3)
    }

    @Test func copyOfACopyCountsOn() throws {
        var flow = try sample()
        let first = flow.insert(flow.fragment(of: [flow.cards[0].id]))
        let second = flow.insert(flow.fragment(of: [first[0].id]))
        #expect(second[0].name == "Writer 3")
    }

    @Test func insertDropsSettingsTheAppDoesNotOffer() throws {
        var flow = Flow(name: "Empty")
        var card = Card.make(kind: .agent, name: "Rogue", x: 0, y: 0)
        card.permissionMode = "bypassPermissions"
        card.effort = "ludicrous"
        let made = flow.insert(FlowFragment(cards: [card], links: [Link(from: card.id, to: card.id)]))
        #expect(made[0].permissionMode == nil && made[0].effort == nil)
        #expect(flow.links.isEmpty)
    }

    @Test func snapLinesUpWithANearbyCard() {
        let other = CGRect(x: 100, y: 300, width: 200, height: 100)
        let result = Snapping.snap(CGRect(x: 104, y: 37, width: 240, height: 96), to: [other], grid: 24, tolerance: 6)
        #expect(result.origin.x == 100)
        #expect(result.origin.y == 48)
        #expect(result.guides == [Snapping.Guide(isVertical: true, position: 100, start: 37, end: 400)])
    }

    @Test func snapFallsBackToTheGrid() {
        let result = Snapping.snap(CGRect(x: 131, y: 59, width: 240, height: 96), to: [], grid: 24, tolerance: 6)
        #expect(result.origin == CGPoint(x: 120, y: 48))
        #expect(result.guides.isEmpty)
    }
}
