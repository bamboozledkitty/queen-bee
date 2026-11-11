import Foundation
import Testing
@testable import QueenBeeCore

/// Which runs a flow keeps, how much of each, and the runs kept for good.
@Suite struct RunKeepingTests {
    private func run(_ number: Int, kept: Bool = false, rehearsal: Bool = false) -> RunRecord {
        let started = Date(timeIntervalSince1970: TimeInterval(number) * 60)
        var record = RunRecord(id: "run-\(number)", started: started, ended: started.addingTimeInterval(30), outcome: .finished,
                               command: "Go", log: [], results: [:], marks: [:], linkPasses: [:],
                               messages: ["link": [LinkMessage(date: started, from: "Writer", text: "Reply \(number)")]],
                               handOffs: 1, number: number)
        if kept { record.kept = true }
        if rehearsal { record.rehearsal = true }
        return record
    }

    @Test func rehearsalsKeepTheirOwnFiveLatest() {
        // 25 real runs, then 7 rehearsals.
        let runs = RunKeeping.trimmed((1...25).map { run($0) } + (26...32).map { run($0, rehearsal: true) })
        #expect(numbers(runs.filter { !$0.isRehearsal }) == Array(6...25))
        #expect(numbers(runs.filter(\.isRehearsal)) == Array(28...32))
        // Messages go by age across all runs, as before.
        #expect(runs.filter { !$0.messages.isEmpty }.compactMap(\.number) == [30, 31, 32])
    }

    @Test func rehearsalsNeverPushARealRunOut() {
        let runs = RunKeeping.trimmed((1...20).map { run($0) } + (21...30).map { run($0, rehearsal: true) })
        #expect(runs.filter { !$0.isRehearsal }.count == 20)
    }

    @Test func aRehearsalCantBeKept() throws {
        var runs = [run(1), run(2, rehearsal: true)]
        let problem = try #require(RunKeeping.setKept(true, run: "run-2", in: &runs))
        #expect(problem == Rehearsal.cantKeep)
        #expect(!runs[1].isKept)
    }

    @Test func aRunFromBeforeRehearsalsIsReal() throws {
        let plain = try #require(String(data: JSONEncoder().encode(run(3)), encoding: .utf8))
        #expect(!plain.contains("rehearsal"))
        let marked = try #require(String(data: JSONEncoder().encode(run(4, rehearsal: true)), encoding: .utf8))
        #expect(marked.contains("\"rehearsal\":true"))
        let back = try JSONDecoder().decode(RunRecord.self, from: Data(plain.utf8))
        #expect(!back.isRehearsal)
    }

    private func numbers(_ runs: [RunRecord]) -> [Int] { runs.compactMap(\.number) }

    @Test func theLatestRunsAreKeptAndOnlyTheNewestKeepTheirMessages() {
        let runs = RunKeeping.trimmed((1...25).map { run($0) })
        #expect(numbers(runs) == Array(6...25))
        #expect(runs.filter { !$0.messages.isEmpty }.compactMap(\.number) == [23, 24, 25])
    }

    @Test func aKeptRunStaysWholePastTheLatestRuns() {
        let runs = RunKeeping.trimmed((1...25).map { run($0, kept: $0 == 2) })
        // The kept run is not one of the 20: the 20 latest besides it stay too.
        #expect(numbers(runs) == [2] + Array(6...25))
        #expect(runs.filter { !$0.messages.isEmpty }.compactMap(\.number) == [2, 23, 24, 25])
    }

    @Test func runsStayInTheOrderTheyRan() {
        let runs = RunKeeping.trimmed((1...23).map { run($0, kept: $0 == 1 || $0 == 21) })
        #expect(numbers(runs) == [1] + Array(3...23))
        #expect(runs.last?.number == 23)
    }

