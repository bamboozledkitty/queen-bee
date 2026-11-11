import Foundation

/// The rules of a rehearsal that need no window. A rehearsal runs the whole flow on Haiku at low effort, by
/// throwaway stand-ins of its agents, in a throwaway copy of where the flow works.
/// See docs/superpowers/specs/2026-11-09-rehearsal-mode-design.md.
public enum Rehearsal {
    public static let model = "haiku"
    public static let effort = "low"
    /// How many rehearsals a flow keeps, apart from its real runs.
    public static let keptLatest = 5

    public static let cantKeep = "A rehearsal can't be kept for good. Run the flow for real to keep a run."

    /// The most of a Script card's last real output kept to pass on in a rehearsal, as for a message.
    public static let storedOutputLimit = 8_000
    /// Branches of rehearsal copies start with this, so ones a crash left behind can be found.
    public static let branchPrefix = "queenbee-rehearsal-"

    // MARK: Stand-ins

    static let marker = "@rehearsal"

    /// The key a card's stand-in is known by, in place of the card id, in its session's secret and in the
    /// flow's usage. "<cardID>@rehearsal".
    public static func standInKey(for cardID: String) -> String { cardID + marker }

    /// The card a session key belongs to, and whether that session is the card's stand-in.
    public static func cardID(ofKey key: String) -> (cardID: String, isStandIn: Bool) {
        key.hasSuffix(marker) ? (String(key.dropLast(marker.count)), true) : (key, false)
    }

    /// No MCP servers: with `--strict-mcp-config`, none of the person's own load either.
    public static let noOutsideTools = #"{"mcpServers":{}}"#
    /// What a stand-in may never do, even where its card's permissions would let it.
    public static let refusedTools = ["Bash(git push:*)"]

    /// What a stand-in is started with on top of what every agent is. Its card's own model, effort and browser are
    /// left out (see `standInCard`). Outside git it only looks.
    public static func standInArguments(permissionMode: String?, readOnly: Bool) -> [String] {
        var args = ["--model", model, "--effort", effort, "--strict-mcp-config", "--mcp-config", noOutsideTools,
                    "--disallowedTools", refusedTools.joined(separator: ",")]
        let mode = readOnly ? "plan" : permissionMode.flatMap { Card.permissionModes.contains($0) ? $0 : nil }
        if let mode { args += ["--permission-mode", mode] }
        return args
    }

    /// The card a stand-in is launched from: the agent's own, less what `standInArguments` decides instead.
    public static func standInCard(_ card: Card) -> Card {
        var stand = card
        stand.model = nil
        stand.effort = nil
        stand.permissionMode = nil
        stand.browser = nil
        return stand
    }

    /// Where a card's stand-in works: the card's own folder inside the copy, or the copy itself when the card's
    /// folder is outside the project, which would be a real place.
    public static func folder(forCard cwd: String?, projectRoot: URL, copy: URL) -> String {
        let inCopy = Workplace.folder(forCard: cwd, projectRoot: projectRoot, workRoot: copy)
        let root = copy.standardizedFileURL.path
        let own = URL(fileURLWithPath: inCopy).standardizedFileURL.path
        return own == root || own.hasPrefix(root + "/") ? own : root
    }

    // MARK: Cards

    public enum ScriptStep: Equatable, Sendable {
        /// The command runs for real, in the copy.
        case run
        /// The command doesn't run; this goes out pass instead. `ranBefore` says it is the last real output.
        case passOn(String, ranBefore: Bool)
    }

    public static func scriptStep(for card: Card, lastOutput: String?, readOnly: Bool) -> ScriptStep {
        if card.runsInRehearsals == true, !readOnly { return .run }
        if let lastOutput { return .passOn(lastOutput, ranBefore: true) }
        return .passOn("Rehearsal: skipped `\(card.command ?? "")`, which has never run.", ranBefore: false)
    }

    /// A Script card's output as stored for rehearsals: its end, where a command's result usually is.
    public static func stored(_ output: String) -> String {
        output.count > storedOutputLimit ? String(output.suffix(storedOutputLimit)) : output
    }

    public static func scriptLine(cardName: String, step: ScriptStep) -> String {
        switch step {
        case .run: "\(cardName) runs its command for real, in the copy"
        case .passOn(_, true): "\(cardName) didn't run its command in the rehearsal, and passed on its last real output"
        case .passOn(_, false): "\(cardName) didn't run its command in the rehearsal, and has never run, so it passed on a note"
        }
    }

    public static func delayLine(cardName: String, minutes: Int) -> String {
        "\(cardName) passed the message on at once: in a rehearsal it doesn't wait its \(waitWords(minutes))"
    }

