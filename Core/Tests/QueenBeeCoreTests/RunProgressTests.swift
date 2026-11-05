import Foundation
import Testing
@testable import QueenBeeCore

/// How far a run has got: the number, the stops on its line, and the line that says where it is.
@Suite struct RunProgressTests {
    private func patch(_ edit: (inout CardPatch) -> Void) -> CardPatch {
        var patch = CardPatch()
        edit(&patch)
        return patch
    }

    private func id(_ name: String, in flow: Flow) throws -> String {
        try #require(flow.resolveCard(name)).id
    }

    /// Keeps what the app keeps of a run as the engine's calls come back, and works out its progress.
    private struct Tracker {
        let flow: Flow
        var marks: [String: RunMark] = [:]
        var snapshot: RunSnapshot?
        var ending: RunEnding?
        var shown = 0.0

        init(_ flow: Flow) { self.flow = flow }

        mutating func take(_ output: RunOutput) {
            for visit in output.visits {
                var mark = marks[visit.cardID] ?? RunMark()
                if visit.viaLinkID != nil { mark.arrivals += 1 }
                if let port = visit.port { mark.passes += 1; mark.lastPort = port }
                marks[visit.cardID] = mark
            }
            if let snapshot = output.snapshot { self.snapshot = snapshot }
            if output.finished { ending = output.ending }
        }

        mutating func progress(inner: [String: Double] = [:], needs: [String: RunProgress.Need] = [:]) -> RunProgress {
            let progress = RunProgress(flow: flow, marks: marks, snapshot: snapshot, inner: inner, needs: needs,
                                       ending: ending, shownBefore: shown)
            shown = progress.fraction
            return progress
        }
    }

    private func state(_ name: String, in progress: RunProgress) -> RunProgress.StopState? {
        progress.stops.first { $0.name == name }?.state
    }

    // MARK: The number

