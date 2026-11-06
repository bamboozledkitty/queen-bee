import Foundation
import Testing
@testable import QueenBeeCore

/// An agent's Error output, and End cards that end the run as failed.
@Suite struct ErrorOutputTests {
    private func id(_ name: String, in flow: Flow) throws -> String {
        try #require(flow.resolveCard(name)).id
    }

    /// Start → Boss → Writer → Sender, with Writer's Error going to `errorTo`, if given.
    private func chain(errorTo: CardKind? = nil, failsRun: Bool = false) throws -> Flow {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        for name in ["Boss", "Writer", "Sender"] { try flow.addCard(kind: .agent, name: name) }
        try flow.addLink(from: "Start", to: "Boss")
        try flow.addLink(from: "Boss", to: "Writer")
        try flow.addLink(from: "Writer", to: "Sender")
        if let errorTo {
            var patch = CardPatch()
            patch.failsRun = failsRun
            try flow.addCard(kind: errorTo, name: "Oops", patch: patch)
            try flow.addLink(from: "Writer", port: "error", to: "Oops")
        }
        return flow
    }

    /// Starts `flow` and has the Boss reply, so the Writer is working on "Draft it" from the Boss.
    private func writerWorking(_ flow: Flow) async throws -> Engine {
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        _ = await engine.agentReplied(flow: flow, cardID: try id("Boss", in: flow), text: "Draft it")
        return engine
    }

    @Test func anAgentHasAnErrorOutputBelowItsOut() throws {
        let flow = try chain()
        let writer = try #require(flow.resolveCard("Writer"))
        #expect(ports(of: writer) == ["out", "error"])
        #expect(portLabel("error") == "Error")
        // Out stays beside the title and Error takes the foot row; other cards are as they were.
        #expect(outputRow(of: writer, port: "out") == nil && outputRow(of: writer, port: "error") == 1)
        let script = Card.make(kind: .script, name: "S", x: 0, y: 0)
        #expect(outputRow(of: script, port: "pass") == 2 && outputRow(of: script, port: "fail") == 1)
        #expect(outputRow(of: Card.make(kind: .delay, name: "D", x: 0, y: 0), port: "out") == nil)
        // A new link from an agent still leaves by Out.
        #expect(flow.links.first { $0.from == writer.id }?.port == "out")
    }

    @Test func withNothingLinkedToErrorAFailureStillStopsTheRun() async throws {
        let flow = try chain()
        let engine = try await writerWorking(flow)
        let out = await engine.agentFailed(flow: flow, cardID: try id("Writer", in: flow), reason: "API error 529")
        #expect(out.finished && out.ending == .failed)
        #expect(out.log == ["Run stopped because Writer failed: API error 529"])
        #expect(out.deliveries.isEmpty)
    }

    @Test func aFailureGoesOutErrorWithTheMessageTheAgentWasGiven() async throws {
        let flow = try chain(errorTo: .agent)
        let engine = try await writerWorking(flow)
        let writer = try id("Writer", in: flow)
        let out = await engine.agentFailed(flow: flow, cardID: writer, reason: "its turn ended with an API error", wholeSession: false)
        #expect(!out.finished)
        #expect(out.log.first == "Writer failed: its turn ended with an API error → Error")
        #expect(out.visits.contains { $0.cardID == writer && $0.port == "error" })
        let delivery = try #require(out.deliveries.first)
        let oops = try id("Oops", in: flow)
        #expect(out.deliveries.count == 1 && delivery.toCardID == oops)
        // As it was handed over, still from the Boss.
        #expect(delivery.text.hasSuffix("\nDraft it") && delivery.fromName == "Boss")
        // It goes out once: the Writer is owed nothing now.
        let again = await engine.agentFailed(flow: flow, cardID: writer, reason: "its session ended")
        #expect(again.deliveries.isEmpty && again.log.isEmpty && !again.finished)
        let late = await engine.agentReplied(flow: flow, cardID: writer, text: "Here it is after all")
        #expect(late.deliveries.isEmpty)
    }

    @Test func aFailedTurnLeavesTheAgentWithWhatElseItWasGiven() async throws {
        // Start → A and B, both → Writer, so the Writer is handed two messages.
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        for name in ["A", "B", "Writer", "Fixer", "Sender"] { try flow.addCard(kind: .agent, name: name) }
        for name in ["A", "B"] {
            try flow.addLink(from: "Start", to: name)
            try flow.addLink(from: name, to: "Writer")
        }
        try flow.addLink(from: "Writer", port: "error", to: "Fixer")
        try flow.addLink(from: "Writer", to: "Sender")
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        _ = await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "From A")
        _ = await engine.agentReplied(flow: flow, cardID: try id("B", in: flow), text: "From B")
        let writer = try id("Writer", in: flow)

