import Testing
@testable import QueenBeeCore

@Suite struct RunLineTests {
    private func line(_ states: [RunProgress.StopState]) -> [RunProgress.Stop] {
        states.enumerated().map { RunProgress.Stop(id: "s\($0)", name: "Stop \($0)", kind: .agent, state: $1) }
    }

    @Test func theLineIsGreenBetweenStopsTheRunReached() {
        #expect(RunLine.green(line([.done, .done, .live, .notYet])) == [true, true, false])
        #expect(RunLine.green(line([.done, .needsYou, .notYet])) == [true, false])
    }

    @Test func twoStopsARunWasAtTogetherAreJoinedInGreen() {
        // The run was stopped while two agents worked side by side: there is no grey gap between them.
        #expect(RunLine.green(line([.endedHere, .endedHere, .notYet])) == [true, false])
    }

    @Test func aStopTheRunHasntReachedNeverSitsOnGreen() {
        // An If sent the run past B to C. B, not reached, has grey on both sides though C beyond it was reached.
        #expect(RunLine.green(line([.done, .notYet, .live])) == [false, false])
        #expect(RunLine.green(line([.done, .skipped, .done, .done])) == [false, false, true])
    }

    @Test func oneStopOrNoneHasNoLine() {
        #expect(RunLine.green(line([.live])).isEmpty)
        #expect(RunLine.green([]).isEmpty)
    }

    @Test func everythingInViewLeavesNothingOut() {
        let seen = RunLine.OutOfView(offset: 0, content: 520, width: 720, column: 104)
        #expect(seen == RunLine.OutOfView(before: 0, after: 0))
        #expect(seen.pageTarget(back: false, count: 5) == nil)
        #expect(seen.pageTarget(back: true, count: 5) == nil)
    }

    @Test func aStopCutAtTheEdgeCountsAsOutOfView() {
        // 11 stops, 1144 wide, in 720: scrolled 150, so 1½ stops are before and 2½ after.
        let seen = RunLine.OutOfView(offset: 150, content: 1144, width: 720, column: 104)
        #expect(seen == RunLine.OutOfView(before: 2, after: 3))
    }

    @Test func lessThanHalfAPointOutCountsAsInView() {
        let seen = RunLine.OutOfView(offset: 0.4, content: 1144, width: 1143.7, column: 104)
        #expect(seen == RunLine.OutOfView(before: 0, after: 0))
    }

    @Test func arrowsMoveOnByWhatIsInViewLessOneStop() {
        // At the start of 11 stops with 6 wholly in view, going on puts the 6th, index 5, at the start of the view.
        let start = RunLine.OutOfView(offset: 0, content: 1144, width: 720, column: 104)
        #expect(start.after == 5)
        #expect(start.pageTarget(back: false, count: 11) == 5)
        #expect(start.pageTarget(back: true, count: 11) == nil)
        // At the end, going back puts the first stop wholly in view, index 5, at the end of the view.
        let end = RunLine.OutOfView(offset: 424, content: 1144, width: 720, column: 104)
        #expect(end.before == 5)
        #expect(end.pageTarget(back: true, count: 11) == 5)
        #expect(end.pageTarget(back: false, count: 11) == nil)
    }

    @Test func aViewNotLaidOutYetHasNothingOut() {
        #expect(RunLine.OutOfView(offset: 0, content: 1144, width: 0, column: 104) == RunLine.OutOfView())
    }
}