    private static func waitWords(_ minutes: Int) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if minutes >= 1440, minutes % 1440 == 0 { return plural(minutes / 1440, "day") }
        if minutes >= 60, minutes % 60 == 0 { return plural(minutes / 60, "hour") }
        return plural(minutes, "minute")
    }

    // MARK: The log and refusals

    public static func firstLine(readOnly: Bool, scriptsThatRun: [String]) -> String {
        if readOnly {
            return "This is a rehearsal on Haiku at low effort. The project isn't in git, so agents can look but not change anything, and no script runs."
        }
        let scripts = scriptsThatRun.isEmpty ? "No script runs for real."
            : "These scripts run for real, in the copy: \(scriptsThatRun.joined(separator: ", "))."
        return "This is a rehearsal on Haiku at low effort, in a throwaway copy of the project. \(scripts)"
    }

    public static let stoppedForRealRun = "Stopped the rehearsal for a real run"
    public static let busyRefusal = "A run is going. Rehearse once it has ended."
    public static let noOrchestrator = "In a rehearsal, agents can't message the orchestrator. Answer from what you have."
    /// A stand-in messaging a session that isn't one of its flow's stand-ins, which would be somebody's real one.
    public static let onlyThisFlow = "In a rehearsal, agents can only message the other agents of this flow's rehearsal."
    /// What an agent card says over its stand-in's terminal.
    public static let standInLabel = "Rehearsing on Haiku"
    /// Retry starts a real run with the message the card was given, which in a rehearsal was a stand-in's.
    public static let noRetry = "Retry isn't offered after a rehearsal. Run the flow for real, or rehearse it again."

    /// Whether Clear also empties the canvas: when the run on show was a rehearsal and Clear leaves no run kept for
    /// good to show in its place. Otherwise the rehearsal's marks and messages would stay with no run left to say
    /// they were a rehearsal's, and Retry would come back with a stand-in's message. A kept run is never a
    /// rehearsal, so one left goes on show as usual. Never while a run or rehearsal is going.
    public static func clearEmptiesCanvas(runOnShowWasRehearsal: Bool, keptLeft: Bool, isRunning: Bool) -> Bool {
        runOnShowWasRehearsal && !keptLeft && !isRunning
    }
    public static let turningOnRefusal = "Only the person can turn on “Runs in rehearsals”, in the card's settings on their Mac."
    public static let saveLine = "In a rehearsal this was saved in the throwaway copy, so nothing was saved for real"
    /// An End card's save in a rehearsal of a project outside git, which has no copy to save into.
    public static let readOnlySaveLine = "a rehearsal outside git saves nothing"

    /// Why a rehearsal didn't begin when the person's uncommitted changes couldn't be copied in, with what git said.
    public static func uncommittedRefusal(_ gitSaid: String) -> String {
        let said = gitSaid.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Your uncommitted changes couldn't be copied in, so the rehearsal would have tried an older version."
            + " Finish or undo a merge that is part-way, then rehearse again." + (said.isEmpty ? "" : " Git said: \(said)")
    }

    /// The folder in a rehearsal's copy that stands for where the flow works. A copy is of the whole repository, so a
    /// project in a subfolder of its repository works in that subfolder of the copy. `subfolder` is what
    /// `git rev-parse --show-prefix` printed: empty at the repository's top, else the path with a "/" on the end.
    /// Nil for one that would lead out of the copy.
    public static func workFolder(inCopy copy: URL, subfolder: String) -> URL? {
        let parts = subfolder.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").map(String.init)
        guard !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return parts.reduce(copy) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    public static func branch(forRun id: String) -> String { branchPrefix + id }
    public static func isRehearsalBranch(_ name: String) -> Bool { name.hasPrefix(branchPrefix) }

    // MARK: Copies a crash left behind

    /// How old a rehearsal's copy or branch must be before a sweep takes it as left behind. Another flow of the
    /// project, or another copy of the app sharing the project's rehearsals folder, can be rehearsing in a newer one.
    public static let leftoverAge: TimeInterval = 24 * 60 * 60

    /// Whether something made at `made` is old enough to be swept. Something whose age isn't known is kept.
    public static func isLeftover(madeAt made: Date?, now: Date = Date()) -> Bool {
        guard let made else { return false }
        return made < now.addingTimeInterval(-leftoverAge)
    }

    /// When a branch last moved, from git's `log -g -1 --date=unix --format=%gd <branch>`, which prints
    /// "<branch>@{<seconds>}". Nil when that isn't what it printed, as for a branch with no reflog.
    public static func branchMoved(reflogLine line: String) -> Date? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasSuffix("}"), let open = line.range(of: "@{", options: .backwards),
              let seconds = TimeInterval(line[open.upperBound..<line.index(before: line.endIndex)]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