    @Test func aRunIsKeptAndLetGoAgain() throws {
        var runs = (1...5).map { run($0) }
        #expect(RunKeeping.setKept(true, run: "run-1", in: &runs) == nil)
        #expect(runs[0].isKept)
        #expect(RunKeeping.setKept(false, run: "run-1", in: &runs) == nil)
        #expect(!runs[0].isKept && runs[0].kept == nil)
    }

    @Test func aRunLetGoFollowsTheUsualRulesFromTheNextTrim() {
        var runs = (1...25).map { run($0, kept: $0 == 2) }
        runs = RunKeeping.trimmed(runs)
        #expect(RunKeeping.setKept(false, run: "run-2", in: &runs) == nil)
        // Nothing goes at once: it goes with the next run, as any older run would.
        #expect(numbers(runs).first == 2 && !runs[0].messages.isEmpty)
        runs.append(run(26))
        runs = RunKeeping.trimmed(runs)
        #expect(numbers(runs) == Array(7...26))
    }

    @Test func aFlowKeepsAtMostTenRuns() throws {
        var runs = (1...12).map { run($0, kept: $0 <= 10) }
        #expect(!RunKeeping.canKeepAnother(runs))
        let problem = try #require(RunKeeping.setKept(true, run: "run-11", in: &runs))
        #expect(problem.contains("10"))
        #expect(!runs[10].isKept)
        // Letting one go makes room.
        #expect(RunKeeping.setKept(false, run: "run-1", in: &runs) == nil)
        #expect(RunKeeping.canKeepAnother(runs))
        #expect(RunKeeping.setKept(true, run: "run-11", in: &runs) == nil)
    }

    @Test func keepingWhatIsAlreadySoIsFine() {
        var runs = (1...12).map { run($0, kept: $0 <= 10) }
        #expect(RunKeeping.setKept(true, run: "run-1", in: &runs) == nil)
        #expect(RunKeeping.setKept(false, run: "run-12", in: &runs) == nil)
    }

    @Test func aRunThatIsGoneCantBeKept() {
        var runs = (1...3).map { run($0) }
        #expect(RunKeeping.setKept(true, run: "run-9", in: &runs) != nil)
    }

    @Test func clearingTheLogLeavesTheKeptRuns() {
        let runs = (1...5).map { run($0, kept: $0 == 2 || $0 == 4) }
        #expect(numbers(RunKeeping.afterClear(runs)) == [2, 4])
    }

    @Test func clearEmptiesTheCanvasUnlessItShowsTheLastRealRun() {
        // A rehearsal, or an earlier run picked in the run picker, would otherwise stay with no run left to say what
        // it was, and Retry would come back with a stand-in's message or one cut short.
        #expect(RunKeeping.clearEmptiesCanvas(showsLastRealRun: false, keptLeft: false, isRunning: false))
        // The last real run stays until the next run replaces it, with Retry: its messages are whole.
        #expect(!RunKeeping.clearEmptiesCanvas(showsLastRealRun: true, keptLeft: false, isRunning: false))
        // A kept run left goes on show in its place.
        #expect(!RunKeeping.clearEmptiesCanvas(showsLastRealRun: false, keptLeft: true, isRunning: false))
        // Never while a run or rehearsal is going: the canvas is that run's.
        #expect(!RunKeeping.clearEmptiesCanvas(showsLastRealRun: false, keptLeft: false, isRunning: true))
    }

    @Test func aRunFromBeforeKeepingIsNotKept() throws {
        let old = try JSONEncoder().encode(run(1))
        var object = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["kept"] = nil
        let record = try JSONDecoder().decode(RunRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!record.isKept)
        // A kept run says so on the wire, and only then.
        let kept = try #require(String(data: JSONEncoder().encode(run(2, kept: true)), encoding: .utf8))
        let plain = try #require(String(data: JSONEncoder().encode(run(3)), encoding: .utf8))
        #expect(kept.contains("\"kept\":true") && !plain.contains("kept"))
    }
}
