import CoreGraphics
import Foundation
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

@Suite struct TriggerTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Wednesday 7 October 2026, 08:30 UTC.
    private var wednesday: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 8, minute: 30))! }

    @Test func anIntervalFiresThatManyMinutesOn() {
        let next = Trigger(kind: .interval, minutes: 30).nextFire(after: wednesday, calendar: utc)
        #expect(next == wednesday.addingTimeInterval(1800))
    }

    @Test func dailyFiresTodayIfTheTimeIsStillAheadElseTomorrow() {
        let nine = Trigger(kind: .daily, hour: 9, minute: 0).nextFire(after: wednesday, calendar: utc)
        #expect(nine == utc.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9)))
        let eight = Trigger(kind: .daily, hour: 8, minute: 0).nextFire(after: wednesday, calendar: utc)
        #expect(eight == utc.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 8)))
    }

    @Test func weeklyFiresOnTheNextChosenDay() {
        // Monday is 2 and Friday is 6. From a Wednesday, Friday comes first.
        let next = Trigger(kind: .weekly, hour: 9, minute: 0, weekdays: [2, 6]).nextFire(after: wednesday, calendar: utc)
        #expect(next == utc.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9)))
        #expect(Trigger(kind: .weekly, weekdays: []).nextFire(after: wednesday, calendar: utc) == nil)
    }

    @Test func aFileTriggerHasNoClockTime() {
        #expect(Trigger(kind: .file, path: "src").nextFire(after: wednesday, calendar: utc) == nil)
    }

    @Test func summariesReadPlainly() {
        #expect(Trigger(kind: .interval, minutes: 120).summary == "Every 2 hours")
        #expect(Trigger(kind: .daily, hour: 9, minute: 5).summary == "Every day at 09:05")
        #expect(Trigger(kind: .weekly, hour: 18, minute: 0, weekdays: [6, 2]).summary == "Mon, Fri at 18:00")
        #expect(Trigger(kind: .file, path: "inbox").summary == "When inbox changes")
    }

    @Test func aPastedStartCardLosesItsSchedule() {
        var flow = Flow(name: "Empty")
        var card = Card.make(kind: .start, name: "Start", x: 0, y: 0)
        card.trigger = Trigger(kind: .interval, minutes: 1)
        #expect(flow.insert(FlowFragment(cards: [card], links: []))[0].trigger == nil)
    }
}
