import Foundation
import Testing
@testable import QueenBeeCore

/// Two kept runs set side by side.
@Suite struct RunComparisonTests {
    /// Start → Writer → Check (If): Yes → Done, No → Writer. Writer's Error → Wait (Delay) → Writer.
    private func flow() throws -> Flow {
        var flow = Flow(name: "Haiku")
        var start = CardPatch()
        start.command = "Write a haiku"
        try flow.addCard(kind: .start, name: "Start", patch: start)
        try flow.addCard(kind: .agent, name: "Writer")
        try flow.addCard(kind: .ifElse, name: "Check")
        try flow.addCard(kind: .end, name: "Done")
        try flow.addCard(kind: .delay, name: "Wait")
        try flow.addCard(kind: .note, name: "Tip")
        try flow.addLink(from: "Start", to: "Writer")
        try flow.addLink(from: "Writer", to: "Check")
        try flow.addLink(from: "Check", port: "yes", to: "Done")
        try flow.addLink(from: "Check", port: "no", to: "Writer")
        try flow.addLink(from: "Writer", port: "error", to: "Wait")
        try flow.addLink(from: "Wait", to: "Writer")
        return flow
    }

    private func id(_ name: String, _ flow: Flow) throws -> String { try #require(flow.resolveCard(name)).id }

    private func link(_ from: String, _ port: String, _ flow: Flow) throws -> String {
        try #require(flow.links(from: try id(from, flow), port: port).first).id
    }

    private func mark(arrivals: Int = 1, _ ports: [String: Int], failed: Bool = false) -> RunMark {
        var mark = RunMark()
        mark.arrivals = arrivals
        mark.passes = ports.values.reduce(0, +)
        mark.ports = ports
        mark.failed = failed
        return mark
    }

    private func said(_ texts: [String]) -> [LinkMessage] {
        texts.map { LinkMessage(date: Date(timeIntervalSince1970: 0), from: "Writer", text: $0) }
    }

    /// Run #1: the Writer's first draft passes. Run #2: the Check sends it back once, then it passes.
    private func runs(_ flow: Flow) throws -> (RunRecord, RunRecord) {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = RunRecord(
            id: "r1", started: start, ended: start.addingTimeInterval(65), outcome: .finished, command: "Write a haiku", log: [],
            results: [try id("Done", flow): "Old pond"],
            marks: [try id("Start", flow): mark(arrivals: 0, ["out": 1]), try id("Writer", flow): mark(["out": 1]),
                    try id("Check", flow): mark(["yes": 1]), try id("Done", flow): mark([:])],
            linkPasses: [:], messages: [try link("Writer", "out", flow): said(["Old pond"])], handOffs: 1,
            usage: [try id("Writer", flow): Usage(cost: 0.10)], ending: .finishedWithAnswer, number: 1)
        let second = RunRecord(
            id: "r2", started: start.addingTimeInterval(3600), ended: start.addingTimeInterval(3600 + 190), outcome: .finished,
            command: "Write a haiku", log: [], results: [try id("Done", flow): "New pond"],
            marks: [try id("Start", flow): mark(arrivals: 0, ["out": 1]), try id("Writer", flow): mark(arrivals: 2, ["out": 2]),
                    try id("Check", flow): mark(arrivals: 2, ["no": 1, "yes": 1]), try id("Done", flow): mark([:])],
            linkPasses: [:], messages: [try link("Writer", "out", flow): said(["Draft", "New pond"])], handOffs: 2,
            usage: [try id("Writer", flow): Usage(cost: 0.25)], ending: .finishedWithAnswer, number: 2)
        return (first, second)
    }

    @Test func theOlderRunComesFirstAndARunIsNeverSetAgainstItself() throws {
        let flow = try flow()
        let (first, second) = try runs(flow)
        let compared = try #require(RunComparison(second, first, in: flow))
        #expect(compared.before.name == "#1" && compared.after.name == "#2")
        #expect(compared.before.length == "1 min 5 sec" && compared.after.length == "3 min 10 sec")
        #expect(RunComparison(first, first, in: flow) == nil)
    }

    @Test func itSaysWhatChangedOverall() throws {
        let flow = try flow()
        let (first, second) = try runs(flow)
        let compared = try #require(RunComparison(first, second, in: flow))
        // Both finished, so the ending isn't a change.
        #expect(compared.changes == ["Hand-offs: 1 → 2", "Cost: $0.10 → $0.25"])
        #expect(compared.comparesReplies && compared.repliesNote == nil)
    }

    @Test func itSaysWhatEachCardDidAndWhatChanged() throws {
        let flow = try flow()
        let (first, second) = try runs(flow)
        let compared = try #require(RunComparison(first, second, in: flow))
        // In canvas order, leaving out the Delay and the Note, which neither run reached.
        #expect(compared.rows.map(\.name) == ["Start", "Writer", "Check", "Done"])
        let start = try #require(compared.rows.first { $0.name == "Start" })
        #expect(!start.isChanged && compared.line(for: start.before, in: start) == "Passed it on")

        let check = try #require(compared.rows.first { $0.name == "Check" })
        #expect(check.changes == ["Went a different way"])
        #expect(compared.line(for: check.before, in: check) == "Yes" && compared.line(for: check.after, in: check) == "Yes · No")

        let writer = try #require(compared.rows.first { $0.name == "Writer" })
        #expect(writer.changes == ["Replies: 1 → 2", "Cost: $0.10 → $0.25"])
        #expect(writer.before.reply == "Old pond" && writer.after.reply == "New pond" && writer.after.replies == 2)
        #expect(compared.line(for: writer.before, in: writer) == "Replied · $0.10")
        #expect(compared.line(for: writer.after, in: writer) == "Out 2 · $0.25")

        let done = try #require(compared.rows.first { $0.name == "Done" })
        #expect(done.changes == ["A different answer"] && done.after.answer == "New pond")
        #expect(compared.line(for: done.before, in: done) == "Got an answer")
    }

    @Test func theSameWayWithADifferentReplyIsAChange() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        second.marks = first.marks
        second.usage = first.usage
        second.messages = [try link("Writer", "out", flow): said(["Old pond, new frog"])]
        let writer = try #require(RunComparison(first, second, in: flow)?.rows.first { $0.name == "Writer" })
        #expect(writer.changes == ["Said something different"])
    }

