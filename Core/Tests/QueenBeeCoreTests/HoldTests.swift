import Foundation
import Testing
@testable import QueenBeeCore

/// Approval and Script cards: a message waits at them until the app answers.
@Suite struct HoldTests {
    private func flow(_ kind: CardKind, command: String? = nil) throws -> Flow {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        try flow.addCard(kind: .agent, name: "Writer")
        var gate = CardPatch()
        gate.command = command
        try flow.addCard(kind: kind, name: "Gate", patch: gate)
        try flow.addCard(kind: .agent, name: "Sender")
        try flow.addCard(kind: .end, name: "Dropped")
        try flow.addLink(from: "Start", to: "Writer")
        try flow.addLink(from: "Writer", to: "Gate")
        try flow.addLink(from: "Gate", port: kind == .approval ? "approved" : "pass", to: "Sender")
        try flow.addLink(from: "Gate", port: kind == .approval ? "rejected" : "fail", to: "Dropped")
        return flow
    }

    private func reachGate(_ flow: Flow, _ engine: Engine) async throws -> Hold {
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        let out = await engine.agentReplied(flow: flow, cardID: try #require(flow.resolveCard("Writer")).id, text: "Dear all")
        #expect(!out.finished)
        return try #require(out.holds.first)
    }

    @Test func anApprovalHoldsTheMessageAndKeepsTheRunGoing() async throws {
        let flow = try flow(.approval)
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        #expect(hold.kind == .approval && hold.text == "Dear all" && hold.fromName == "Writer")
        #expect(await engine.isRunning)
    }

    @Test func approvingPassesTheEditedMessageOnFromItsWriter() async throws {
        let flow = try flow(.approval)
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        let out = await engine.holdResolved(flow: flow, holdID: hold.id, port: "approved", text: "Dear team")
        #expect(out.deliveries.count == 1)
        #expect(out.deliveries.first?.text.hasSuffix("from Writer]\nDear team") == true)
        #expect(out.log.first == "Approval \"Gate\" → Approved")
    }

    @Test func rejectingTakesTheOtherOutputAndCanEndTheRun() async throws {
        let flow = try flow(.approval)
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        let out = await engine.holdResolved(flow: flow, holdID: hold.id, port: "rejected", text: nil)
        #expect(out.results.map(\.text) == ["Dear all"])
        #expect(out.finished)
    }

    @Test func aHoldAnsweredTwiceOnlyCountsOnce() async throws {
        let flow = try flow(.approval)
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        _ = await engine.holdResolved(flow: flow, holdID: hold.id, port: "approved", text: nil)
        let again = await engine.holdResolved(flow: flow, holdID: hold.id, port: "approved", text: nil)
        #expect(again.deliveries.isEmpty && again.log.isEmpty)
    }

    @Test func aScriptPassesOnWhatItPrintedUnderItsOwnName() async throws {
        let flow = try flow(.script, command: "npm test")
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        #expect(hold.kind == .script)
        let out = await engine.holdResolved(flow: flow, holdID: hold.id, port: "pass", text: "12 passed")
        #expect(out.deliveries.first?.text.hasSuffix("from Gate]\n12 passed") == true)
    }

    @Test func aScriptWithNoCommandFailsWithoutWaiting() async throws {
        let flow = try flow(.script, command: "  ")
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        let out = await engine.agentReplied(flow: flow, cardID: try #require(flow.resolveCard("Writer")).id, text: "Dear all")
        #expect(out.holds.isEmpty)
        #expect(out.results.map(\.cardName) == ["Dropped"])
    }

    @Test func stoppingARunForgetsWhatWasHeld() async throws {
        let flow = try flow(.approval)
        let engine = Engine(judge: ScriptedJudge())
        let hold = try await reachGate(flow, engine)
        _ = await engine.stop()
        let late = await engine.holdResolved(flow: flow, holdID: hold.id, port: "approved", text: nil)
        #expect(late.deliveries.isEmpty)
    }

    @Test func warningsCoverTheNewCards() throws {
        var flow = Flow(name: "Test")
        let script = try flow.addCard(kind: .script, name: "Tests")
        let gate = try flow.addCard(kind: .approval, name: "Gate")
        #expect(warnings(for: flow)[script.id] == "Write the command")
        #expect(warnings(for: flow)[gate.id] == "Nothing on Approved")
    }
}

@Suite struct TravelTests {
    @Test func eachLinkRecordsWhatItCarried() async throws {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        try flow.addCard(kind: .agent, name: "Writer")
        try flow.addCard(kind: .end, name: "Done")
        let first = try flow.addLink(from: "Start", to: "Writer")
        let second = try flow.addLink(from: "Writer", to: "Done")
        let engine = Engine(judge: ScriptedJudge())
        let began = await engine.start(flow: flow, startCardID: nil, command: nil)
        #expect(began.travels == [Travel(linkID: first.id, text: "Go", fromName: "Start")])
        let replied = await engine.agentReplied(flow: flow, cardID: try #require(flow.resolveCard("Writer")).id, text: "A draft")
        #expect(replied.travels == [Travel(linkID: second.id, text: "A draft", fromName: "Writer")])
    }
}
