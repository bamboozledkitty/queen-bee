# Rehearsal mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Rehearse action runs the whole flow on Haiku at low effort, using throwaway stand-ins of its agents in a throwaway git copy of where the flow works. It checks routing, loops and approvals without spending much, and without touching the person's files or conversations.

**Architecture:**
- A rehearsal is an ordinary run of the same flow, with a flag on its `RunRecord`. The engine knows nothing of it.
- `FlowController` sends each agent card's hand-offs to a stand-in session instead of the card's own. It runs Script, Delay and End cards by the rehearsal rules, and works in a git worktree made for the rehearsal and removed afterwards.
- Every rule that needs no window lives in `Core/Sources/QueenBeeCore/Rehearsal.swift`, with tests.

**Tech Stack:**
- Swift 6 and Swift Testing, in Core.
- SwiftUI and AppKit for the Mac; SwiftUI for the iPad and iPhone.
- Claude Code's CLI flags: `--model`, `--effort`, `--strict-mcp-config`, `--mcp-config`, `--disallowedTools`, `--permission-mode`, `--session-id`.

**Spec:** `docs/superpowers/specs/2026-11-09-rehearsal-mode-design.md`

**Branch:** `claude/rehearsal-mode`, which sits on `claude/keep-a-run` (PR 35).

**Ground rules from AGENTS.md:**
- Run `cd Core && swift test` after every Core task.
- Run `./scripts/build.sh` after any App task, and `./scripts/build-mobile.sh` after any Mobile or Core task.
- Run `./scripts/check-clean.sh` before every commit.
- Never edit `CAPABILITIES.md` by hand: `build.sh` rewrites it.
- Colours, sizes and spacing come from `QueenBeeDesign` only.
- Don't push, and ask Keith before running `scripts/e2e.py`.

Checked before writing this plan:
- The qb-link plugin (`Plugin/qb-link`) has hooks only and no MCP server. `--strict-mcp-config` with an empty `--mcp-config` therefore removes every outside tool server without touching hand-offs.
- `UsageReader.usage(sessionID:)` finds a transcript in any folder under `~/.claude/projects`, so a stand-in's cost is found wherever it works.

---

## File map

| File | Change |
|---|---|
| `Core/Sources/QueenBeeCore/Rehearsal.swift` | **New.** Stand-in keys, launch arguments, folder, Script and Delay rules, log lines, refusals. |
| `Core/Tests/QueenBeeCoreTests/RehearsalTests.swift` | **New.** Tests for the above. |
| `Core/Sources/QueenBeeCore/RunState.swift` | `RunRecord.rehearsal`, `isRehearsal`. |
| `Core/Sources/QueenBeeCore/RunKeeping.swift` | Rehearsals trimmed to their own 5; refused for keeping. |
| `Core/Tests/QueenBeeCoreTests/RunKeepingTests.swift` | Rehearsal cases. |
| `Core/Sources/QueenBeeCore/Model.swift` | `Card.runsInRehearsals`, `CardPatch.runsInRehearsals`. |
| `Core/Sources/QueenBeeCore/Mutations.swift` | Apply `runsInRehearsals` to Script cards. |
| `Core/Sources/QueenBeeCore/Capabilities.swift` | Describe `runs_in_rehearsals`, and the `rehearse_flow` tool's notes. |
| `Core/Sources/QueenBeeCore/Tools.swift` | Parse `runs_in_rehearsals` (refuse true); report it; `rehearse_flow` tool; `ToolHost.rehearseFlow`. |
| `Core/Sources/QueenBeeCore/Remote.swift` | `RemoteFeature.rehearsals`; `RemoteCommand.rehearse`; `RemoteCardPatch.runsInRehearsals` (refuse true); `RemoteRunState.rehearsal`. |
| `Core/Tests/QueenBeeCoreTests/Remote*Tests.swift`, `ToolsTests.swift`, `MutationsTests.swift` | Cases and the fingerprint. |
| `App/Sessions/Git.swift` | Make, remove and sweep rehearsal copies. |
| `App/Sessions/ClaudeLauncher.swift` | `standIn(...)` launch spec. |
| `App/FlowController.swift` | Rehearsal state, stand-ins, hook translation, holds, saving, real-run-wins, cleanup, script outputs. |
| `App/Canvas/AgentCardView.swift` | Show a stand-in's terminal and the strip. |
| `App/Views/FlowHeader.swift`, `RunProgressViews.swift`, `PlaceViews.swift`, `SidePanel.swift`, `RunCompareView.swift` | Rehearse in the Run menu, pills, no Keep, no Compare. |
| `App/Remote/RemoteHost.swift`, `RemoteCommands.swift` | Feature flag, `.rehearse`, run state flag, patch refusal. |
| `App/Testing/TestHarness.swift` | `rehearse` op, state fields. |
| `Mobile/...` | Rehearse control, row pill, canned Mac, parity step. |
| `Tools/RemoteCheck/main.swift` | `rehearse` command. |
| `scripts/e2e.py` | Checks in gates, remote, parity. |
| `CHANGELOG.md`, `SECURITY.md`, the spec | Words. |

---

### Task 1: Rehearsal records and how they're kept

**Files:**
- Modify: `Core/Sources/QueenBeeCore/RunState.swift` (`RunRecord`, around line 208)
- Modify: `Core/Sources/QueenBeeCore/RunKeeping.swift`
- Create: `Core/Sources/QueenBeeCore/Rehearsal.swift` (the constants only, for now)
- Test: `Core/Tests/QueenBeeCoreTests/RunKeepingTests.swift`

- [ ] **Step 1: Write the failing tests.** Add to `RunKeepingTests`, and extend the helper so it can make a rehearsal:

```swift
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
```

- [ ] **Step 2: Run the tests and watch them fail.**

Run: `cd Core && swift test --filter RunKeepingTests`
Expected: they fail to compile, because `rehearsal`, `isRehearsal` and `Rehearsal` don't exist yet.

- [ ] **Step 3: Add the field.** In `RunRecord` (RunState.swift), next to `kept`:

```swift
    /// True for a rehearsal: a run on Haiku by stand-ins of the agents, in a throwaway copy. Nil for a real run,
    /// which is how every run from before rehearsals reads.
    public var rehearsal: Bool?
```

Add `rehearsal: Bool? = nil` to the memberwise `init` after `kept`, and assign it there. At the bottom of `RunKeeping.swift`, next to `isKept`:

```swift
extension RunRecord {
    public var isRehearsal: Bool { rehearsal == true }
}
```

- [ ] **Step 4: Create `Rehearsal.swift` with the constants Task 1 needs.**

```swift
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
}
```

- [ ] **Step 5: Change `RunKeeping`.** Replace `trimmed` and add the check to `setKept`:

```swift
    /// The runs a flow keeps: every run kept for good, the `latest` real runs besides, and the
    /// `Rehearsal.keptLatest` latest rehearsals. Messages stay on the `withMessages` newest runs of all, and on kept ones.
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
```

In `setKept`, right after the `guard let index` line:

```swift
        if on, runs[index].isRehearsal { return Rehearsal.cantKeep }
```

- [ ] **Step 6: Run the tests and watch them pass.**

Run: `cd Core && swift test --filter RunKeepingTests`
Expected: every RunKeepingTests test passes, the old ones included.

- [ ] **Step 7: Run all Core tests, then commit.**

```bash
cd Core && swift test && cd .. && ./scripts/check-clean.sh
git add Core/Sources/QueenBeeCore/RunState.swift Core/Sources/QueenBeeCore/RunKeeping.swift Core/Sources/QueenBeeCore/Rehearsal.swift Core/Tests/QueenBeeCoreTests/RunKeepingTests.swift
git commit -m "Rehearsal mode: a rehearsal's record, kept apart from real runs"
```

---

### Task 2: The rehearsal rules in Core

**Files:**
- Modify: `Core/Sources/QueenBeeCore/Rehearsal.swift`
- Create: `Core/Tests/QueenBeeCoreTests/RehearsalTests.swift`

This task adds `Card.runsInRehearsals` itself (Step 3a), because its rules read it. Task 3 then wires the setting everywhere else.

In the test helper, make the `Card` the way the neighbouring Core tests do (`grep -rn "Card(id:" Core/Tests | head`). The initializer shown is a guess at its shape.

- [ ] **Step 1: Write the failing tests.**