    @Test func aReplyOnALinkSinceReplacedIsUnknownNotADifference() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        second.marks = first.marks
        second.usage = first.usage
        // The Writer's Out was linked again after #1, so #1's reply is under a link the flow no longer has.
        first.messages = ["an-old-link": said(["Old pond"])]
        second.messages = [try link("Writer", "out", flow): said(["New pond"])]
        let writer = try #require(RunComparison(first, second, in: flow)?.rows.first { $0.name == "Writer" })
        #expect(writer.before.reply == nil && writer.after.reply == "New pond" && writer.before.replies == 1)
        #expect(writer.changes.isEmpty)
    }

    @Test func repliesAreCountedEvenWhenTheirMessagesWerentKept() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        first.messages = [:]
        second.messages = [:]
        let writer = try #require(RunComparison(first, second, in: flow)?.rows.first { $0.name == "Writer" })
        #expect(writer.before.replies == 1 && writer.after.replies == 2 && writer.changes.first == "Replies: 1 → 2")
    }

    @Test func repliesAreComparedOnlyWhenBothRunsKeptThem() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        first.messages = [:]
        let compared = try #require(RunComparison(first, second, in: flow))
        #expect(!compared.comparesReplies && compared.repliesNote?.contains("3 latest runs") == true)
        let writer = try #require(compared.rows.first { $0.name == "Writer" })
        #expect(writer.before.reply == nil && writer.after.reply == nil)
        // How often it replied is in the marks; what it said is not compared.
        #expect(!writer.changes.contains { $0.contains("Said") } && writer.changes.contains("Replies: 1 → 2"))
        // Answers are kept with every run, so they are still compared.
        #expect(compared.rows.first { $0.name == "Done" }?.changes == ["A different answer"])
    }

    @Test func aCostNotWorkedOutIsUnknownNotADifference() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        second.usage = nil
        let compared = try #require(RunComparison(first, second, in: flow))
        #expect(compared.after.cost == nil && !compared.changes.contains { $0.hasPrefix("Cost") })
        let writer = try #require(compared.rows.first { $0.name == "Writer" })
        #expect(writer.after.cost == nil && !writer.changes.contains { $0.hasPrefix("Cost") })
    }

    @Test func aCardTakenOutSinceIsStillListed() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        first.marks["gone1"] = mark(["out": 1])
        let compared = try #require(RunComparison(first, second, in: flow))
        let gone = try #require(compared.rows.last)
        #expect(gone.name == "A card since removed" && gone.kind == nil)
        #expect(gone.changes == ["Reached only in #1"])
        #expect(compared.line(for: gone.after, in: gone) == "Not reached")
        // An agent that got the message but never answered, as in a run stopped before it did.
        var silent = try #require(compared.rows.first { $0.name == "Writer" })
        silent.after.ports = [:]
        silent.after.replies = 0
        #expect(compared.line(for: silent.after, in: silent) == "Didn't reply · $0.25")
    }

    @Test func whatWentOutErrorIsNotAReply() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        // In #2 the Writer failed once: the message it was given went out Error, round the Delay and back.
        second.marks[try id("Writer", flow)] = mark(arrivals: 2, ["error": 1, "out": 1])
        second.marks[try id("Wait", flow)] = mark(["out": 1])
        second.messages = [try link("Writer", "error", flow): said(["Write a haiku"]), try link("Writer", "out", flow): said(["Old pond"])]
        let compared = try #require(RunComparison(first, second, in: flow))
        let writer = try #require(compared.rows.first { $0.name == "Writer" })
        #expect(writer.after.reply == "Old pond" && writer.after.replies == 1)
        #expect(writer.changes.first == "Failed a different number of times")
        #expect(compared.line(for: writer.after, in: writer) == "Out · Error · $0.25")
        #expect(compared.rows.first { $0.name == "Wait" }?.changes == ["Reached only in #2"])
    }

    @Test func whereARunStoppedIsAChange() throws {
        let flow = try flow()
        var (first, second) = try runs(flow)
        second.outcome = .failed
        second.ending = .failed
        second.marks[try id("Writer", flow)] = mark(["out": 2], failed: true)
        let compared = try #require(RunComparison(first, second, in: flow))
        #expect(compared.changes.first == "Ended: finished in #1, failed in #2")
        let writer = try #require(compared.rows.first { $0.name == "Writer" })
        #expect(writer.changes.first == "Stopped the run in #2")
        #expect(compared.line(for: writer.after, in: writer).hasPrefix("Stopped the run"))
    }
}
