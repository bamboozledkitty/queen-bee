import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct RemoteOverviewTests {
    private static let at = Date(timeIntervalSince1970: 10_000)

    private func run(_ id: String?, flow: String = "f", number: Int = 1, _ outcome: RunRecord.Outcome? = .finished, ago: Double = 0) -> RemoteRunEntry {
        RemoteRunEntry(flowID: flow, flowName: "Flow \(flow)", projectID: "p", projectName: "P", runID: id, number: number, outcome: outcome,
                       summary: outcome?.rawValue ?? "Running", handOffs: 0, started: id == nil ? nil : Self.at.addingTimeInterval(-ago))
    }

    private func schedule(_ card: String, armed: Bool) -> RemoteScheduleEntry {
        RemoteScheduleEntry(flowID: "f", flowName: "Flow", projectID: "p", projectName: "P", cardID: card, cardName: "Start",
                            summary: "Every day at 09:00", isFile: false, armed: armed, next: armed ? Self.at : nil)
    }

    // MARK: Runs and schedules

    @Test func aFlowCopiedIntoAnotherProjectKeepsRowsOfItsOwn() {
        // A copied flow keeps its id and its cards' ids, so only the project tells the two apart.
        var there = run(nil), elsewhere = run(nil)
        elsewhere.projectID = "q"
        #expect(there.id != elsewhere.id)
        there.runID = "r"; elsewhere.runID = "r"
        #expect(there.id != elsewhere.id)
        var start = schedule("s", armed: true), copied = schedule("s", armed: true)
        copied.projectID = "q"
        #expect(start.id != copied.id)
        start.armed = false
        #expect(start.id == schedule("s", armed: true).id)
    }

    @Test func runsAreGroupedAsTheMacGroupsThem() {
        let overview = RemoteOverview(runs: [run("a", ago: 30), run("b", .failed, ago: 10), run(nil, flow: "g", number: 3, nil),
                                             run("c", .stopped, ago: 20), run("d", ago: 5)])
        let groups = overview.runGroups
        #expect(groups.running.map(\.flowID) == ["g"])
        // Stopped and failed together, newest first; then the ones that finished, newest first.
        #expect(groups.stopped.map(\.runID) == ["b", "c"])
        #expect(groups.done.map(\.runID) == ["d", "a"])
        #expect(!groups.isEmpty)
        #expect(RemoteOverview().runGroups.isEmpty)
    }

    @Test func schedulesAreGroupedOnThenOff() {
        let overview = RemoteOverview(schedules: [schedule("a", armed: false), schedule("b", armed: true), schedule("c", armed: false)])
        let groups = overview.scheduleGroups
        #expect(groups.on.map(\.cardID) == ["b"])
        #expect(groups.off.map(\.cardID) == ["a", "c"])
    }

    @Test func theListIsCappedAndKeepsRunsGoingNow() {
        let runs = (0 ..< RemoteOverview.mostRuns + 20).map { run("r\($0)", ago: Double($0)) } + [run(nil, flow: "g", number: 2, nil)]
        let made = RemoteOverview.made(runs: runs, schedules: (0 ..< 150).map { schedule("s\($0)", armed: false) })
        #expect(made.runs.count == RemoteOverview.mostRuns + 1)
        #expect(made.runs.first?.runID == nil)
        // The newest are kept, and the oldest left out.
        #expect(made.runs.contains { $0.runID == "r0" })
        #expect(!made.runs.contains { $0.runID == "r\(RemoteOverview.mostRuns + 19)" })
        #expect(made.schedules.count == RemoteOverview.mostSchedules)
    }

    @Test func longNamesAreCut() {
        var entry = schedule("a", armed: true)
        entry.cardName = String(repeating: "x", count: 500)
        entry.summary = "When " + String(repeating: "/long", count: 100) + " changes"
        let made = RemoteOverview.made(runs: [], schedules: [entry])
        #expect(made.schedules[0].cardName.count == RemoteOverview.longest + 1)
        #expect(made.schedules[0].summary.count <= RemoteOverview.longest + 1)
    }

    @Test func aScheduleCarriesNoCommand() throws {
        // What a schedule runs is read in the flow. The list has no field that could hold it.
        let json = try #require(try JSONSerialization.jsonObject(with: Remote.encode(schedule("a", armed: true))) as? [String: Any])
        #expect(!json.keys.contains("command"))
    }

    // MARK: The wire

    @Test func theOverviewSurvivesTheTrip() throws {
        let message = HostMessage.overview(WireSamples.overview)
        #expect(try Remote.read(fromMac: Remote.encode(message)) == .message(message))
    }

    @Test func aRunStateFromBeforeTheBranchChipStillReads() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: Remote.encode(WireSamples.run)) as? [String: Any])
        #expect(json["workplace"] as? String == "main · worktree")
        json["workplace"] = nil
        let old = try Remote.decode(RemoteRunState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.workplace == nil)
        #expect(old.isRunning)
    }

    @Test func aMacFromBeforeSendsNoOverviewAndTheMirrorHasNone() {
        var mirror = RemoteMirror()
        _ = mirror.apply(.welcome(RemoteWelcome(version: Remote.version, macName: "Mac", canControl: true)))
        #expect(!mirror.macHasOverview)
        #expect(mirror.overview == nil)
        _ = mirror.apply(.welcome(RemoteWelcome(version: Remote.version, macName: "Mac", canControl: true, features: [RemoteFeature.overview])))
        #expect(mirror.macHasOverview)
        _ = mirror.apply(.overview(WireSamples.overview))
        #expect(mirror.overview == WireSamples.overview)
        // A new connection starts the lists afresh.
        _ = mirror.apply(.welcome(RemoteWelcome(version: Remote.version, macName: "Mac", canControl: true, features: [RemoteFeature.overview])))
        #expect(mirror.overview == nil)
    }

    // MARK: Restart

    @Test func restartIsAFlowCommandThatIsNotAnEditAndTakesNoTime() {
        let command = RemoteCommand.restartAgents(flowID: "f", which: .all(withOrchestrator: true))
        #expect(command.flowID == "f")
        #expect(!command.isEdit)
        #expect(!command.waitsWithEdits)
        #expect(!command.canTakeTime)
        #expect(command.isAnswered)
        #expect(command.cleaned == command)
        #expect(command.problem == nil)
    }

    @Test func restartingTooManyCardsIsRefusedBeforeItIsSent() {
        let ids = (0 ... Remote.cardLimit).map { "c\($0)" }
        #expect(RemoteCommand.restartAgents(flowID: "f", which: .cards(ids)).problem != nil)
        #expect(RemoteCommand.restartAgents(flowID: "f", which: .cards(Array(ids.dropLast()))).problem == nil)
    }

    @Test func theRestartMenuUsesTheMacsWords() {
        func titles(_ selected: [String], _ awaiting: Int) -> [String] { RestartMenu(selected: selected, awaiting: awaiting).items.map(\.title) }
        #expect(titles([], 0) == ["Restart All Agents", "Restart All Agents Except the Orchestrator", "Restart Selected Agent"])
        #expect(titles(["a"], 0).last == "Restart Selected Agent")
        #expect(titles(["a", "b"], 0).last == "Restart 2 Selected Agents")
        #expect(titles([], 1).last == "Restart the One with New Settings")
        #expect(titles([], 3).last == "Restart the 3 with New Settings")
    }

    @Test func theRestartMenuEnablesWhatCanBeChosen() {
        let none = RestartMenu(selected: [], awaiting: 0)
        #expect(none.items.map(\.isEnabled) == [true, true, false])
        #expect(none.items.allSatisfy { !$0.startsGroup })
        let some = RestartMenu(selected: ["a", "b"], awaiting: 2)
        #expect(some.items.map(\.isEnabled) == [true, true, true, true])
        #expect(some.items[2].which == .cards(["a", "b"]))
        #expect(some.items[3].which == .awaitingNewSettings)
        #expect(some.items[3].startsGroup)
    }

    @Test func aRestartOnlyWarnsOfWhatItWouldCutShort() {
        let agents = [(id: "a", name: "Writer"), (id: "b", name: "Editor")]
        let sessions: [String: SessionState] = ["a": .working, "b": .idle, Remote.orchestratorKey: .needsYou]
        func busy(_ which: RemoteRestart, awaiting: Set<String> = [], orchestrator: Bool = false) -> [String] {
            RestartMenu.busy(which, sessions: sessions, agents: agents, awaiting: awaiting, orchestratorAwaiting: orchestrator)
        }
        #expect(busy(.all(withOrchestrator: true)) == ["Writer", "the orchestrator"])
        #expect(busy(.all(withOrchestrator: false)) == ["Writer"])
        #expect(busy(.cards(["b"])).isEmpty)
        #expect(busy(.cards(["a"])) == ["Writer"])
        #expect(busy(.awaitingNewSettings, awaiting: ["b"]).isEmpty)
        #expect(busy(.awaitingNewSettings, awaiting: ["a"], orchestrator: true) == ["Writer", "the orchestrator"])
    }
}