        let failed = await engine.agentFailed(flow: flow, cardID: writer, reason: "API error", wholeSession: false)
        #expect(failed.deliveries.map(\.fromName) == ["A"] && failed.deliveries.first?.text.hasSuffix("From A") == true)
        // Its next reply answers B's message, and goes out as usual.
        let replied = await engine.agentReplied(flow: flow, cardID: writer, text: "Done B")
        let sender = try id("Sender", in: flow)
        #expect(replied.deliveries.map(\.toCardID) == [sender])
    }

    @Test func aSessionThatEndsSendsEverythingItWasGivenOutError() async throws {
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        for name in ["A", "B", "Writer", "Fixer"] { try flow.addCard(kind: .agent, name: name) }
        for name in ["A", "B"] {
            try flow.addLink(from: "Start", to: name)
            try flow.addLink(from: name, to: "Writer")
        }
        try flow.addLink(from: "Writer", port: "error", to: "Fixer")
        let engine = Engine(judge: ScriptedJudge())
        _ = await engine.start(flow: flow, startCardID: nil, command: nil)
        _ = await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "From A")
        _ = await engine.agentReplied(flow: flow, cardID: try id("B", in: flow), text: "From B")
        let writer = try id("Writer", in: flow)

        let ended = await engine.agentFailed(flow: flow, cardID: writer, reason: "its session ended")
        // Both messages it was given go out Error, oldest first, so nothing is left waiting on it.
        #expect(ended.deliveries.map(\.fromName) == ["A", "B"])
        #expect(ended.log.contains("Writer failed: its session ended → Error, with all 2 messages it was given"))
        #expect(await engine.agentReplied(flow: flow, cardID: writer, text: "Late").deliveries.isEmpty)
    }

    @Test func tryingAgainThroughADelayStopsAtTheLinksLimit() async throws {
        var flow = try chain(errorTo: .delay)
        try flow.addLink(from: "Oops", to: "Writer")
        let engine = try await writerWorking(flow)
        let writer = try id("Writer", in: flow)
        for _ in 1...Link.defaultMaxPasses {
            let failed = await engine.agentFailed(flow: flow, cardID: writer, reason: "API error", wholeSession: false)
            let hold = try #require(failed.holds.first)
            #expect(hold.kind == .delay && hold.text == "Draft it")
            let back = await engine.holdResolved(flow: flow, holdID: hold.id, port: "out", text: nil)
            #expect(back.deliveries.first?.toCardID == writer && back.deliveries.first?.fromName == "Boss")
        }
        let last = await engine.agentFailed(flow: flow, cardID: writer, reason: "API error", wholeSession: false)
        #expect(last.holds.isEmpty)
        #expect(last.log.contains { $0.contains("reached its limit of \(Link.defaultMaxPasses)") })
        #expect(last.finished && last.ending == .endedWithoutAnswer)
    }

    @Test func aTurnFromARunThatHasEndedDoesntFailThisOne() async throws {
        let flow = try chain(errorTo: .agent)
        let engine = try await writerWorking(flow)
        let out = await engine.agentFailed(flow: flow, cardID: try id("Writer", in: flow), reason: "API error",
                                           wholeSession: false, forRun: "an-old-run")
        #expect(out.deliveries.isEmpty && out.log.isEmpty && !out.finished)
        #expect(await engine.isRunning)
    }

    @Test func anEndThatFailsTheRunEndsItAtOnce() async throws {
        // The Boss also hands work to a Checker, which is still working when the Writer fails.
        var flow = try chain(errorTo: .end, failsRun: true)
        try flow.addCard(kind: .agent, name: "Checker")
        try flow.addLink(from: "Boss", to: "Checker")
        let engine = try await writerWorking(flow)
        let out = await engine.agentFailed(flow: flow, cardID: try id("Writer", in: flow), reason: "API error", wholeSession: false)
        #expect(out.finished && out.ending == .failed)
        #expect(out.results.map(\.text) == ["Draft it"])
        #expect(out.log.contains("End \"Oops\" ends the run as failed"))
        let checker = try id("Checker", in: flow)
        #expect(out.leftWaiting == [checker])
        #expect(await !engine.isRunning)
    }

    @Test func anEndThatFailsTheRunStopsOtherCopiesOfTheMessage() async throws {
        // Start → Failed (fails_run) and Start → Writer: the Writer is never handed anything.
        var flow = Flow(name: "Test")
        var start = CardPatch()
        start.command = "Go"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        var fails = CardPatch()
        fails.failsRun = true
        try flow.addCard(kind: .end, name: "Failed", patch: fails)
        try flow.addCard(kind: .agent, name: "Writer")
        try flow.addLink(from: "Start", to: "Failed")
        try flow.addLink(from: "Start", to: "Writer")
        let out = await Engine(judge: ScriptedJudge()).start(flow: flow, startCardID: nil, command: nil)
        #expect(out.finished && out.ending == .failed && out.deliveries.isEmpty)
    }

    @Test func failsRunIsSetAndShownLikeTheEndsOtherSettings() throws {
        var flow = try chain(errorTo: .end)
        var patch = CardPatch()
        patch.failsRun = true
        #expect(try flow.updateCard("Oops", patch: patch).failsRun == true)
        func described() throws -> JSONValue? {
            let json = try JSONValue.parse(Data(Tools.describe(FlowSnapshot(flow: flow, agents: [:], isRunning: false)).text().utf8))
            return try #require(json["cards"]?.arrayValue).first { $0["name"]?.stringValue == "Oops" }?["fails_run"]
        }
        #expect(try described() == .bool(true))
        patch.failsRun = false
        // Off is left out of the file.
        #expect(try flow.updateCard("Oops", patch: patch).failsRun == nil)
        #expect(try described() == .bool(false))
        let writer = try #require(try JSONValue.parse(Data(Tools.describe(FlowSnapshot(flow: flow, agents: [:], isRunning: false)).text().utf8))["cards"]?
            .arrayValue?.first { $0["name"]?.stringValue == "Writer" })
        #expect(writer["outputs"] == .array([.string("out"), .string("error")]))
    }
}
