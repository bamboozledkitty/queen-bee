import Foundation

/// Which of a flow's runs are kept, and how much of each. A flow keeps its latest runs, and what their links carried
/// for the newest few of those. A run the person keeps for good stays whole, apart from those: it isn't let go
/// when newer runs come, so new runs can always be compared with it.
public enum RunKeeping {
    /// How many runs a flow keeps besides the ones kept for good.
    public static let latest = 20
    /// How many of the newest runs keep the messages their links carried. A run kept for good always does.
    public static let withMessages = 3
    /// How many runs one flow can keep for good, so its history file stays a size that loads and syncs quickly.
    public static let keptLimit = 10

    /// The runs a flow keeps: every run kept for good, the `latest` real runs besides, and the
    /// `Rehearsal.keptLatest` latest rehearsals. Messages stay on the `withMessages` newest runs of all, and on kept ones.
    /// Runs stay in the order they ran.
    public static func trimmed(_ runs: [RunRecord]) -> [RunRecord] {
        var others = 0
        var rehearsals = 0
        var out: [RunRecord] = []
        for (age, run) in runs.reversed().enumerated() {
            if run.isRehearsal {
                rehearsals += 1
                guard rehearsals <= Rehearsal.keptLatest else { continue }
            } else if !run.isKept {
                others += 1
                guard others <= latest else { continue }
            }
            var run = run
            if !run.isKept, age >= withMessages { run.messages = [:] }
            out.append(run)
        }
        return out.reversed()
    }

    /// There is room to keep one more run for good.
    public static func canKeepAnother(_ runs: [RunRecord]) -> Bool {
        runs.filter(\.isKept).count < keptLimit
    }

    /// Keeps run `id` for good, or lets it go back to the usual rules. Nil when that was done, or was so already;
    /// otherwise why not, in words to show. A run let go stays until the next run ends, then goes like any other.
    public static func setKept(_ on: Bool, run id: String, in runs: inout [RunRecord]) -> String? {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return "That run is no longer kept." }
        if on, runs[index].isRehearsal { return Rehearsal.cantKeep }
        guard runs[index].isKept != on else { return nil }
        if on, !canKeepAnother(runs) { return limitReached }
        runs[index].kept = on ? true : nil
        return nil
    }

    /// The runs left when the log is cleared: the ones kept for good.
    public static func afterClear(_ runs: [RunRecord]) -> [RunRecord] { runs.filter(\.isKept) }

    /// Whether Clear also empties the canvas. With none kept, Clear leaves the last real run on the canvas, and
    /// Retry with it, since that run's messages are whole. Anything else on show would be left with no run to say
    /// what it was: a rehearsal, whose messages were a stand-in's, or an earlier run picked in the run picker, whose
    /// messages are cut short. So then the canvas is emptied. A kept run left goes on show in its place instead.
    /// Never while a run or rehearsal is going: the canvas is that run's.
    ///
    /// - Parameter showsLastRealRun: before Clear, the canvas showed the run that ended last, and it wasn't a
    ///   rehearsal. See `Retry.lastRunIsOnShow`.
    public static func clearEmptiesCanvas(showsLastRealRun: Bool, keptLeft: Bool, isRunning: Bool) -> Bool {
        !showsLastRealRun && !keptLeft && !isRunning
    }

    public static let limitReached = "A flow can keep \(keptLimit) runs for good. Stop keeping one of them first."
}

extension RunRecord {
    /// The person kept this run for good. See `RunKeeping`.
    public var isKept: Bool { kept == true }
}

extension RunRecord {
    /// This run was a rehearsal. See `Rehearsal`.
    public var isRehearsal: Bool { rehearsal == true }
}