```swift
import Foundation
import Testing
@testable import QueenBeeCore

/// What a rehearsal does that needs no window.
@Suite struct RehearsalTests {
    private func card(_ kind: CardKind, command: String? = nil, cwd: String? = nil, mode: String? = nil,
                      runs: Bool? = nil, browser: Bool? = nil) -> Card {
        var card = Card(id: "c1", kind: kind, name: "Tests", x: 0, y: 0, width: 200, height: 100)
        card.command = command
        card.cwd = cwd
        card.permissionMode = mode
        card.runsInRehearsals = runs
        card.browser = browser
        card.model = "opus"
        card.effort = "max"
        return card
    }

    @Test func aStandInsKeyIsToldApartFromItsCards() {
        let key = Rehearsal.standInKey(for: "abc")
        #expect(Rehearsal.cardID(ofKey: key) == ("abc", true))
        #expect(Rehearsal.cardID(ofKey: "abc") == ("abc", false))
        #expect(Rehearsal.cardID(ofKey: "orchestrator") == ("orchestrator", false))
    }

    @Test func aStandInRunsOnHaikuWithNoOutsideToolsAndNoPush() {
        let args = Rehearsal.standInArguments(permissionMode: "acceptEdits", readOnly: false)
        #expect(args.containsInOrder(["--model", "haiku"]))
        #expect(args.containsInOrder(["--effort", "low"]))
        #expect(args.contains("--strict-mcp-config"))
        #expect(args.containsInOrder(["--mcp-config", Rehearsal.noOutsideTools]))
        #expect(args.containsInOrder(["--disallowedTools", "Bash(git push:*)"]))
        #expect(args.containsInOrder(["--permission-mode", "acceptEdits"]))
    }

    @Test func aStandInOutsideGitOnlyLooks() {
        let args = Rehearsal.standInArguments(permissionMode: "auto", readOnly: true)
        #expect(args.containsInOrder(["--permission-mode", "plan"]))
        #expect(!args.contains("auto"))
    }

    @Test func aModeNoCardMayAskForIsLeftOut() {
        let args = Rehearsal.standInArguments(permissionMode: "bypassPermissions", readOnly: false)
        #expect(!args.contains("--permission-mode"))
    }

    @Test func aStandInCardHasNoBrowserAndNoOwnModel() {
        let stand = Rehearsal.standInCard(card(.agent, mode: "auto", browser: true))
        #expect(stand.browser == nil && stand.model == nil && stand.effort == nil && stand.permissionMode == nil)
    }

    @Test func aStandInWorksInTheCopyAndNeverOutside() {
        let project = URL(fileURLWithPath: "/work/app")
        let copy = URL(fileURLWithPath: "/support/rehearsals/r1")
        #expect(Rehearsal.folder(forCard: nil, projectRoot: project, copy: copy) == "/support/rehearsals/r1")
        #expect(Rehearsal.folder(forCard: "web", projectRoot: project, copy: copy) == "/support/rehearsals/r1/web")
        #expect(Rehearsal.folder(forCard: "/work/app/api", projectRoot: project, copy: copy) == "/support/rehearsals/r1/api")
        // A folder outside the project would be real work in a real place, so the stand-in stays in the copy.
        #expect(Rehearsal.folder(forCard: "/elsewhere", projectRoot: project, copy: copy) == "/support/rehearsals/r1")
        #expect(Rehearsal.folder(forCard: "~/notes", projectRoot: project, copy: copy) == "/support/rehearsals/r1")
    }

    @Test func aScriptIsSkippedUnlessItsCardAllows() {
        #expect(Rehearsal.scriptStep(for: card(.script, command: "make test"), lastOutput: "ok", readOnly: false) == .passOn("ok", ranBefore: true))
        #expect(Rehearsal.scriptStep(for: card(.script, command: "make test"), lastOutput: nil, readOnly: false)
                == .passOn("Rehearsal: skipped `make test`, which has never run.", ranBefore: false))
        #expect(Rehearsal.scriptStep(for: card(.script, command: "make test", runs: true), lastOutput: nil, readOnly: false) == .run)
        // Read-only, nothing runs.
        #expect(Rehearsal.scriptStep(for: card(.script, command: "make test", runs: true), lastOutput: "ok", readOnly: true) == .passOn("ok", ranBefore: true))
    }

    @Test func aStoredOutputKeepsItsEnd() {
        let long = String(repeating: "a", count: 9_000) + "END"
        let kept = Rehearsal.stored(long)
        #expect(kept.count == Rehearsal.storedOutputLimit && kept.hasSuffix("END"))
        #expect(Rehearsal.stored("short") == "short")
    }

    @Test func theLogSaysWhatADelayWouldHaveWaited() {
        #expect(Rehearsal.delayLine(cardName: "Wait", minutes: 1) == "Wait passed the message on at once: in a rehearsal it doesn't wait its 1 minute")
        #expect(Rehearsal.delayLine(cardName: "Wait", minutes: 120) == "Wait passed the message on at once: in a rehearsal it doesn't wait its 2 hours")
        #expect(Rehearsal.delayLine(cardName: "Wait", minutes: 2880) == "Wait passed the message on at once: in a rehearsal it doesn't wait its 2 days")
        #expect(Rehearsal.delayLine(cardName: "Wait", minutes: 90) == "Wait passed the message on at once: in a rehearsal it doesn't wait its 90 minutes")
    }

    @Test func theFirstLineSaysWhereItWorks() {
        #expect(Rehearsal.firstLine(readOnly: false, scriptsThatRun: [])
                == "This is a rehearsal on Haiku at low effort, in a throwaway copy of the project. No script runs for real.")
        #expect(Rehearsal.firstLine(readOnly: false, scriptsThatRun: ["Tests", "Lint"])
                == "This is a rehearsal on Haiku at low effort, in a throwaway copy of the project. These scripts run for real, in the copy: Tests, Lint.")
        #expect(Rehearsal.firstLine(readOnly: true, scriptsThatRun: ["Tests"])
                == "This is a rehearsal on Haiku at low effort. The project isn't in git, so agents can look but not change anything, and no script runs.")
    }

    @Test func aCopysBranchIsKnownForSweeping() {
        #expect(Rehearsal.branch(forRun: "r-1") == "queenbee-rehearsal-r-1")
        #expect(Rehearsal.isRehearsalBranch("queenbee-rehearsal-r-1"))
        #expect(!Rehearsal.isRehearsalBranch("main"))
    }
}

extension Array where Element == String {
    /// Whether `pair` appears side by side, in that order.
    func containsInOrder(_ pair: [String]) -> Bool {
        guard pair.count == 2 else { return false }
        return zip(self, dropFirst()).contains { $0 == pair[0] && $1 == pair[1] }
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail.**

Run: `cd Core && swift test --filter RehearsalTests`
Expected: they fail to compile, because the functions are missing.

- [ ] **Step 3a: Add the field to `Card`** (Model.swift, after `failsRun` at line 130):

```swift
    // Script
    /// True runs the card's command for real in a rehearsal, in the rehearsal's copy. Nil skips it there.
    /// Only the person turns it on, on the Mac.
    public var runsInRehearsals: Bool?
```

- [ ] **Step 3: Fill in `Rehearsal.swift`.** Add these inside `enum Rehearsal`:

```swift
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
    public static let turningOnRefusal = "Only the person can turn on “Runs in rehearsals”, in the card's settings on their Mac."
    public static let saveLine = "In a rehearsal this was saved in the throwaway copy, so nothing was saved for real"

    public static func branch(forRun id: String) -> String { branchPrefix + id }
    public static func isRehearsalBranch(_ name: String) -> Bool { name.hasPrefix(branchPrefix) }
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `cd Core && swift test --filter RehearsalTests`
Expected: all pass. If `folder` fails on the `~` case, check `Workplace.folder`: it returns a `~` path as given, and `standardizedFileURL` keeps the `~`. That path doesn't start with the copy, so it falls back to the copy.

- [ ] **Step 5: Run all Core tests, then commit.**

```bash
cd Core && swift test && cd .. && ./scripts/check-clean.sh
git add Core/Sources/QueenBeeCore/Rehearsal.swift Core/Tests/QueenBeeCoreTests/RehearsalTests.swift
git commit -m "Rehearsal mode: the rules a rehearsal follows, in Core"
```

---

### Task 3: The "Runs in rehearsals" setting

**Files:**
- Modify: `Core/Sources/QueenBeeCore/Model.swift` (`Card` near `failsRun`, line 130; `CardPatch` near line 333)
- Modify: `Core/Sources/QueenBeeCore/Mutations.swift` (`case .start, .script:` at line 245)
- Modify: `Core/Sources/QueenBeeCore/Capabilities.swift` (`case .script:` settings, near line 140)
- Modify: `Core/Sources/QueenBeeCore/Tools.swift` (fields near line 229; parsing near line 482)
- Modify: `Core/Sources/QueenBeeCore/Remote.swift` (`RemoteCardPatch`, lines 496 to 610)
- Test: `Core/Tests/QueenBeeCoreTests/MutationsTests.swift`, `ToolsTests.swift`, `RemoteParityTests.swift` (or wherever `RemoteCardPatch.problem` is tested: `grep -rn "patch.problem\|\.problem ==" Core/Tests`)

- [ ] **Step 1: Write the failing tests.**

In `MutationsTests`, follow the style of the test for `failsRun` (find it with `grep -n failsRun Core/Tests/QueenBeeCoreTests/MutationsTests.swift`):

