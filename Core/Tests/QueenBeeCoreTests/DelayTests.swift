import Foundation
import Testing
@testable import QueenBeeCore

/// Delay cards: a message waits at one for a set time, then goes on as it was.
@Suite struct DelayTests {
    /// Start → Writer → Wait (Delay) → Sender.
    private func delayed(minutes: Int? = nil) throws -> Flow {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        try flow.addCard(kind: .agent, name: "Writer")
        var wait = CardPatch()
        wait.waitMinutes = minutes
        try flow.addCard(kind: .delay, name: "Wait", patch: wait)
        try flow.addCard(kind: .agent, name: "Sender")
        try flow.addLink(from: "Start", to: "Writer")
        try flow.addLink(from: "Writer", to: "Wait")
        try flow.addLink(from: "Wait", to: "Sender")
        return flow
    }

    @Test func aDelayHoldsTheMessageThenPassesItOnFromItsSender() async throws {
        let flow = try delayed(minutes: 90)
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        let writer = try #require(flow.resolveCard("Writer"))
        let reached = await engine.agentReplied(flow: flow, cardID: writer.id, text: "Dear all")
        let hold = try #require(reached.holds.first)
        #expect(hold.kind == .delay && hold.text == "Dear all")
        #expect(reached.deliveries.isEmpty && !reached.finished)
        #expect(reached.log.contains("Delay \"Wait\" is waiting 1 hour 30 minutes"))

        let out = await engine.holdResolved(flow: flow, holdID: hold.id, port: "out", text: nil)
        let delivery = try #require(out.deliveries.first)
        #expect(delivery.toCardID == (try #require(flow.resolveCard("Sender"))).id)
        #expect(delivery.text.contains("Dear all"))
        // The Delay only held it, so the Sender hears it from the Writer.
        #expect(delivery.fromName == "Writer")
        #expect(!out.finished)
    }

    @Test func aRunWaitingAtADelayIsNotStalled() async throws {
        let flow = try delayed()
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        let out = await engine.agentReplied(flow: flow, cardID: try #require(flow.resolveCard("Writer")).id, text: "Dear all")
        #expect(out.holds.count == 1 && !out.finished)
        #expect(!out.isStalled && out.stalledOn.isEmpty)
    }

    @Test func aDelayAlwaysWaitsBetweenAMinuteAndAWeek() throws {
        var flow = Flow(name: "Test")
        let made = try flow.addCard(kind: .delay, name: "Wait")
        #expect(made.waitMinutes == DelayTime.defaultMinutes)
        #expect(DelayTime.wait(for: made) == .seconds(DelayTime.defaultMinutes * 60))

        var patch = CardPatch()
        patch.waitMinutes = 0
        #expect(try flow.updateCard("Wait", patch: patch).waitMinutes == 1)
        patch.waitMinutes = -20
        #expect(try flow.updateCard("Wait", patch: patch).waitMinutes == 1)
        patch.waitMinutes = 1_000_000
        #expect(try flow.updateCard("Wait", patch: patch).waitMinutes == HoldTimeLimit.longestMinutes)

        // A file that leaves it out, or says 0, still waits.
        var bare = Card(id: "d1", kind: .delay, name: "Bare", x: 0, y: 0, width: 240, height: 96)
        #expect(DelayTime.minutes(for: bare) == DelayTime.defaultMinutes)
        bare.waitMinutes = 0
        #expect(DelayTime.minutes(for: bare) == 1)
        // A Delay never gives an Approval's or a Script's time limit.
        #expect(HoldTimeLimit.wait(for: made) == nil)
    }

    @Test func aDelayNeedsOnlySomethingLinkedIn() throws {
        var flow = try delayed()
        #expect(warnings(for: flow).isEmpty)
        let wait = try #require(flow.resolveCard("Wait"))
        try flow.removeLink(try #require(flow.links(from: wait.id).first).id)
        // A run can end at a Delay: nothing after it is not a mistake.
        #expect(warnings(for: flow).isEmpty)
        try flow.removeLink(try #require(flow.links(into: wait.id).first).id)
        #expect(warnings(for: flow) == [wait.id: "Nothing is linked to it"])
    }

    @Test func aScriptThatTriesAgainAfterADelayIsNotGoingRoundWithNoAgent() throws {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        var check = CardPatch()
        check.command = "test -f done"
        try flow.addCard(kind: .script, name: "Done yet?", patch: check)
        try flow.addCard(kind: .delay, name: "Wait")
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "Done yet?")
        try flow.addLink(from: "Done yet?", port: "pass", to: "End")
        try flow.addLink(from: "Done yet?", port: "fail", to: "Wait")
        try flow.addLink(from: "Wait", to: "Done yet?")
        #expect(warnings(for: flow).isEmpty)
    }

    @Test func getFlowGivesADelaysMinutes() throws {
        var flow = try delayed(minutes: 12)
        flow.cards[flow.cards.firstIndex { $0.kind == .delay }!].waitMinutes = nil
        let snapshot = FlowSnapshot(flow: flow, agents: [:], isRunning: false)
        let described = try JSONValue.parse(Data(Tools.describe(snapshot).text().utf8))
        let cards = try #require(described["cards"]?.arrayValue)
        let wait = try #require(cards.first { $0["kind"]?.stringValue == "delay" })
        #expect(wait["wait_minutes"]?.doubleValue == Double(DelayTime.defaultMinutes))
        #expect(wait["outputs"] == .array([.string("out")]))
    }
}
