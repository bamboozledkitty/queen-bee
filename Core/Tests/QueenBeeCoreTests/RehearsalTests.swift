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

/// The "Runs in rehearsals" setting on a Script card, and who may turn it on.
@Suite struct RunsInRehearsalsTests {
    @Test func aScriptCardCanBeSetToRunInRehearsals() throws {
        var flow = Flow(name: "Test")
        try flow.addCard(kind: .script, name: "Tests")
        var patch = CardPatch()
        patch.runsInRehearsals = true
        #expect(try flow.updateCard("Tests", patch: patch).runsInRehearsals == true)
        patch.runsInRehearsals = false
        // Off is left out of the file.
        #expect(try flow.updateCard("Tests", patch: patch).runsInRehearsals == nil)
    }

    @Test func theOrchestratorCantTurnOnRunsInRehearsals() async throws {
        let host = FakeHost()
        _ = await Tools.call(name: "add_card", arguments: ["kind": "script", "name": "Tests"], host: host)
        let on = await Tools.call(name: "update_card", arguments: ["card": "Tests", "runs_in_rehearsals": true], host: host)
        #expect(on.isError && on.text.contains(Rehearsal.turningOnRefusal))
        #expect(try #require(await host.flow.resolveCard("Tests")).runsInRehearsals == nil)
        // Off is allowed.
        let off = await Tools.call(name: "update_card", arguments: ["card": "Tests", "runs_in_rehearsals": false], host: host)
        #expect(!off.isError)
    }

    @Test func aDeviceCantTurnOnRunsInRehearsals() {
        var on = RemoteCardPatch()
        on.runsInRehearsals = true
        #expect(on.problem == Rehearsal.turningOnRefusal)
        var off = RemoteCardPatch()
        off.runsInRehearsals = false
        #expect(off.problem == nil)
        #expect(off.cardPatch.runsInRehearsals == false)
    }
}

extension Array where Element == String {
    /// Whether `pair` appears side by side, in that order.
    func containsInOrder(_ pair: [String]) -> Bool {
        guard pair.count == 2 else { return false }
        return zip(self, dropFirst()).contains { $0 == pair[0] && $1 == pair[1] }
    }
}