```swift
    @Test func aScriptCardCanBeSetToRunInRehearsals() throws {
        var flow = Flow.sample()   // use whatever helper the neighbouring tests use to make a flow with a Script card
        let id = try #require(flow.cards.first { $0.kind == .script }?.id)
        var patch = CardPatch()
        patch.runsInRehearsals = true
        try Mutations.update(&flow, card: id, patch)   // use the same call the failsRun test uses
        #expect(flow.card(id)?.runsInRehearsals == true)
        patch.runsInRehearsals = false
        try Mutations.update(&flow, card: id, patch)
        #expect(flow.card(id)?.runsInRehearsals == nil)
    }
```

In `ToolsTests`, beside the tests for `update_card`:

```swift
    @Test func theOrchestratorCantTurnOnRunsInRehearsals() async throws {
        // Build the host and Script card as the neighbouring update_card tests do.
        await #expect(throws: FlowError.self) {
            _ = try await Tools.call("update_card", ["card": "Tests", "runs_in_rehearsals": true], host: host)
        }
        // Off is allowed.
        _ = try await Tools.call("update_card", ["card": "Tests", "runs_in_rehearsals": false], host: host)
    }
```

Where `RemoteCardPatch.problem` is tested:

```swift
    @Test func aDeviceCantTurnOnRunsInRehearsals() {
        var on = RemoteCardPatch()
        on.runsInRehearsals = true
        #expect(on.problem == Rehearsal.turningOnRefusal)
        var off = RemoteCardPatch()
        off.runsInRehearsals = false
        #expect(off.problem == nil)
    }
```

- [ ] **Step 2: Run the tests and watch them fail.**

Run: `cd Core && swift test --filter "Mutations|Tools|Remote"`
Expected: they fail to compile, because `runsInRehearsals` doesn't exist.

- [ ] **Step 3: Add the field to `CardPatch`.** `Card.runsInRehearsals` is already there from Task 2. In `CardPatch`, after `failsRun`:

```swift
    public var runsInRehearsals: Bool?
```

- [ ] **Step 4: Apply it in `Mutations`.** In `case .start, .script:`, after the `waitMinutes` line:

```swift
            if card.kind == .script, let runs = patch.runsInRehearsals { card.runsInRehearsals = runs ? true : nil }
```

- [ ] **Step 5: Describe it in `Capabilities.swift`.** In `case .script:` settings, after `wait_minutes`:

```swift
                    SettingCapability("runs_in_rehearsals", ["type": "boolean"], "false skips this card's command in a rehearsal, the default: it passes on its output from the last real run instead. Only the person can turn it on, in the card's settings on their Mac."),
```

Add a note to the same card:

```swift
                    "In a rehearsal the command is skipped, and the card passes on its last real output or a note, unless the person has turned on runs_in_rehearsals.",
```

- [ ] **Step 6: Parse and report it in `Tools.swift`.** In the card fields reported for a Script card (near `fields["fails_run"]`; add it in the branch for `.script`):

```swift
                fields["runs_in_rehearsals"] = .bool(card.runsInRehearsals == true)
```

In the patch parsing, after `patch.failsRun = try bool("fails_run")`:

```swift
        patch.runsInRehearsals = try bool("runs_in_rehearsals")
        if patch.runsInRehearsals == true { throw FlowError.invalid(Rehearsal.turningOnRefusal) }
```

- [ ] **Step 7: Add it to `RemoteCardPatch`.** Add the stored property after `failsRun`:

```swift
    /// Script: only off may be sent from a device. See `problem`.
    public var runsInRehearsals: Bool?
```

Copy it in the `CardPatch` conversion, beside `patch.failsRun = failsRun`:

```swift
        patch.runsInRehearsals = runsInRehearsals
```

Pass it through unchanged in `cleaned`. At the top of `problem`, after the `isEmpty` line:

```swift
        if runsInRehearsals == true { return Rehearsal.turningOnRefusal }
```

Also add the field to `RemoteCardPatch`'s `init`, if it has an explicit one.

- [ ] **Step 8: Name the setting in the Mac's log of device edits.** In `App/Remote/RemoteCommands.swift:865`, add `(patch.runsInRehearsals != nil, "whether it runs in rehearsals")` to the list of named settings.

- [ ] **Step 9: Run the tests, then rebuild `CAPABILITIES.md`.**

```bash
cd Core && swift test && cd ..
./scripts/build.sh
cd Core && swift test && cd ..
```

Expected:
- The first `swift test` may fail only on the test that checks `CAPABILITIES.md` is up to date.
- `build.sh` rewrites `CAPABILITIES.md`.
- The second `swift test` passes in full.

- [ ] **Step 10: Commit.**

```bash
./scripts/check-clean.sh
git add Core App/Remote/RemoteCommands.swift CAPABILITIES.md
git commit -m "Rehearsal mode: a Script card can be set to run in rehearsals, by the person only"
```

---

### Task 4: `rehearse_flow` for the orchestrator

**Files:**
- Modify: `Core/Sources/QueenBeeCore/Tools.swift` (`ToolHost` near line 44; the `run_flow` case at line 155; the `run_flow` definition at line 339)
- Modify: `Core/Sources/QueenBeeCore/Capabilities.swift` (the part that lists what the orchestrator's tools can do; find it with `grep -n "run_flow" Core/Sources/QueenBeeCore/Capabilities.swift`, and if there's none, the general notes section)
- Modify: every `ToolHost` conformer, in tests and the app (`grep -rn ": ToolHost\|ToolHost {" Core App`)
- Test: `Core/Tests/QueenBeeCoreTests/ToolsTests.swift`

- [ ] **Step 1: Write the failing test.** Use the fake host in `ToolsTests`, and record calls as its `runFlow` does:

```swift
    @Test func rehearseFlowStartsARehearsal() async throws {
        let host = FakeHost()   // the existing test host
        let said = try await Tools.call("rehearse_flow", ["command": "Try it"], host: host)
        #expect(await host.rehearsed == ["Try it"])
        #expect(!said.isEmpty)
    }
```

Add `var rehearsed: [String?] = []` to the fake host, and implement `func rehearseFlow(command: String?) async throws -> String { rehearsed.append(command); return "Rehearsal started" }`.

- [ ] **Step 2: Run it and watch it fail.**

Run: `cd Core && swift test --filter ToolsTests`
Expected: it fails to compile, because there's no `rehearseFlow`.

- [ ] **Step 3: Add to `ToolHost`.**

```swift
    func rehearseFlow(command: String?) async throws -> String
```

Add the case beside `run_flow`:

```swift
        case "rehearse_flow":
            return try await host.rehearseFlow(command: try arguments.string("command"))
```

Add the definition after `run_flow`'s:

```swift
        ToolDefinition(
            name: "rehearse_flow",
            description: """
            Start a rehearsal: a run of the whole flow on Haiku at low effort, by throwaway copies of its agents, \
            in a throwaway copy of the project. Use it to check a flow's routing after you change it. It returns once \
            the rehearsal has started: follow it with get_run_log. What a rehearsal does at each card is in the \
            capabilities reference.
            """,
            inputSchema: schema(["command": ["type": "string", "description": "What to send in place of the Start card's command."]])),
```

- [ ] **Step 4: Say what a rehearsal does in `Capabilities.swift`.** Find the section that `CAPABILITIES.md` builds its general notes from (search for "## " headings in `Capabilities.swift`), and add a "## Rehearsals" section with these lines:

```swift
        lines += ["", "## Rehearsals", ""]
        lines += [
            "- rehearse_flow runs the whole flow on Haiku at low effort, by throwaway copies of its agents that don't remember their real conversations, in a throwaway git copy of the project that is deleted afterwards. Outside git the copies can only look.",
            "- The copies have no browser, none of the person's other tool servers, and can't git push. Other commands, such as curl, still really run.",
            "- Script cards are skipped and pass on their last real output, unless the person turned on runs_in_rehearsals. Delay cards pass on at once. Approvals ask the person as usual. Files End cards save go into the copy.",
            "- A rehearsal never starts while a run is going. A real run stops a rehearsal.",
            "- Rehearsals are kept apart from real runs (the \(Rehearsal.keptLatest) latest) and can't be kept for good.",
        ]
```

- [ ] **Step 5: Give every app `ToolHost` a stub, so the build passes.** In `App/FlowController.swift` near `runFlow(command:)` (line 3024):

```swift
    func rehearseFlow(command: String?) async throws -> String {
        let started = await start(command: command, rehearse: true)
        guard started.began else { throw FlowError.invalid(started.status) }
        return started.status
    }
```

`start(…rehearse:)` comes in Task 7. Until then, write the body as `throw FlowError.invalid("Rehearsals aren't ready yet.")` and come back to it in Task 7, Step 9.

- [ ] **Step 6: Run the tests, rebuild, run again, commit.**

```bash
cd Core && swift test && cd .. && ./scripts/build.sh && cd Core && swift test && cd ..
./scripts/check-clean.sh
git add Core App/FlowController.swift CAPABILITIES.md
git commit -m "Rehearsal mode: the orchestrator can start a rehearsal"
```

