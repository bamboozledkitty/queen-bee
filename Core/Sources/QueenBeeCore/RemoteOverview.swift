import Foundation

/// What a device shows of the Mac's Runs and Schedules places: one list of runs and one of schedules across every
/// open project. Small on purpose. A run here is a line with its number and how it ended, never its log or its
/// messages, so that a run ending sends a few hundred bytes and not a flow's whole history. Opening the run's flow
/// sends the rest.
///
/// Only a device that says it has `RemoteFeature.overview` is sent this.
public struct RemoteOverview: Codable, Equatable, Sendable {
    /// The most runs listed, newest first, besides the ones going now. Older ones are in each flow's History.
    public static let mostRuns = 100
    /// The most schedules listed.
    public static let mostSchedules = 100
    /// The longest name or summary sent, in characters, so one odd flow can't make the list large.
    public static let longest = 120

    public var runs: [RemoteRunEntry]
    public var schedules: [RemoteScheduleEntry]

    public init(runs: [RemoteRunEntry] = [], schedules: [RemoteScheduleEntry] = []) {
        self.runs = runs; self.schedules = schedules
    }

    /// The list as the Mac sends it: names cut short, the runs that went before the newest `mostRuns` left out, and
    /// the schedules capped. Runs going now are always kept.
    public static func made(runs: [RemoteRunEntry], schedules: [RemoteScheduleEntry]) -> RemoteOverview {
        let live = runs.filter { $0.runID == nil }
        let past = runs.filter { $0.runID != nil }.sorted { ($0.started ?? .distantPast) > ($1.started ?? .distantPast) }
        return RemoteOverview(runs: (live + past.prefix(mostRuns)).map(\.cut), schedules: schedules.prefix(mostSchedules).map(\.cut))
    }

    /// A name cut to `longest` characters, with an ellipsis if anything was cut.
    public static func cut(_ text: String) -> String { text.count > longest ? String(text.prefix(longest)) + "…" : text }

    // MARK: How the Mac's places group them

    /// The runs as the Mac's Runs place groups them: the ones going now, then the ones that stopped or failed, then the
    /// ones that finished. The last two are newest first.
    public struct RunGroups: Equatable, Sendable {
        public var running: [RemoteRunEntry]
        public var stopped: [RemoteRunEntry]
        public var done: [RemoteRunEntry]

        public var isEmpty: Bool { running.isEmpty && stopped.isEmpty && done.isEmpty }
    }

    public var runGroups: RunGroups {
        let past = runs.filter { $0.runID != nil }.sorted { ($0.started ?? .distantPast) > ($1.started ?? .distantPast) }
        return RunGroups(running: runs.filter { $0.runID == nil }, stopped: past.filter { $0.outcome != .finished },
                         done: past.filter { $0.outcome == .finished })
    }

    /// The schedules as the Mac's Schedules place groups them: the ones that are on, then the ones that are off.
    public var scheduleGroups: (on: [RemoteScheduleEntry], off: [RemoteScheduleEntry]) {
        (schedules.filter(\.armed), schedules.filter { !$0.armed })
    }

    /// What the Schedules list says where the Mac's has "Turn on" and "Turn off". Turning a schedule on lets the flow
    /// run with nobody watching, so the list on a device only shows them: a device turns one on or off in its Start card.
    public static let schedulesAreForTheMac = "Turn a schedule on or off in its Start card."
    /// Said in place of the lists when the Mac is a version that doesn't send them.
    public static let macIsOlder = "Update Queen Bee on your Mac to see this here."
}

/// One run in the list across flows.
public struct RemoteRunEntry: Codable, Equatable, Sendable, Identifiable {
    public var flowID: String
    public var flowName: String
    public var projectID: String
    public var projectName: String
    /// The run's id in its flow's history, or nil for the run going now, which is only recorded once it ends.
    public var runID: String?
    /// Its number in its flow, as the Mac shows it. For the run going now, the number it will have.
    public var number: Int?
    /// How it ended. Nil for the run going now.
    public var outcome: RunRecord.Outcome?
    /// How it ended in a few words, or "Running".
    public var summary: String
    /// Replies passed to agents.
    public var handOffs: Int
    /// When it began. Nil for the run going now.
    public var started: Date?
    /// What it cost, when the Mac has worked that out.
    public var cost: Usage?
    /// True when a flow of another project open on the Mac has the same id, which the Mac won't open from a device.
    public var sharedID: Bool?

    public var id: String { runID.map { "\(projectID)/\($0)" } ?? "live:\(projectID)/\(flowID)" }

    public init(flowID: String, flowName: String, projectID: String, projectName: String, runID: String?, number: Int?,
                outcome: RunRecord.Outcome?, summary: String, handOffs: Int, started: Date?, cost: Usage? = nil, sharedID: Bool? = nil) {
        self.flowID = flowID; self.flowName = flowName; self.projectID = projectID; self.projectName = projectName
        self.runID = runID; self.number = number; self.outcome = outcome; self.summary = summary; self.handOffs = handOffs
        self.started = started; self.cost = cost; self.sharedID = sharedID
    }

    var cut: RemoteRunEntry {
        var entry = self
        entry.flowName = RemoteOverview.cut(flowName)
        entry.projectName = RemoteOverview.cut(projectName)
        entry.summary = RemoteOverview.cut(summary)
        return entry
    }
}