    @Test func aStraightLineGoesUpAStopAtATimeAndFinishesAt100() async throws {
        var flow = Flow(name: "Line")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        for name in ["A", "B", "C"] { try flow.addCard(kind: .agent, name: name) }
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "B")
        try flow.addLink(from: "B", to: "C")
        try flow.addLink(from: "C", to: "End")
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)

        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        var progress = run.progress()
        #expect(progress.percent == 0)
        #expect(progress.headline.text == "A working")
        #expect(progress.stops.map(\.name) == ["A", "B", "C", "End"])
        #expect(state("A", in: progress) == .live)
        #expect(state("B", in: progress) == .notYet)

        run.take(await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "a"))
        progress = run.progress()
        #expect(progress.percent == 33)
        #expect(state("A", in: progress) == .done)

        run.take(await engine.agentReplied(flow: flow, cardID: try id("B", in: flow), text: "b"))
        #expect(run.progress().percent == 66)

        run.take(await engine.agentReplied(flow: flow, cardID: try id("C", in: flow), text: "c"))
        progress = run.progress()
        #expect(progress.percent == 100)
        #expect(progress.headline == .init(tone: .finished, text: "Finished"))
        #expect(progress.stops.allSatisfy { $0.state == .done })
    }

    @Test func aBranchNotTakenIsSkippedAndOnlyRaisesTheNumber() async throws {
        var flow = Flow(name: "Branch")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addCard(kind: .ifElse, name: "Short?", patch: patch { $0.check = .contains; $0.value = "short" })
        try flow.addCard(kind: .agent, name: "Quick")
        for name in ["Long 1", "Long 2", "Long 3"] { try flow.addCard(kind: .agent, name: name) }
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "Short?")
        try flow.addLink(from: "Short?", port: "yes", to: "Quick")
        try flow.addLink(from: "Short?", port: "no", to: "Long 1")
        try flow.addLink(from: "Long 1", to: "Long 2")
        try flow.addLink(from: "Long 2", to: "Long 3")
        try flow.addLink(from: "Long 3", to: "End")
        try flow.addLink(from: "Quick", to: "End")
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)

        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        // The longest way still ahead counts: A, then the three on No.
        #expect(run.progress().percent == 0)
        run.take(await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "keep it short"))
        let progress = run.progress()
        #expect(progress.percent == 50)
        #expect(state("Quick", in: progress) == .live)
        #expect(state("Long 1", in: progress) == .skipped)
        #expect(state("Long 3", in: progress) == .skipped)
    }

    @Test func aLoopGoingRoundAgainHoldsTheNumberAndCountsTheTry() async throws {
        var flow = Flow(name: "Loop")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "Writer")
        try flow.addCard(kind: .agent, name: "Reviewer")
        try flow.addCard(kind: .loop, name: "Good?", patch: patch { $0.check = .contains; $0.value = "FINAL"; $0.maxTries = 3 })
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "Writer")
        try flow.addLink(from: "Writer", to: "Reviewer", maxPasses: 10)
        try flow.addLink(from: "Reviewer", to: "Good?", maxPasses: 10)
        try flow.addLink(from: "Good?", port: "again", to: "Writer", maxPasses: 10)
        try flow.addLink(from: "Good?", port: "done", to: "End")
        let writer = try id("Writer", in: flow), reviewer = try id("Reviewer", in: flow)
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)

        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        var progress = run.progress()
        #expect(progress.stops.first { $0.name == "Writer" }?.loopBack?.currentTry == nil)
        run.take(await engine.agentReplied(flow: flow, cardID: writer, text: "draft"))
        #expect(run.progress().percent == 50)

        run.take(await engine.agentReplied(flow: flow, cardID: reviewer, text: "not yet"))
        progress = run.progress()
        #expect(progress.percent == 50)
        #expect(state("Writer", in: progress) == .live)
        // Reviewer comes round again, so it is still to come.
        #expect(state("Reviewer", in: progress) == .notYet)
        #expect(progress.stops.first { $0.name == "Writer" }?.loopBack?.currentTry == 2)
        #expect(progress.headline.text == "Writer working · try 2 of 3")
    }

    @Test func aForEachGivesCreditItemByItem() async throws {
        var flow = Flow(name: "Each")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "a\nb\nc\nd" })
        try flow.addCard(kind: .forEach, name: "Each")
        try flow.addCard(kind: .agent, name: "Worker")
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "Each")
        try flow.addLink(from: "Each", port: "each", to: "Worker")
        try flow.addLink(from: "Worker", to: "Each")
        try flow.addLink(from: "Each", port: "done", to: "End")
        let worker = try id("Worker", in: flow)
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)

        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        var progress = run.progress()
        #expect(progress.percent == 0)
        #expect(progress.stops.first { $0.name == "Worker" }?.items == RunSnapshot.Items(current: 0, count: 4))
        #expect(progress.headline.text == "Worker working · item 1 of 4")
        run.take(await engine.agentReplied(flow: flow, cardID: worker, text: "A"))
        #expect(run.progress().percent == 25)
        run.take(await engine.agentReplied(flow: flow, cardID: worker, text: "B"))
        progress = run.progress()
        #expect(progress.percent == 50)
        #expect(progress.headline.text == "Worker working · item 3 of 4")
    }

    @Test func aForEachsBodyComesBeforeWhatFollowsItsDone() throws {
        var flow = Flow(name: "Order")
        try flow.addCard(kind: .start, name: "Start", x: 0, y: 200, patch: patch { $0.command = "a\nb" })
        try flow.addCard(kind: .forEach, name: "Each", x: 300, y: 200)
        try flow.addCard(kind: .agent, name: "Worker", x: 300, y: 500)
        // Higher on the canvas than Worker, and as many links from Start, but it only comes once the items are done.
        try flow.addCard(kind: .agent, name: "After", x: 600, y: 0)
        try flow.addLink(from: "Start", to: "Each")
        try flow.addLink(from: "Each", port: "each", to: "Worker")
        try flow.addLink(from: "Worker", to: "Each")
        try flow.addLink(from: "Each", port: "done", to: "After")
        let progress = RunProgress(flow: flow, marks: [:], snapshot: RunSnapshot())
        #expect(progress.stops.map(\.name) == ["Worker", "After"])
    }

    @Test func theLeastAdvancedBranchIsWhatCounts() async throws {
        var flow = Flow(name: "Parallel")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        for name in ["Slow 1", "Slow 2", "Fast"] { try flow.addCard(kind: .agent, name: name) }
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "Slow 1")
        try flow.addLink(from: "Start", to: "Fast")
        try flow.addLink(from: "Slow 1", to: "Slow 2")
        try flow.addLink(from: "Slow 2", to: "End")
        try flow.addLink(from: "Fast", to: "End")
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)

        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        run.take(await engine.agentReplied(flow: flow, cardID: try id("Fast", in: flow), text: "done"))
        let progress = run.progress()
        // Fast is done, but Slow 1 and Slow 2 are both still ahead.
        #expect(progress.percent == 33)
        #expect(progress.headline.text == "Slow 1 working")
    }

    @Test func neverAHundredWhileTheRunIsGoing() throws {
        var flow = Flow(name: "Almost")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "End")
        var passed = RunMark()
        passed.arrivals = 1; passed.passes = 1
        // Everything has been through, but the run hasn't said it's over: a judge may still be thinking.
        let progress = RunProgress(flow: flow, marks: [try id("A", in: flow): passed], snapshot: RunSnapshot())
        #expect(progress.percent == 99)
    }

    @Test func aSubflowsProgressMovesItsFlowCard() throws {
        var flow = Flow(name: "Outer")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addCard(kind: .flow, name: "Release", patch: patch { $0.flowRef = "Release" })
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "Release")
        try flow.addLink(from: "Release", port: "done", to: "End")
        let a = try id("A", in: flow), release = try id("Release", in: flow)
        var passed = RunMark()
        passed.arrivals = 1; passed.passes = 1
        let snapshot = RunSnapshot(holding: [release])
        let before = RunProgress(flow: flow, marks: [a: passed], snapshot: snapshot, inner: [release: 0])
        let halfway = RunProgress(flow: flow, marks: [a: passed], snapshot: snapshot, inner: [release: 0.5])
        #expect(before.percent == 50)
        #expect(halfway.percent == 75)
        #expect(halfway.stops.first { $0.name == "Release" }?.inner == 0.5)
        #expect(halfway.headline.text == "Release running its flow")
    }

    @Test func logicCardsLinkedInACircleStillGiveAnAnswer() throws {
        var flow = Flow(name: "Circle")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .ifElse, name: "One")
        try flow.addCard(kind: .ifElse, name: "Two")
        try flow.addCard(kind: .agent, name: "A")
        try flow.addLink(from: "Start", to: "One")
        try flow.addLink(from: "One", port: "yes", to: "Two")
        try flow.addLink(from: "Two", port: "yes", to: "One")
        try flow.addLink(from: "Two", port: "no", to: "A")
        try flow.addLink(from: "A", to: "One")
        let progress = RunProgress(flow: flow, marks: [:], snapshot: RunSnapshot(waitingOn: [try id("A", in: flow)]))
        #expect(progress.percent == 0)
        #expect(progress.stops.map(\.name) == ["A"])
    }

    // MARK: The line

    @Test func anApprovalWaitingSaysItNeedsYou() async throws {
        var flow = Flow(name: "Approve")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addCard(kind: .approval, name: "Ship it?")
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "Ship it?")
        try flow.addLink(from: "Ship it?", port: "approved", to: "End")
        let approval = try id("Ship it?", in: flow)
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)
        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        run.take(await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "ready"))
        let progress = run.progress(needs: [approval: .approval])
        #expect(progress.headline == .init(tone: .needsYou, text: "Needs you: Ship it?", cardID: approval))
        #expect(state("Ship it?", in: progress) == .needsYou)
        #expect(progress.percent == 50)
    }

    @Test func anAgentThatAskedAQuestionNeedsYou() async throws {
        var flow = Flow(name: "Ask")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addLink(from: "Start", to: "A")
        let a = try id("A", in: flow)
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)
        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        #expect(run.progress(needs: [a: .question]).headline.text == "A asked you a question")
    }

    @Test func aStoppedRunSaysWhereAndKeepsItsNumber() async throws {
        var flow = Flow(name: "Fail")
        try flow.addCard(kind: .start, name: "Start", patch: patch { $0.command = "Go" })
        try flow.addCard(kind: .agent, name: "A")
        try flow.addCard(kind: .agent, name: "B")
        try flow.addCard(kind: .end, name: "End")
        try flow.addLink(from: "Start", to: "A")
        try flow.addLink(from: "A", to: "B")
        try flow.addLink(from: "B", to: "End")
        let b = try id("B", in: flow)
        let engine = Engine(judge: ScriptedJudge())
        var run = Tracker(flow)
        run.take(await engine.start(flow: flow, startCardID: nil, command: nil))
        run.take(await engine.agentReplied(flow: flow, cardID: try id("A", in: flow), text: "a"))
        #expect(run.progress().percent == 50)
        run.take(await engine.agentFailed(flow: flow, cardID: b, reason: "rate limit"))
        run.marks[b, default: RunMark()].failed = true
        let progress = run.progress()
        #expect(progress.percent == 50)
        #expect(progress.headline == .init(tone: .failed, text: "Stopped at B", cardID: b))
        #expect(state("B", in: progress) == .failed)
        #expect(state("End", in: progress) == .skipped)
    }
}