---

### Task 5: The wire: Rehearse from a device, and a rehearsal's run state

**Files:**
- Modify: `Core/Sources/QueenBeeCore/Remote.swift` (`RemoteFeature` near line 127; `RemoteCommand` near line 654; the `flowID`, `isEdit`, `cleaned` and `contentProblem` switches; `RemoteRunState` at line 321)
- Modify: `Core/Sources/QueenBeeCore/RemoteMirror.swift` (`macKeepsRuns` is the pattern)
- Test: `Core/Tests/QueenBeeCoreTests/RemoteParityTests.swift`, `RemoteWireTests.swift`

- [ ] **Step 1: Write the failing tests.** Add `.rehearse(flowID: "f", startCardID: nil)` and `.rehearse(flowID: "f", startCardID: "s")` to the lists of commands in `RemoteParityTests` and `RemoteWireTests`, wherever `.keepRun` was added (`grep -n keepRun Core/Tests`).

In `RemoteWireTests`, add:

```swift
    @Test func aRunStateFromBeforeRehearsalsIsReal() throws {
        // Encode a RemoteRunState the way the other tests make one, drop "rehearsal", and decode it.
        var state = RemoteRunState.sample()   // or the neighbouring helper
        state.rehearsal = true
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["rehearsal"] = nil
        let back = try JSONDecoder().decode(RemoteRunState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(back.rehearsal == nil)
    }
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `cd Core && swift test --filter Remote`
Expected: they fail to compile.

- [ ] **Step 3: Add the feature, the command and the field.**

```swift
    /// The Mac can rehearse a flow for a device: `RemoteCommand.rehearse`.
    public static let rehearsals = "rehearsals"
```

Add the command after `runFromStart`:

```swift
    /// Rehearse the flow: a run on Haiku by stand-ins, in a throwaway copy. From the given Start card, or the usual one.
    case rehearse(flowID: String, startCardID: String?)
```

In the switches:
- `flowID`: `case .rehearse(let id, _): id`
- `isEdit`: `false`
- `cleaned`: `self`
- `contentProblem`: `nil`, unless the switch checks `startCardID` lengths. If `runFromStart` is checked against an id limit there, check this one the same way.

In `RemoteRunState`, add:

```swift
    /// True while the run going is a rehearsal. Nil from a Mac before rehearsals, and for a real run.
    public var rehearsal: Bool?
```

Add it as `rehearsal: Bool? = nil` in its `init`, if it has an explicit one.

In `RemoteMirror.swift`:

```swift
    public var macRehearses: Bool { welcome?.has(RemoteFeature.rehearsals) == true }
```

- [ ] **Step 4: Update the fingerprint.** Run `cd Core && swift test --filter theWireFormatMatchesItsVersion`. It fails and prints the new fingerprint. Put that value in `RemoteWireTests.fingerprints` for version 5. Don't change `Remote.version`: both additions are optional, and an older app ignores what it doesn't know. Read the comment above `fingerprints` to confirm that's the rule.

- [ ] **Step 5: Run all Core tests and build the mobile app.** Mobile switches over `RemoteCommand` may need the new case, so the build may fail. If it does, add `case .rehearse: break` where the compiler asks, then do the real work in Task 12.

```bash
cd Core && swift test && cd .. && ./scripts/build-mobile.sh && ./scripts/build.sh
```

- [ ] **Step 6: Commit.**

```bash
./scripts/check-clean.sh
git add Core Mobile App
git commit -m "Rehearsal mode: a device can ask for a rehearsal, and sees when a run is one"
```

---

### Task 6: Throwaway copies in git

**Files:**
- Modify: `App/Sessions/Git.swift`

There are no unit tests in `App/`. Task 13's e2e checks the copy is made and gone, and a manual check follows in Step 3.

- [ ] **Step 1: Add the three functions to `enum Git`.**

```swift
    /// Makes a throwaway copy of `source`, where a flow works, for the rehearsal `runID`: a worktree on a new
    /// branch at `source`'s current commit, in `folder`, with `source`'s uncommitted changes, tracked and untracked
    /// but not ignored, copied in. The copy's path, or what went wrong.
    nonisolated static func makeRehearsalCopy(of source: URL, runID: String, in folder: URL) async -> Result<URL, RehearsalCopyError> {
        let copy = folder.appendingPathComponent(runID, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let branch = Rehearsal.branch(forRun: runID)
        let made = await run(["worktree", "add", "-b", branch, copy.path, "HEAD"], in: source)
        guard made.ok else { return .failure(.init(made.error.isEmpty ? "git couldn't make the copy." : made.error)) }
        // Tracked changes: a stash commit made without touching the working tree, applied in the copy.
        let stash = await run(["stash", "create"], in: source)
        if stash.ok, !stash.output.isEmpty {
            let applied = await run(["stash", "apply", stash.output], in: copy)
            if !applied.ok { return .failure(.init("Your uncommitted changes couldn't be copied in: \(applied.error)")) }
        }
        // Untracked files that git doesn't ignore.
        let untracked = await run(["ls-files", "--others", "--exclude-standard", "-z"], in: source)
        for path in untracked.output.split(separator: "\0").map(String.init) where !path.isEmpty {
            let from = source.appendingPathComponent(path)
            let to = copy.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: from, to: to)
        }
        return .success(copy)
    }

    struct RehearsalCopyError: Error { let text: String; init(_ text: String) { self.text = text } }

    /// Removes a rehearsal's copy and its branch. Nothing in it is kept.
    nonisolated static func removeRehearsalCopy(_ copy: URL, runID: String, from root: URL) async {
        _ = await run(["worktree", "remove", "--force", copy.path], in: root)
        try? FileManager.default.removeItem(at: copy)
        _ = await run(["worktree", "prune"], in: root)
        _ = await run(["branch", "-D", Rehearsal.branch(forRun: runID)], in: root)
    }

    /// Removes the copies and branches of rehearsals a crash or a quit left behind, in the repository at `root`.
    nonisolated static func sweepRehearsalCopies(at root: URL) async {
        guard let info = await info(at: root) else { return }
        for worktree in info.worktrees where worktree.branch.map(Rehearsal.isRehearsalBranch) == true {
            _ = await run(["worktree", "remove", "--force", worktree.path], in: root)
        }
        _ = await run(["worktree", "prune"], in: root)
        for branch in info.branches where Rehearsal.isRehearsalBranch(branch) {
            _ = await run(["branch", "-D", branch], in: root)
        }
    }
```

Check `Workplace.parseWorktrees`'s element type for the names of its `path` and `branch` fields (`grep -n "struct Worktree" -A8 Core/Sources/QueenBeeCore/Workplace.swift`), and use those names. If `branch` there is `refs/heads/…`, strip that prefix first.

`git stash create` leaves the source's working tree and stash list alone. It only writes a commit object, so it is safe while the person keeps working.

- [ ] **Step 2: Build.**

Run: `./scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` or the script's own success line, and exit code 0.

- [ ] **Step 3: Check by hand on a scratch repo.** In the scratchpad, make a git repo with one commit, one changed tracked file and one untracked file. Call nothing from the app: run the same git commands in the shell (`worktree add -b`, `stash create`, `stash apply`, `ls-files --others --exclude-standard`). Check that the copy has both changes and that the source's `git status` and `git stash list` are unchanged.

- [ ] **Step 4: Commit.**

```bash
./scripts/check-clean.sh
git add App/Sessions/Git.swift
git commit -m "Rehearsal mode: make, remove and sweep a rehearsal's throwaway copy"
```

---

### Task 7: The rehearsal's state, start and end in `FlowController`

**Files:**
- Modify: `App/FlowController.swift`

This task gets a rehearsal to start and end, with its record marked, its copy made and removed, and the orchestrator not told. Stand-ins come in Task 8, so agents still use their real sessions until then. Don't run a rehearsal of a flow with agents before Task 8 is done.

- [ ] **Step 1: Add the state.** Next to `currentRun` (line 121):

```swift
    /// A rehearsal going on: where it works, and whether this flow made that copy, or a flow above lent it.
    struct RehearsalState {
        var copy: URL?
        var readOnly: Bool
        var ownsCopy: Bool
        /// The copy's own id, which names its folder and branch. Nil when there is no copy of this flow's own.
        var runID: String? = nil
    }
    /// Set from the moment a rehearsal is asked for until it has ended and been tidied away.
    private(set) var rehearsal: RehearsalState?
    var isRehearsing: Bool { rehearsal != nil }
    /// Where this run's scripts run and its End cards save: the rehearsal's copy, or where the flow works.
    private var runRoot: URL { rehearsal?.copy ?? workRoot }
```

- [ ] **Step 2: Store each Script card's last real output in the history.** In `RunHistory` (line 28), add:

```swift
    /// The last real output of each Script card, by card id, for a rehearsal to pass on. Nil in older files.
    var scriptOutputs: [String: String]?