/// One Start card with a schedule, in the list across flows. It carries no command: what the schedule runs is
/// read in the flow, and turning it on is done on the Mac.
public struct RemoteScheduleEntry: Codable, Equatable, Sendable, Identifiable {
    public var flowID: String
    public var flowName: String
    public var projectID: String
    public var projectName: String
    public var cardID: String
    public var cardName: String
    /// When it runs, in the Mac's words: "Every day at 09:00", "When src changes".
    public var summary: String
    /// It waits on a file and not the clock.
    public var isFile: Bool
    /// On, as the Mac's Schedules place says.
    public var armed: Bool
    /// When the clock next starts a run. Nil when it is off, or waits on a file.
    public var next: Date?
    public var sharedID: Bool?

    public var id: String { "\(projectID)/\(flowID)/\(cardID)" }

    public init(flowID: String, flowName: String, projectID: String, projectName: String, cardID: String, cardName: String,
                summary: String, isFile: Bool, armed: Bool, next: Date? = nil, sharedID: Bool? = nil) {
        self.flowID = flowID; self.flowName = flowName; self.projectID = projectID; self.projectName = projectName
        self.cardID = cardID; self.cardName = cardName; self.summary = summary; self.isFile = isFile; self.armed = armed
        self.next = next; self.sharedID = sharedID
    }

    var cut: RemoteScheduleEntry {
        var entry = self
        entry.flowName = RemoteOverview.cut(flowName)
        entry.projectName = RemoteOverview.cut(projectName)
        entry.cardName = RemoteOverview.cut(cardName)
        entry.summary = RemoteOverview.cut(summary)
        return entry
    }
}

/// Restarting a flow's agents together, as the Mac's Restart menu does.
public enum RemoteRestart: Codable, Equatable, Hashable, Sendable {
    /// Every agent, and the orchestrator unless it is left out.
    case all(withOrchestrator: Bool)
    /// These agent cards. A device has its own selection, so it names the cards: the Mac's selection is never used.
    case cards([String])
    /// The agents running with settings changed since they started, and the orchestrator if the flow's details changed under it.
    case awaitingNewSettings
}

/// The Mac's Restart menu as a device offers it: the same items in the same words, and which can be chosen.
/// The Mac's own menu (`RestartMenuButton` in `App/Views/FlowHeader.swift`) is built from this too, so the two can't drift.
public struct RestartMenu: Equatable, Sendable {
    public struct Item: Equatable, Identifiable, Sendable {
        public var title: String
        public var which: RemoteRestart
        public var isEnabled: Bool
        /// A line is drawn above it.
        public var startsGroup: Bool
        public var id: String { title }
    }

    public var items: [Item]

    /// - Parameter selected: the agent cards selected on the canvas, in canvas order. Cards of other kinds picked with them don't count.
    /// - Parameter awaiting: how many agents, the orchestrator included, are running with settings they haven't started using.
    public init(selected: [String], awaiting: Int) {
        var items = [
            Item(title: "Restart All Agents", which: .all(withOrchestrator: true), isEnabled: true, startsGroup: false),
            Item(title: "Restart All Agents Except the Orchestrator", which: .all(withOrchestrator: false), isEnabled: true, startsGroup: false),
            Item(title: selected.count <= 1 ? "Restart Selected Agent" : "Restart \(selected.count) Selected Agents",
                 which: .cards(selected), isEnabled: !selected.isEmpty, startsGroup: false),
        ]
        if awaiting > 0 {
            items.append(Item(title: awaiting == 1 ? "Restart the One with New Settings" : "Restart the \(awaiting) with New Settings",
                              which: .awaitingNewSettings, isEnabled: true, startsGroup: true))
        }
        self.items = items
    }

    /// The agents that a restart would cut short, by name: those working, or waiting on the person, among the ones it restarts.
    /// The Mac asks about them first; a device asks in its own words before it sends.
    /// - Parameter sessions: each session's state, by card id, with the orchestrator under `Remote.orchestratorKey`.
    /// - Parameter agents: every agent card of the flow, by id, with its name, in canvas order.
    /// - Parameter awaiting: the agents (by id) and whether the orchestrator is waiting to use new settings.
    public static func busy(_ which: RemoteRestart, sessions: [String: SessionState], agents: [(id: String, name: String)],
                            awaiting: Set<String>, orchestratorAwaiting: Bool) -> [String] {
        func isBusy(_ key: String) -> Bool { [.working, .needsYou].contains(sessions[key] ?? .notStarted) }
        var names: [String] = []
        let restarted: [(id: String, name: String)]
        var withOrchestrator = false
        switch which {
        case .all(let orchestrator):
            restarted = agents
            withOrchestrator = orchestrator
        case .cards(let ids):
            restarted = agents.filter { ids.contains($0.id) }
        case .awaitingNewSettings:
            restarted = agents.filter { awaiting.contains($0.id) }
            withOrchestrator = orchestratorAwaiting
        }
        names += restarted.filter { isBusy($0.id) }.map(\.name)
        if withOrchestrator, isBusy(Remote.orchestratorKey) { names.append("the orchestrator") }
        return names
    }
}
