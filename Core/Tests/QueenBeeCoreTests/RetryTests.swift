import Foundation
import Testing
@testable import QueenBeeCore

/// Retry is only for the run that ended last: the only one whose messages are kept whole.
@Suite struct RetryTests {
    private func run(_ number: Int?, kept: Bool = false, rehearsal: Bool = false) -> RunRecord {
        let started = Date(timeIntervalSince1970: TimeInterval(number ?? 0) * 60)
        var record = RunRecord(id: "run-\(number.map(String.init) ?? "old")", started: started, ended: started.addingTimeInterval(30),
                               outcome: .failed, command: "Go", log: [], results: [:], marks: [:], linkPasses: [:],
                               messages: [:], handOffs: 1, number: number)
        if kept { record.kept = true }
        if rehearsal { record.rehearsal = true }
        return record
    }

    @Test func theLastRunOnShowCanBeRetried() {
        let runs = [run(1), run(2), run(3)]
        #expect(Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 3))
    }

    @Test func notWhileAnEarlierRunIsPicked() {
        let runs = [run(1), run(2), run(3)]
        #expect(!Retry.lastRunIsOnShow(viewed: "run-2", runs: runs, highestNumber: 3))
    }

    @Test func clearingWithNoneKeptLeavesTheLastRunOnTheCanvas() {
        // The runs are gone, but the last run's marks and its whole messages are still on the canvas.
        let runs = RunKeeping.afterClear([run(1), run(2)])
        #expect(runs.isEmpty)
        #expect(Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 2))
    }

    @Test func clearingKeepsRetryWhenTheLastRunWasKept() {
        let runs = RunKeeping.afterClear([run(1, kept: true), run(2), run(3, kept: true)])
        #expect(runs.compactMap(\.number) == [1, 3])
        #expect(Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 3))
    }

    @Test func notOnAnOlderKeptRunThatClearPutOnShow() {
        // Clear puts the newest kept run on show, and it is the last run left, but not the last to end.
        let runs = RunKeeping.afterClear([run(1), run(2, kept: true), run(3)])
        #expect(runs.compactMap(\.number) == [2])
        #expect(!Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 3))
    }

    @Test func notOnAKeptRunLeftAfterClearingARehearsalThatEndedLast() {
        // A rehearsal can't be kept, so Clear lets it go and puts an older kept run on show.
        let runs = RunKeeping.afterClear([run(1, kept: true), run(2, rehearsal: true)])
        #expect(!Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 2))
    }

    @Test func runsFromBeforeNumbersStillCanBeRetried() {
        #expect(Retry.lastRunIsOnShow(viewed: nil, runs: [run(nil)], highestNumber: 0))
        // Once a run has been numbered, an unnumbered one is older: Clear left it, kept.
        #expect(!Retry.lastRunIsOnShow(viewed: nil, runs: [run(nil, kept: true)], highestNumber: 4))
    }

    @Test func notOnAnUnnumberedKeptRunThatClearMayHaveLeft() {
        // Several runs from before numbers, an older one kept: after Clear it is all that is left, and nothing says
        // a later one didn't end after it.
        var older = run(nil, kept: true)
        older.ended = Date(timeIntervalSince1970: 10)
        var later = run(nil)
        later.ended = Date(timeIntervalSince1970: 20)
        let runs = RunKeeping.afterClear([older, later])
        #expect(runs.count == 1 && runs[0].isKept)
        #expect(!Retry.lastRunIsOnShow(viewed: nil, runs: runs, highestNumber: 0))
    }
}