```

Then:
- Add `@ObservationIgnored private var scriptOutputs: [String: String] = [:]` to the controller.
- In `loadHistory()`, read it with `scriptOutputs = saved.scriptOutputs ?? [:]`.
- In `saveHistory`, write it with `history.scriptOutputs = scriptOutputs.isEmpty ? nil : scriptOutputs`. Follow how `lastRunNumber` is read and written there.
- In `forgetHistory()`, clear it.

In `runScript` (line 2485), after `guard !Task.isCancelled else { return }`:

```swift
            if self.rehearsal == nil { self.scriptOutputs[hold.cardID] = Rehearsal.stored(result.output) }
```

Then change `let folder = workRoot` to `let folder = runRoot`.

- [ ] **Step 3: Save End cards' answers into the copy.** In `save(_:to:card:)` (line 2614), change `let root = workRoot.resolvingSymlinksInPath()` to `let root = runRoot.resolvingSymlinksInPath()`. Then, after the line that appends "saved the answer to", add:

```swift
            if rehearsal != nil { append("\(card): \(Rehearsal.saveLine)") }
```

- [ ] **Step 4: Give `start` a `rehearse` flag, and make the copy before the run begins.** Change the signature at line 1720:

```swift
    func start(command: String? = nil, startCardID: String? = nil, levelsLeft given: Int? = nil, inside: Set<String> = [],
               note: String? = nil, rehearse: Bool = false, lentCopy: RehearsalState? = nil) async -> RunStart {
```

At the very top, after `guard let engine = readyEngine()`:

```swift
        if rehearse, isRunning || isStartingRun { return RunStart(began: false, status: Rehearsal.busyRefusal) }
        // A real run always wins over a rehearsal.
        if !rehearse, rehearsal != nil { await stopRehearsalForRealRun() }
```

After the workplace check (`if !isRunning, let refusal = await prepareWorkplace() …`), add:

```swift
        if rehearse, !isRunning {
            if let refusal = await readyRehearsal(lent: lentCopy) { return RunStart(began: false, status: refusal) }
        }
```

In the `if let id = output.runID, !isRunning` block, after `clearForRun()`:

```swift
            if rehearsal != nil {
                let scripts = flow.cards.filter { $0.kind == .script && $0.runsInRehearsals == true }.map(\.name)
                append(Rehearsal.firstLine(readOnly: rehearsal?.readOnly ?? true, scriptsThatRun: scripts), kept: true)
            }
```

After the `absorb(output, sender: nil)` call, if the run didn't begin, tidy the rehearsal away:

```swift
        if rehearse, !began { await endRehearsal() }
```

Make the same `!rehearse, rehearsal != nil` check at the top of `start(from:message:…)` (line 1761), before its first `guard !isRunning`:

```swift
        if rehearsal != nil { await stopRehearsalForRealRun() }
```

- [ ] **Step 5: Add `readyRehearsal`, `stopRehearsalForRealRun` and `endRehearsal`.** Put them under a new `// MARK: Rehearsals`:

```swift
    // MARK: Rehearsals

    /// Gets a rehearsal's place ready: a copy of where the flow works, a copy a flow above lent this one, or no copy
    /// outside git. Nil when ready, else why not.
    private func readyRehearsal(lent: RehearsalState?) async -> String? {
        if let lent {
            rehearsal = RehearsalState(copy: lent.copy, readOnly: lent.readOnly, ownsCopy: false)
            return nil
        }
        guard git != nil else {
            rehearsal = RehearsalState(copy: nil, readOnly: true, ownsCopy: false)
            return nil
        }
        let id = UUID().uuidString.lowercased()
        let folder = services.supportDirectory.appendingPathComponent("rehearsals", isDirectory: true)
        switch await Git.makeRehearsalCopy(of: workRoot, runID: id, in: folder) {
        case .success(let copy):
            rehearsal = RehearsalState(copy: copy, readOnly: false, ownsCopy: true, runID: id)
            return nil
        case .failure(let error):
            return refuse("The rehearsal couldn't make its copy of the project: \(error.text)")
        }
    }

    /// A real run was asked for while this flow rehearses: the rehearsal stops, and says why.
    private func stopRehearsalForRealRun() async {
        guard rehearsal != nil else { return }
        append(Rehearsal.stoppedForRealRun, kept: true)
        if isRunning { await stop() }
        await endRehearsal()
    }

    /// Tidies a rehearsal away once it has ended: its stand-ins quit, and its copy goes once their cost is read.
    private func endRehearsal() async {
        guard let ended = rehearsal else { return }
        rehearsal = nil
        retireStandIns()          // Task 8
        guard ended.ownsCopy, let copy = ended.copy else { return }
        let copyID = copy.lastPathComponent
        let root = project.root
        Task.detached {
            // Long enough for `recordUsage`, which reads the stand-ins' transcripts 4 seconds after the run.
            try? await Task.sleep(for: .seconds(8))
            await Git.removeRehearsalCopy(copy, runID: copyID, from: root)
            await MainActor.run { Transcripts.removeFolder(for: copy.path) }   // Task 8, Step 7
        }
    }
```

`makeRehearsalCopy` names the copy's folder with its own id, so `copy.lastPathComponent` is the branch's id too. For now, until Task 8 adds them, make `retireStandIns()` an empty private function and leave out the `Transcripts.removeFolder` line.

- [ ] **Step 6: Mark the record and end the rehearsal.** In `finishRecord` (line 609), pass `rehearsal: rehearsal != nil ? true : nil` to `RunRecord(…)`.

In `absorb`, in the `if output.finished` block, right after `notifyOrchestrator(of: output)`:

```swift
            if rehearsal != nil { Task { await self.endRehearsal() } }
```

In `notifyOrchestrator(of:)`, change the first guard to:

```swift
        guard flow.notifyOrchestrator, rehearsal == nil, orchestrator.isLive else { return }
```

In the `Notifier.post` at the end of the `finished` block, start the title with "Rehearsal: " when `rehearsal != nil`:

```swift
            let prefix = rehearsal != nil ? "Rehearsal: " : ""
            Notifier.post(title: "\(prefix)\(flow.name) \(failed ? …)", …)
```

Keep the existing text after the prefix.

- [ ] **Step 7: Schedules don't skip, so a real run wins.** In `fire(_:because:changed:)` (line 369), change `if isRunning {` to `if isRunning, rehearsal == nil {`.

- [ ] **Step 8: Sweep leftovers when a flow opens.** In `open()` (line 675), at the end:

```swift
        if rehearsal == nil { Task.detached { [root = project.root] in await Git.sweepRehearsalCopies(at: root) } }
```

Also delete any folder left under `services.supportDirectory/rehearsals` that is older than a day. A crash leaves the folder even after git forgets it.

- [ ] **Step 9: Put the real `rehearseFlow` back** in place of the Task 4 stub:

```swift
    func rehearseFlow(command: String?) async throws -> String {
        let started = await start(command: command, rehearse: true)
        guard started.began else { throw FlowError.invalid(started.status) }
        return "Rehearsal started. " + started.status
    }
```

- [ ] **Step 10: Build and commit.**

```bash
./scripts/build.sh && ./scripts/check-clean.sh
git add App/FlowController.swift
git commit -m "Rehearsal mode: a rehearsal starts in its copy, is marked in its record, and is tidied away"
```

---

### Task 8: Stand-ins

**Files:**
- Modify: `App/Sessions/ClaudeLauncher.swift`
- Modify: `App/FlowController.swift`
- Modify: `Core/Sources/QueenBeeCore/Transcripts.swift` (`removeFolder`)

- [ ] **Step 1: A launch spec for a stand-in.** In `ClaudeLauncher`, after `agent(...)`:

```swift
    /// A rehearsal's stand-in for an agent card: a fresh session on Haiku at low effort with the card's instructions,
    /// in `folder`, known to the app by the stand-in's key, never the card's. See `Rehearsal`.
    static func standIn(flow: Flow, card: Card, sessionID: String, folder: String, readOnly: Bool, services: AppServices,
                        environment: ResolvedEnvironment) -> LaunchSpec? {
        guard let claude = environment.claude else { return nil }
        let stand = Rehearsal.standInCard(card)
        var args = common(sessionID: sessionID, directory: folder, name: "\(card.name) (rehearsal)",
                          systemPrompt: agentPrompt(flow: flow, card: stand), services: services)
        args += Rehearsal.standInArguments(permissionMode: card.permissionMode, readOnly: readOnly)
        return spec(claude: claude, args: args, cwd: folder, key: "\(flow.id)/\(Rehearsal.standInKey(for: card.id))",
                    sessionID: sessionID, services: services, environment: environment)
    }
```

Because `sessionID` is new, `common`'s `sessionArguments` gives `--session-id`, never `--resume`.

- [ ] **Step 2: Hold stand-ins in the controller.** Next to `sessions` (line 153):

```swift
    /// Each agent card's stand-in in the rehearsal going on, by card id. Never saved, and never in `Card.sessionID`.
    private(set) var standIns: [String: TerminalSession] = [:]
    /// The session ids of stand-ins that have quit, by stand-in key, until the rehearsal's cost has been read.
    @ObservationIgnored private var retiredStandIns: [String: String] = [:]

    /// The session a run's hand-offs for a card go to: its stand-in in a rehearsal, else its own.
    private func runSession(forCard id: String) -> TerminalSession {
        rehearsal != nil ? standIn(forCard: id) : session(forCard: id)
    }

    /// What a card shows: its stand-in while it has one, else its own session.
    func shownSession(forCard id: String) -> TerminalSession { standIns[id] ?? session(forCard: id) }

    private func standIn(forCard id: String) -> TerminalSession {
        if let existing = standIns[id] { return existing }
        let key = Rehearsal.standInKey(for: id)
        let made = TerminalSession(key: "\(flow.id)/\(key)")
        made.onExit = { [weak self] _ in self?.sessionExited(key) }
        standIns[id] = made
        return made
    }

    private func startStandIn(forCard id: String) {
        guard let environment = services.environment, let state = rehearsal, let card = flow.card(id), card.kind == .agent else { return }
        let sessionID = UUID().uuidString.lowercased()
        let folder = state.copy.map { Rehearsal.folder(forCard: card.cwd, projectRoot: project.root, copy: $0) }
            ?? ClaudeLauncher.folder(for: card, projectRoot: project.root, workRoot: workRoot)
        services.noteBorn(session: sessionID, instructions: ClaudeLauncher.agentPrompt(flow: flow, card: Rehearsal.standInCard(card)))
        guard let spec = ClaudeLauncher.standIn(flow: flow, card: card, sessionID: sessionID, folder: folder,
                                                readOnly: state.readOnly, services: services, environment: environment) else {
            banner = services.problem
            return
        }
        standIn(forCard: id).start(spec, settings: AgentSettings(card))
    }

    private func retireStandIns() {
        for (id, session) in standIns {
            if let sid = session.claudeSessionID { retiredStandIns[Rehearsal.standInKey(for: id)] = sid }
            session.terminate()
        }
        standIns.removeAll()
    }
```

Check that `TerminalSession.claudeSessionID` is the id given at launch (`grep -n claudeSessionID App/Sessions/TerminalSession.swift`). If it's only set from a hook, record `spec.sessionID` in a `standInIDs: [String: String]` map when starting, and read that instead.

- [ ] **Step 3: Deliver to stand-ins.** In `absorb` (line 1814), change the delivery loop and the `leftWaiting` loop:

```swift
        for delivery in output.finished ? [] : output.deliveries {
            let target = runSession(forCard: delivery.toCardID)
            if !target.isLive { rehearsal != nil ? startStandIn(forCard: delivery.toCardID) : startSession(forCard: delivery.toCardID) }
            let live = runSession(forCard: delivery.toCardID)
            // … the rest unchanged
        }
        …
        for id in output.leftWaiting {
            (rehearsal != nil ? standIns[id] : sessions[id])?.interrupt()
            …
        }
```

In `handleSent` (line 1621), change `session(forCard: delivery.toCardID).send(delivery.text)` to `runSession(forCard: delivery.toCardID).send(delivery.text)`.

- [ ] **Step 4: Tell stand-ins' hooks from cards' own.** In `handleHook` (line 1509):

```swift
    func handleHook(from who: String, payload: JSONValue) -> JSONValue {
        let (cardID, isStandIn) = Rehearsal.cardID(ofKey: who)
        guard let session = isStandIn ? standIns[cardID] : sessions[who] else { return [:] }
        let context = payload["hook_event_name"]?.stringValue == "SessionStart" ? startContext(for: cardID, session: session, payload: payload) : [:]
        // In a rehearsal only stand-ins work for the run; outside one, only cards' own sessions.
        applyHook(from: cardID, key: who, session: session, payload: payload, forRun: isStandIn == (rehearsal != nil))
        return context
    }
```

Change `applyHook`'s signature to `applyHook(from who: String, key: String, session: TerminalSession, payload: JSONValue, forRun: Bool)`. Inside it:
- Make the "needs you" notification title start with "Rehearsal: " when `key != who`.
- In the `Stop`/`StopFailure` usage refresh, call `refreshUsage(key)`.
- Right after `guard who != Self.orchestratorKey else { return }`, add `guard forRun else { return }`. A card's own session going on in a rehearsal then never feeds the run, and its state still updates above that line.

In `handleRoute` (line 1608), at the top:

```swift
        let (cardID, isStandIn) = Rehearsal.cardID(ofKey: who)
        guard isStandIn == (rehearsal != nil) else { return [] }
        let who = cardID
```

Then change `sessions[who]?.lastReply = answer` to `(isStandIn ? standIns[who] : sessions[who])?.lastReply = answer`.

In `sessionExited(_:)` (line 1469):

```swift
    private func sessionExited(_ key: String) {
        guard key != Self.orchestratorKey else { return }
        let (id, isStandIn) = Rehearsal.cardID(ofKey: key)
        guard isStandIn == (rehearsal != nil) else { return }
        agentStopped(id, reason: "its session ended")
    }
```

Find where `AppServices` calls `handleRoute`, `handleSent` and `judgeSend` (`grep -n "handleRoute\|handleSent\|judgeSend" App/AppServices.swift`). They pass `parts[1]`, which is now the stand-in key, so each entry point translates as above. Do `handleSent`: translate `who` at its top the same way, and return early when it doesn't match.

- [ ] **Step 5: Messages between stand-ins.** In `judgeSend` (line 1645), at the top:

```swift
        let (sender, isStandIn) = Rehearsal.cardID(ofKey: who)
        if isStandIn, address.hasPrefix(ClaudeLauncher.orchestratorName(for: flow).lowercased()) {
            return SendVerdict(refusal: Rehearsal.noOrchestrator)
        }
        let who = sender
```

Move `let address = to.lowercased()` above these lines. Change the last `return` to give the stand-in's session:

```swift
        let sid = isStandIn ? standIns[target.id]?.claudeSessionID : target.sessionID
        return SendVerdict(inFlow: who != Self.orchestratorKey, sessionID: sid)
```

A stand-in that isn't started yet has no id. In that case, `startStandIn(forCard: target.id)` first, and return `SendVerdict(refusal: "\(target.name) is still starting in the rehearsal. Try again in a moment.")`.

- [ ] **Step 6: Count stand-ins' cost.** In `refreshUsage` (line 505), after the cards loop:

```swift
        for (id, session) in standIns where only == nil || only == Rehearsal.standInKey(for: id) {
            if let sid = session.claudeSessionID { ids[Rehearsal.standInKey(for: id)] = sid }
        }
        for (key, sid) in retiredStandIns where only == nil || only == key { ids[key] = sid }
```

In `recordUsage(forRun:)`, fold each stand-in key into its card when building `shares`, then forget them:

```swift
            for (key, now) in self.usage where key != Self.orchestratorKey {
                let share = now.since(before[key] ?? Usage())
                guard !share.isZero else { continue }
                let card = Rehearsal.cardID(ofKey: key).cardID
                shares[card] = (shares[card] ?? Usage()) + share
            }
            …
            self.runs[index].usage = shares
            // A rehearsal's stand-ins are gone: their keys go once their cost is the run's.
            for key in self.retiredStandIns.keys { self.usage[key] = nil }
            self.retiredStandIns.removeAll()
```

Before you touch anything else, check `totalUsage` and the cost panel. `usage` keyed by a stand-in key must not show as a card. Find `usage.values` and `usage[` (`grep -n "usage\[" App/FlowController.swift App/Views/*.swift`). Anywhere that maps keys to cards should skip stand-in keys, which `flow.card(key) == nil` already does.

- [ ] **Step 7: Remove a copy's transcripts.** In `Core/Sources/QueenBeeCore/Transcripts.swift`, add:

```swift
    /// Deletes Claude Code's folder of transcripts for sessions that worked in `directory`, as for a rehearsal's
    /// copy once it is gone. Only the folder named exactly for that directory.
    public static func removeFolder(for directory: String, projects: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")) {
        guard let name = exactFolderName(for: directory) else { return }
        try? FileManager.default.removeItem(at: projects.appendingPathComponent(name, isDirectory: true))
    }
```

Add a test in `TranscriptsTests` that makes a temporary `projects` folder holding the folder named for `/tmp/x` and another one, calls `removeFolder(for: "/tmp/x", projects:)`, and checks that only the first is gone. Put back the `Transcripts.removeFolder` line in `endRehearsal`.

- [ ] **Step 8: Show the stand-in on its card.** In `App/Canvas/AgentCardView.swift`, find where the terminal view is made from `controller.session(forCard:)` and use `controller.shownSession(forCard:)` instead. Above the terminal, when `controller.standIns[card.id] != nil`, show a one-line strip that says "Rehearsing on Haiku". Build it from the design system:
- the `StatusPill` used for "Kept" in `PlaceViews.swift`, with the same tone
- `DS.Space` padding
- `.textRole` for the text

The card's other controls (Restart, settings) act on the real session as before.

- [ ] **Step 9: Build, run the unit tests, and commit.**

```bash
cd Core && swift test && cd .. && ./scripts/build.sh && ./scripts/check-clean.sh
git add App Core
git commit -m "Rehearsal mode: stand-ins take the agents' hand-offs in a rehearsal, and their cost is counted"
```

- [ ] **Step 10: First real look.** Ask Keith first, because this starts real Haiku sessions on his account.
  1. Open the Debug app with a mock flow: Start, then one agent, then End.
  2. Call `controller.rehearseFlow` through the harness (Task 11), or temporarily from the Run menu (Task 10).
  3. Check that the card shows "Rehearsing on Haiku" and the stand-in's terminal.
  4. Check that the agent's real conversation has no new message.
  5. Check that the record says rehearsal, and that the copy folder under `QueenBee-Dev/rehearsals` is gone after about 10 seconds.

---

### Task 9: Script, Delay and Approval cards in a rehearsal; sub-flows

**Files:**
- Modify: `App/FlowController.swift` (`take(_ hold:)` at line 1959; `runInnerFlow` at line 2084; `runToEnd` at line 2405)

- [ ] **Step 1: Scripts and Delays.** In `take(_ hold:)`, before the `if hold.kind == .flow` block:

```swift
        if let state = rehearsal, hold.kind == .script {
            let step = Rehearsal.scriptStep(for: card, lastOutput: scriptOutputs[card.id], readOnly: state.readOnly)
            append(Rehearsal.scriptLine(cardName: card.name, step: step))
            if case .passOn(let text, _) = step {
                holds.append(pending)
                return resolve(pending.id, port: "pass", text: text)
            }
        }
        if rehearsal != nil, hold.kind == .delay {
            append(Rehearsal.delayLine(cardName: card.name, minutes: Int(DelayTime.wait(for: card).components.seconds / 60)))
            holds.append(pending)
            return resolve(pending.id, port: "out", text: nil)
        }
```

`.run` falls through to the usual path, so the allow question and its time limit still apply. `runScript` already uses `runRoot`.

- [ ] **Step 2: Approvals say it's a rehearsal.** In the same function, change the approval notification's title:

```swift
            Notifier.post(title: "\(rehearsal != nil ? "Rehearsal: " : "")\(card.name) needs your approval", …)
```

- [ ] **Step 3: Sub-flows rehearse, in the same copy.** Give `runToEnd` a `rehearse` parameter:

```swift
    func runToEnd(command: String, levelsLeft: Int, inside: Set<String>, forHold holdID: String? = nil,
                  rehearse: RehearsalState? = nil) async -> (finished: Bool, text: String) {
        // A real run always wins over a rehearsal of this flow.
        if rehearse == nil, rehearsal != nil { await stopRehearsalForRealRun() }
        guard await subflowTurns.take(whenFree: { !self.isRunning && !self.isStartingRun }) else { return (false, "The run was stopped.") }
        defer { subflowTurns.release() }
        let started = await start(command: command, levelsLeft: levelsLeft, inside: inside, rehearse: rehearse != nil, lentCopy: rehearse)
        …
```

In `runInnerFlow`, pass `rehearse: rehearsal` to `inner.runToEnd(...)`.

When an inner flow rehearses in the outer flow's copy, its stand-ins must work in its own folder inside that copy. `Rehearsal.folder` already gives that for card folders. The inner flow's own root is the outer copy, because `inheritsWorkplace` flows work where the outer one does. If the inner flow has a workplace of its own, it still uses the lent copy: one copy per rehearsal, as the spec says.

- [ ] **Step 4: Build and commit.**

```bash
./scripts/build.sh && ./scripts/check-clean.sh
git add App/FlowController.swift
git commit -m "Rehearsal mode: scripts skip, delays pass on, approvals say so, and sub-flows rehearse too"
```

---

### Task 10: The Mac's window

**Files:**
- Modify: `App/Views/FlowHeader.swift` (the Run menu, which has "Run from")
- Modify: `App/Views/RunProgressViews.swift` (the run pill)
- Modify: `App/Views/PlaceViews.swift` (Runs page: row, peek, keep button, compare menu)
- Modify: `App/Views/SidePanel.swift` (RunPicker label)
- Modify: `App/Views/RunCompareView.swift`, if it lists runs to pick

Every colour, size and spacing comes from `QueenBeeDesign`. Copy the "Kept" pill and bookmark row from Keep a run (commit 9435f8e) for the matching rehearsal pieces.

- [ ] **Step 1: Rehearse in the Run menu.** Find the menu that holds "Run from" (`grep -n "Run from" App/Views/FlowHeader.swift`). Add a **Rehearse** item, and disable it while `controller.isRunning || controller.isStartingRun || !controller.canRun`. Give it the help text "Run the whole flow on Haiku at low effort, by throwaway copies of its agents, in a throwaway copy of the project". It calls:

```swift
                Task { _ = await controller.start(rehearse: true) }
```

- [ ] **Step 2: Run during a rehearsal asks first.** Where the Run button calls `controller.run(...)`, check `controller.isRehearsing` first. If it's true, show an alert from the same component the app's other confirmations use (`grep -n "confirmationDialog\|NSAlert" App/Views/FlowHeader.swift`):
- Title: "Stop the rehearsal and run for real?"
- Buttons: "Run for Real" and "Cancel"

On "Run for Real", call `run` as usual. `start` stops the rehearsal.

- [ ] **Step 3: The run pill says Rehearsal.** In `RunProgressViews.swift`, where the pill's label is built, prefix "Rehearsal · " when `controller.isRehearsing`.

- [ ] **Step 4: Runs page.** In `PlaceViews.swift`:
- Next to the `bookmark.fill` mark for kept runs, show a `theatermasks` symbol with help "A rehearsal, on Haiku" for `run.isRehearsal`. Use `.dsIcon` sizing.
- In `RunPeek`, show a "Rehearsal" `StatusPill` for rehearsals.
- Hide `keepButton` for rehearsals.
- In the compare menu, leave out rehearsals: `runs.filter { !$0.isRehearsal }`.

In `SidePanel.swift`'s RunPicker label, add " · Rehearsal" as " · Kept" is added.

- [ ] **Step 5: Build, open, look.**

```bash
./scripts/build.sh && open build/Build/Products/Debug/QueenBee.app
```

With a mock flow, check that Rehearse is in the menu, the pill reads "Rehearsal ·", and the Runs page shows the mark and no Keep for a rehearsal. Ask Keith before starting one, as it costs a little.

- [ ] **Step 6: Commit.**

```bash
./scripts/check-clean.sh
git add App/Views
git commit -m "Rehearsal mode: Rehearse in the Run menu, and rehearsals marked in the window"
```

---

### Task 11: The Mac's end of the device link, and the test harness

**Files:**
- Modify: `App/Remote/RemoteHost.swift` (welcome features, where `RemoteFeature.keepRuns` is added; run state, where `RemoteRunState` is built)
- Modify: `App/Remote/RemoteCommands.swift` (a `.rehearse` handler beside `.runFromStart`)
- Modify: `App/Testing/TestHarness.swift` (beside `case "keep":` at line 368, and the runs state)
- Modify: `Tools/RemoteCheck/main.swift`

- [ ] **Step 1: Announce it and say so in the run state.** Add `RemoteFeature.rehearsals` to the welcome's features, and set `rehearsal: controller.isRehearsing ? true : nil` where `RemoteRunState` is made.

- [ ] **Step 2: Handle `.rehearse`.** Copy the `.runFromStart` handler, and call:

```swift
            let started = await controller.start(startCardID: startCardID, note: "\(device) started a rehearsal", rehearse: true)
            return started.began ? .ok : .refused(started.status)
```

Use whatever reply and refusal shapes `.runFromStart` uses.

- [ ] **Step 3: Harness ops.**

```swift
        case "rehearse":
            // Rehearse in the Run menu, or the orchestrator's rehearse_flow.
            let started = await controller.start(command: payload["command"]?.stringValue, rehearse: true)
            return ["began": .bool(started.began), "status": .string(started.status)]
```

In the controller's state, add these fields:
- `"rehearsing": .bool(controller.isRehearsing)`
- `"standIns": .array(controller.standIns.keys.sorted().map(JSONValue.string))`
- `"copy": controller.rehearsalCopyPath.map(JSONValue.string) ?? .null`. Add the `rehearsalCopyPath: String?` getter to `FlowController`, returning `rehearsal?.copy?.path`.

On each run in the runs state, add `"rehearsal": .bool(run.isRehearsal)`.

In `scriptOutputs` support, add `"scriptOutputs": .object(...)`, so a test can check a real run stored one.

- [ ] **Step 4: RemoteCheck.**

```swift
        case "rehearse": return .rehearse(flowID: flow, startCardID: optionalText("start"))
```

If there is no `optionalText` helper, use the one `runFromStart` uses.

- [ ] **Step 5: Build and commit.**

```bash
./scripts/build.sh && ./scripts/check-clean.sh
git add App Tools
git commit -m "Rehearsal mode: a device can rehearse, and the test harness can drive and read a rehearsal"
```

---

### Task 12: The iPad and iPhone app

**Files:**
- Modify: `Mobile/Model/CardTasks.swift` (the pattern is `canKeepRuns`, `keepRunCommand`)
- Modify: the run control (`grep -rn "runFromStart\|\.run(flowID" Mobile`)
- Modify: `Mobile/Model/PanelContent.swift` (`RunRow`), `Mobile/Views/RunPages.swift`
- Modify: `Mobile/Link/DebugCannedRun.swift`, `Mobile/Link/DebugParity.swift`, `Mobile/Link/DebugLaunch.swift`

- [ ] **Step 1: The command.** In `CardTasks.swift`:

```swift
    var canRehearse: Bool { canAct && mirror.macRehearses && !(mirror.run?.isRunning ?? false) }
    func rehearseCommand(startCardID: String?) -> RemoteCommand? {
        guard canRehearse, let flowID = openFlowID else { return nil }
        return .rehearse(flowID: flowID, startCardID: startCardID)
    }
```

Fit the names (`canAct`, `mirror`, `openFlowID`) to what `keepRunCommand` uses beside it.

- [ ] **Step 2: The control.** Wherever Run is offered, add **Rehearse** beside it, in the same menu or as a second item. Show it only when `canRehearse`. While a rehearsal runs (`mirror.run?.rehearsal == true`), say "Rehearsal" on the run strip, as the Mac's pill does.

- [ ] **Step 3: Rows.** In `RunRow`, add `isRehearsal`, read from the record. In `RunPages.swift`:
- On the row's bottom line, before "Kept", show the `theatermasks` icon and the word "Rehearsal".
- Leave out "Keep for Good" for rehearsals.
- Add ", rehearsal" to the spoken label.

- [ ] **Step 4: The canned Mac.** In `DebugCannedRun`:
- Answer `.rehearse` by starting the canned run with `rehearsal: true` on its record, and `RemoteRunState.rehearsal = true` while it goes.
- Include `RemoteFeature.rehearsals` in its features.

- [ ] **Step 5: Parity step and launch state.**
- In `DebugParity`, add a step `rehearse[:<start card id>]` that sends `rehearseCommand`.
- In `DebugLaunch`, add `rehearsal` to each panel run's state, and add `rehearsing` to the panel.

- [ ] **Step 6: Build and commit.**

```bash
./scripts/build-mobile.sh && ./scripts/check-clean.sh
git add Mobile
git commit -m "Rehearsal mode: Rehearse from the iPad and iPhone, and rehearsals marked there"
```

---

### Task 13: End-to-end checks

**Files:**
- Modify: `scripts/e2e.py` (scenarios `gates`, `remote`, `parity`)

Ask Keith before running any of them.

- [ ] **Step 1: gates.** Use a small flow: Start → Agent "Writer" → Script "Echo" (`echo hi`) → Delay "Wait" (5 minutes) → End. Find how `gates` builds its flows and copy that. Then add these checks, using the harness ops from Task 11:
  1. Run once for real, and check `scriptOutputs["<Echo id>"]` contains "hi".
  2. Note the Writer card's `sessionID`, and the length of its transcript (`~/.claude/projects/*/<id>.jsonl`).
  3. `rehearse`: wait for the run to end, then check:
     - the latest run has `rehearsal: true`
     - the log has the first line, Echo's "passed on its last real output", and Wait's "passed the message on at once"
     - the run took under a minute, so the Delay didn't wait
  4. Check that the Writer's transcript length is unchanged, so its real conversation was untouched.
  5. Within 15 seconds of the end, check that `copy` is null, the folder under `QB_SUPPORT_DIR/rehearsals` is gone, and `git branch --list 'queenbee-rehearsal-*'` in the project is empty.
  6. `keep` on the rehearsal returns the "can't be kept" problem.
  7. Rehearse, then at once run for real. Check that the log says "Stopped the rehearsal for a real run", and that the next record is a real run.
  8. Rehearse 6 times quickly, using a flow of Start → End to save cost. Check that only 5 rehearsals remain, and that the real runs are all still there.

- [ ] **Step 2: remote.** With RemoteCheck:
  1. `rehearse`. Check it starts, and that the run state's `rehearsal` is true while it goes.
  2. `patchCard` with `runsInRehearsals: true`. Check it's refused with the "Only the person" text.

- [ ] **Step 3: parity.** On the canned Mac:
  1. Step `rehearse`. Check that the panel shows a run with `rehearsal: true` and a spoken label containing "rehearsal", and that its row has no Keep action.
  2. Take a screenshot named `parity-18-rehearsal`.

- [ ] **Step 4: Run them, with Keith's go-ahead.** Run them one simulator at a time, and quit the test copies afterwards.

```bash
./scripts/build.sh && ./scripts/e2e.py gates remote
./scripts/build-mobile.sh && ./scripts/e2e.py parity panels
QB_E2E_SIMULATOR="iPhone 17" ./scripts/e2e.py parity panels
```

Expected: 0 failed in each.

- [ ] **Step 5: Commit.**

```bash
./scripts/check-clean.sh
git add scripts/e2e.py
git commit -m "Rehearsal mode: end-to-end checks on the Mac and devices"
```

---

### Task 14: Words

**Files:**
- Modify: `CHANGELOG.md` (Unreleased → Added)
- Modify: `SECURITY.md`
- Modify: `docs/superpowers/specs/2026-11-09-rehearsal-mode-design.md`

- [ ] **Step 1: CHANGELOG.** Under Unreleased → Added:

```markdown
- Rehearse a flow: Rehearse, in the Run menu and on the iPad and iPhone, runs the whole flow on Haiku at low effort, by throwaway copies of its agents in a throwaway copy of the project. Your files and your agents' conversations are left alone. Script cards pass on their last real output unless you let them run, Delays pass on at once, and Approvals ask as usual. Rehearsals are kept apart from real runs.
```

- [ ] **Step 2: SECURITY.md.** In the list of what a flow file or the orchestrator can do without asking, add:

```markdown
- A Script card with "Runs in rehearsals" on runs its command in a rehearsal, in the rehearsal's copy of the project, as it would in a real run. Only the person can turn this on, on the Mac. A rehearsal's agents keep their cards' permissions, with no browser, no MCP servers and no `git push`. Other commands they run, such as `curl`, still reach the network.
```

- [ ] **Step 3: The spec.** Change these lines in the spec:
- Status: "Built", once merged.
- "The engine is told a run is a rehearsal when it starts" becomes "The engine doesn't know: a rehearsal is the app's, marked on its record".
- The copy's location: already changed to the project's `.queenbee/rehearsals` folder, with the fix that moved it there.

- [ ] **Step 4: Final checks and commit.**

```bash
cd Core && swift test && cd .. && ./scripts/build.sh && ./scripts/build-mobile.sh && ./scripts/check-clean.sh
git add CHANGELOG.md SECURITY.md docs/superpowers/specs/2026-11-09-rehearsal-mode-design.md CAPABILITIES.md
git commit -m "Rehearsal mode: changelog, security notes and the spec brought up to date"
```

---

## Self-review against the spec

| Spec item | Task |
|---|---|
| Rehearse beside Run on the Mac and devices; the orchestrator's tool; never from schedules or links | 10, 12, 4 (schedules and links call `start` without `rehearse`) |
| Run pill "Rehearsal"; card strip and stand-in terminal; back afterwards | 10.3, 8.8 |
| Runs pill; own 5; can't keep; not in Compare | 1, 10.4, 12.3 |
| First log line | 2, 7.4 |
| Agents as stand-ins: Haiku, low, own instructions and mode, in copy, no browser, no MCP, no push | 2, 8 |
| Script skipped / last output / note / runs in copy when allowed | 2, 7.2, 9.1 |
| Approval asks, marked | 9.2 |
| Delay passes at once, log line | 2, 9.1 |
| Flow card rehearses, same copy | 9.3 |
| End saves into copy, log says so | 7.3 |
| No orchestrator notice; spending limit as usual | 7.6, 8.6 |
| Copy of the workplace with uncommitted changes; removed; swept on launch; read-only outside git | 6, 7.5, 7.8, 8 |
| Real run wins: schedules, links, devices, Flow cards; Mac asks first; Rehearse refused during a run | 7.4, 7.7, 9.3, 10.2 |
| Card setting, Mac only, `SECURITY.md` | 3, 14 |
| Wire: feature, command, run state, fingerprint, no version bump | 5, 11 |
| Tests: unit, e2e, real app | 1–5, 8.7, 13, 8.10, 10.5 |
