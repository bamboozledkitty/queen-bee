import AppKit
import Foundation
import Observation
import QueenBeeCore

nonisolated enum Selection: Equatable, Sendable {
    case none
    case card(String)
    case link(String)
    /// Two or more cards, picked with Shift or by dragging a box round them.
    case cards(Set<String>)

    /// One card is `.card`, so its settings show; several are `.cards`.
    static func of(_ ids: Set<String>) -> Selection {
        ids.count > 1 ? .cards(ids) : ids.first.map { .card($0) } ?? .none
    }

    var cardIDs: Set<String> {
        switch self {
        case .card(let id): [id]
        case .cards(let ids): ids
        case .none, .link: []
        }
    }
}

/// Where the run on show has been, for one card.
nonisolated struct RunMark: Equatable, Sendable, Codable {
    /// Messages that reached the card along a link.
    var arrivals = 0
    /// Times a message left the card.
    var passes = 0
    /// How many times it left by each output, and the output it left by last.
    var ports: [String: Int] = [:]
    var lastPort: String?
    /// Arrivals since it last passed anything on: what an And is holding, what an Or dropped.
    var holding = 0
    /// The run stopped at this card.
    var failed = false
}

/// What a flow needs from you right now, for its row in the sidebar.
nonisolated enum FlowActivity: Sendable {
    case quiet, running, needsYou, failed
}

nonisolated struct LogLine: Identifiable, Sendable, Codable {
    var id = UUID()
    let date: Date
    let text: String
}

/// What a flow's runs left behind, kept between launches: the log, each End card's answer,
/// and the marks the last run made on cards and links.
nonisolated struct RunHistory: Codable, Sendable {
    var log: [LogLine] = []
    var results: [String: String] = [:]
    var marks: [String: RunMark] = [:]
    var linkPasses: [String: Int] = [:]
    var handOffs = 0
}

/// One open flow: the graph, its sessions, and its runs. Every change to the graph goes
/// through here, whether it comes from the canvas, the settings panel or the orchestrator's
/// tools, so all three always see the same thing.
// Named as main-actor here because conforming to a Sendable protocol would otherwise opt the class out of the app's default.
@MainActor @Observable
final class FlowController: ToolHost {
    static let orchestratorKey = "orchestrator"

    var flow: Flow {
        didSet { if flow != oldValue { scheduleSave() } }
    }
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored unowned let project: ProjectModel

    var selection: Selection = .none
    /// The agent card whose terminal has the keyboard.
    var focusedCardID: String?
    private(set) var log: [LogLine] = []
    /// Each End card's latest final answer.
    private(set) var results: [String: String] = [:]
    /// A one-line message about the last thing that didn't work.
    var banner: String?
    private(set) var isRunning = false
    /// Bumped when a session object is replaced, so the canvas picks up its new terminal.
    private(set) var sessionGeneration = 0
    /// Where the latest run has been, card by card. Kept after the run ends, cleared when the next starts.
    private(set) var marks: [String: RunMark] = [:]
    /// How many times each link has fired in the latest run.
    private(set) var linkPasses: [String: Int] = [:]
    /// The links each waiting agent's hand-off travelled, by that agent's card id.
    private var liveLinks: [String: Set<String>] = [:]
    /// Hand-offs made in the latest run.
    private(set) var handOffs = 0
    /// The canvas's zoom, published by the canvas for the zoom pill.
    var zoom: Double = 1

    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored private(set) var sessions: [String: TerminalSession] = [:]
    @ObservationIgnored private var engine: Engine?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var isOpen = false
    /// Agents whose plugin has reported a finished turn since their session started. Once a
    /// plugin has spoken it is loaded, and the app never routes that agent's replies itself.
    @ObservationIgnored private var pluginSpoke: Set<String> = []
    /// Hand-offs given to a plugin to send, by the receiving session's id, until it says how they went.
    @ObservationIgnored private var inFlight: [String: Delivery] = [:]
    @ObservationIgnored private var runLogStart = 0
    /// Undo and redo for the graph. The canvas hands this to the Edit menu.
    @ObservationIgnored let undoManager = UndoManager()
    /// The last change given an undo step, so a run of the same kind of change shares one.
    @ObservationIgnored private var lastUndo: (key: String, at: Date)?
    /// The flow as it was when a drag began. While set, the drag's steps don't each get an undo.
    @ObservationIgnored private var gestureStart: Flow?

    private var services: AppServices { AppServices.shared }
    var warnings: [String: String] { QueenBeeCore.warnings(for: flow) }
    var liveLinkIDs: Set<String> { liveLinks.values.reduce(into: Set<String>()) { $0.formUnion($1) } }

    /// Agent cards whose session is waiting on the person, in canvas order.
    var cardsNeedingYou: [Card] {
        flow.cards.filter { $0.kind == .agent && sessions[$0.id]?.state == .needsYou }
    }

    var activity: FlowActivity {
        if !cardsNeedingYou.isEmpty { return .needsYou }
        if isRunning { return .running }
        if marks.values.contains(where: \.failed) { return .failed }
        return .quiet
    }

    /// True for a flow nobody has built anything in yet: just its Start card, with no command.
    var isBlank: Bool {
        flow.links.isEmpty && flow.cards.allSatisfy { $0.kind == .start && ($0.command ?? "").isEmpty }
    }

    init(flow: Flow, fileURL: URL, project: ProjectModel) {
        self.flow = flow
        self.fileURL = fileURL
        self.project = project
        undoManager.groupsByEvent = false
        loadHistory()
    }

    // MARK: History

    /// Kept in the app's own folder, not the project's, so a run leaves nothing to commit.
    private var historyURL: URL {
        services.supportDirectory.appendingPathComponent("history", isDirectory: true).appendingPathComponent("\(flow.id).json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL), let history = try? JSONDecoder().decode(RunHistory.self, from: data) else { return }
        log = history.log
        results = history.results.filter { flow.card($0.key) != nil }
        marks = history.marks.filter { flow.card($0.key) != nil }
        linkPasses = history.linkPasses
        handOffs = history.handOffs
        // What was loaded is earlier runs; the orchestrator is only told about new ones.
        runLogStart = log.count
    }

    private func scheduleHistorySave() {
        historyTask?.cancel()
        historyTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self.saveHistory()
        }
    }

    private func saveHistory() {
        historyTask?.cancel()
        historyTask = nil
        let history = RunHistory(log: log, results: results, marks: marks, linkPasses: linkPasses, handOffs: handOffs)
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    /// Empties the log. Answers and run marks stay until the next run replaces them.
    func clearLog() {
        log.removeAll()
        runLogStart = 0
        saveHistory()
    }

    /// The flow is being deleted: its history goes with it.
    func forgetHistory() {
        historyTask?.cancel()
        historyTask = nil
        try? FileManager.default.removeItem(at: historyURL)
    }

    // MARK: Opening and closing

    /// The flow came on screen: start its sessions, once `claude` has been found.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        Task {
            while services.environment == nil { try? await Task.sleep(for: .milliseconds(100)) }
            startMissingSessions()
        }
    }

    func shutDown() {
        saveNow()
        if historyTask != nil { saveHistory() }
        sessions.values.forEach { $0.terminate() }
        sessions.removeAll()
        isOpen = false
    }

    // MARK: Editing

    /// Applies a change to a copy of the flow and keeps it only if it is valid. `name` is what
    /// the Edit menu calls it. Changes with the same `key` made close together undo as one.
    @discardableResult
    private func perform(_ name: String, key: String? = nil, _ body: (inout Flow) throws -> Void) -> Bool {
        var copy = flow
        do {
            try body(&copy)
        } catch {
            banner = String(describing: error)
            return false
        }
        banner = nil
        let old = flow
        flow = copy
        registerUndo(from: old, name, key: key)
        reconcile()
        return true
    }

    // MARK: Undo

    /// Makes the change from `old` to the flow as it is now undoable.
    private func registerUndo(from old: Flow, _ name: String, key: String? = nil, within window: TimeInterval = 1.5) {
        guard gestureStart == nil, old != flow else { return }
        if let key, let last = lastUndo, last.key == key, Date().timeIntervalSince(last.at) < window {
            // The step already on the stack goes back to before the first of these changes.
            lastUndo = (key, Date())
            return
        }
        lastUndo = key.map { ($0, Date()) }
        // Each step is its own group. Left to group by event, changes that arrive from the
        // orchestrator's tools rather than from a click all landed in one step.
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { $0.restore(old, name) }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    /// Puts the graph back to `old`, and makes that undoable in turn. Sessions are not part
    /// of the graph: a card that is still there keeps the session it has now.
    private func restore(_ old: Flow, _ name: String) {
        let current = flow
        var back = old
        back.orchestratorSessionID = current.orchestratorSessionID
        for i in back.cards.indices {
            if let now = current.card(back.cards[i].id) { back.cards[i].sessionID = now.sessionID }
        }
        lastUndo = nil
        flow = back
        undoManager.registerUndo(withTarget: self) { $0.restore(current, name) }
        undoManager.setActionName(name)
        reconcile()
    }

    /// A drag is starting: everything until `endGesture` is one undo step.
    func beginGesture() {
        if gestureStart == nil { gestureStart = flow }
    }

    func endGesture(_ name: String) {
        guard let start = gestureStart else { return }
        gestureStart = nil
        registerUndo(from: start, name)
    }

    /// After the graph changes: drop sessions of deleted cards, start sessions of new ones,
    /// and clear a selection that points at something gone.
    private func reconcile() {
        let agentIDs = Set(flow.cards.filter { $0.kind == .agent }.map(\.id))
        for (id, session) in sessions where id != Self.orchestratorKey && !agentIDs.contains(id) {
            session.terminate()
            sessions[id] = nil
        }
        switch selection {
        case .card(let id) where flow.card(id) == nil: selection = .none
        case .link(let id) where !flow.links.contains(where: { $0.id == id }): selection = .none
        case .cards(let ids):
            let left = ids.filter { flow.card($0) != nil }
            if left != ids { selection = .of(left) }
        default: break
        }
        if isOpen, services.environment != nil { startMissingSessions() }
    }

    func select(_ new: Selection) {
        if selection != new { selection = new }
    }

    /// Shift-click: adds a card to what is selected, or takes it out.
    func toggleSelection(_ id: String) {
        var ids = selection.cardIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        selection = .of(ids)
    }

    func selectAll() {
        selection = .of(Set(flow.cards.map(\.id)))
    }

    /// Where each card a drag of `id` moves is now. Dragging one of several selected cards
    /// moves them all; dragging any other card selects it and moves it alone.
    func dragOrigins(for id: String) -> [String: CGPoint] {
        if !selection.cardIDs.contains(id) { selection = .card(id) }
        var origins: [String: CGPoint] = [:]
        for card in flow.cards where selection.cardIDs.contains(card.id) { origins[card.id] = CGPoint(x: card.x, y: card.y) }
        return origins
    }

    /// Puts each card at its origin plus `offset`. Part of a drag, so it is undone with the drag.
    func moveCards(from origins: [String: CGPoint], by offset: CGSize) {
        var copy = flow
        for i in copy.cards.indices {
            guard let origin = origins[copy.cards[i].id] else { continue }
            copy.cards[i].x = max(CardView.farLeft, origin.x + offset.width)
            copy.cards[i].y = max(CardView.farLeft, origin.y + offset.height)
        }
        if copy != flow { flow = copy }
    }

    /// The arrow keys: moves what is selected by a step.
    func nudgeSelection(dx: Double, dy: Double) {
        let ids = selection.cardIDs
        guard !ids.isEmpty else { return }
        let old = flow
        for i in flow.cards.indices where ids.contains(flow.cards[i].id) {
            flow.cards[i].x = max(CardView.farLeft, flow.cards[i].x + dx)
            flow.cards[i].y = max(CardView.farLeft, flow.cards[i].y + dy)
        }
        registerUndo(from: old, "Move", key: "nudge")
    }

    func resizeCard(_ id: String, width: Double, height: Double) {
        var patch = CardPatch()
        patch.width = width
        patch.height = height
        perform("Resize") { try $0.updateCard(id, patch: patch) }
    }

    func update(_ id: String, _ patch: CardPatch) {
        perform("Change \(flow.card(id)?.name ?? "Card")", key: "edit:\(id)") { try $0.updateCard(id, patch: patch) }
    }

    // MARK: Copying

    /// What Copy puts on the pasteboard and Paste reads back: only this app writes or reads it.
    static let fragmentType = NSPasteboard.PasteboardType("dev.queenbee.flow-fragment")

    func duplicateSelection() {
        let ids = selection.cardIDs
        guard !ids.isEmpty else { return }
        var made: [Card] = []
        perform(ids.count == 1 ? "Duplicate Card" : "Duplicate Cards") { made = $0.insert($0.fragment(of: ids), dx: 48, dy: 48) }
        if !made.isEmpty { selection = .of(Set(made.map(\.id))) }
    }

    func copySelection() {
        let ids = selection.cardIDs
        guard !ids.isEmpty, let data = try? JSONEncoder().encode(flow.fragment(of: ids)) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.fragmentType)
    }

    var canPaste: Bool { NSPasteboard.general.data(forType: Self.fragmentType) != nil }

    /// Pastes what was copied. With a point, as from the canvas's menu, its top-left card
    /// lands there; without, it lands a step away from where it was copied.
    func paste(at point: CGPoint? = nil) {
        guard let data = NSPasteboard.general.data(forType: Self.fragmentType),
              let fragment = try? JSONDecoder().decode(FlowFragment.self, from: data), !fragment.cards.isEmpty else { return }
        var dx = 48.0, dy = 48.0
        if let point, let left = fragment.cards.map(\.x).min(), let top = fragment.cards.map(\.y).min() {
            dx = point.x - left
            dy = point.y - top
        }
        var made: [Card] = []
        perform("Paste") { made = $0.insert(fragment, dx: dx, dy: dy) }
        if !made.isEmpty { selection = .of(Set(made.map(\.id))) }
    }

    /// Adds a card. With a point, as when one is dropped from the palette, the card is centred
    /// there. Without, it goes to the middle of what is on screen, stepped clear of other cards.
    func addCard(_ kind: CardKind, at point: CGPoint? = nil) {
        var made: Card?
        let size = Card.make(kind: kind, name: "x", x: 0, y: 0)
        var spot: CGRect
        if let point {
            spot = CGRect(x: max(20, point.x - size.width / 2), y: max(20, point.y - CanvasGeometry.titleHeight / 2),
                          width: size.width, height: size.height)
        } else {
            let center = canvas?.visibleCenter ?? CGPoint(x: 400, y: 300)
            spot = CGRect(x: max(20, center.x - size.width / 2), y: max(20, center.y - size.height / 2),
                          width: size.width, height: size.height)
            let taken = flow.cards.map(CanvasGeometry.frame(of:))
            var tries = 0
            while tries < 30, taken.contains(where: { $0.insetBy(dx: -16, dy: -16).intersects(spot) }) {
                spot.origin.x += 48
                spot.origin.y += 48
                tries += 1
            }
        }
        var patch = CardPatch()
        if kind == .agent, let model = UserDefaults.standard.string(forKey: "defaultModel"), !model.isEmpty { patch.model = model }
        perform("Add \(kind.label)") { made = try $0.addCard(kind: kind, x: spot.minX, y: spot.minY, patch: patch) }
        if let made { selection = .card(made.id) }
    }

    func link(from: String, port: String, to: String) {
        var made: Link?
        perform("Link") { made = try $0.addLink(from: from, port: port, to: to) }
        if let made { selection = .link(made.id) }
    }

    func setMaxPasses(_ id: String, _ value: Int) {
        perform("Change Link", key: "link:\(id)") { try $0.updateLink(id, maxPasses: value) }
    }

    func deleteSelection() {
        switch selection {
        case .card(let id): perform("Delete Card") { try $0.removeCard(id) }
        case .link(let id): perform("Delete Link") { try $0.removeLink(id) }
        case .cards(let ids): perform("Delete Cards") { for id in ids { try $0.removeCard(id) } }
        case .none: break
        }
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let old = flow
        flow.name = trimmed
        registerUndo(from: old, "Rename Flow")
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        do {
            try project.store.save(flow, to: fileURL)
        } catch {
            banner = "Couldn't save the flow: \(error.localizedDescription)"
        }
    }

    // MARK: Sessions

    /// The session behind an agent card, or behind the orchestrator for `orchestratorKey`.
    func session(forCard id: String) -> TerminalSession {
        _ = sessionGeneration
        if let existing = sessions[id] { return existing }
        let session = TerminalSession(key: "\(flow.id)/\(id)")
        session.onExit = { [weak self] _ in self?.sessionExited(id) }
        sessions[id] = session
        return session
    }

    var orchestrator: TerminalSession { session(forCard: Self.orchestratorKey) }

    /// The settings changed on a card since its session started, which the running session
    /// doesn't have yet. Empty when the session isn't running or is up to date.
    func settingsAwaitingRestart(forCard id: String) -> [String] {
        guard let card = flow.card(id), let session = sessions[id], session.isLive, let launched = session.launched else { return [] }
        return AgentSettings(card).differences(from: launched)
    }

    /// Puts a card's settings back to what its running session was started with, undoing
    /// whatever has been changed since.
    func revertSettings(forCard id: String) {
        guard let session = sessions[id], session.isLive, let launched = session.launched else { return }
        var patch = CardPatch()
        patch.name = launched.name
        patch.instructions = launched.instructions
        // An empty string clears these back to "your default".
        patch.model = launched.model
        patch.effort = launched.effort
        patch.permissionMode = launched.permissionMode
        patch.cwd = launched.folder
        update(id, patch)
    }

    private func startMissingSessions() {
        for card in flow.cards where card.kind == .agent && session(forCard: card.id).state == .notStarted {
            startSession(forCard: card.id)
        }
        if orchestrator.state == .notStarted { startOrchestrator() }
    }

    /// Starts, or after an exit restarts, the session of one agent card.
    func startSession(forCard id: String) {
        guard let environment = services.environment else { return }
        guard let index = flow.cards.firstIndex(where: { $0.id == id }), flow.cards[index].kind == .agent else { return }
        // The id ends up on the command line and in a file name, so one from a flow file has to be a real id.
        if flow.cards[index].sessionID.flatMap(UUID.init(uuidString:)) == nil { flow.cards[index].sessionID = UUID().uuidString.lowercased() }
        let card = flow.cards[index]
        guard let spec = ClaudeLauncher.agent(flow: flow, card: card, sessionID: card.sessionID!, projectRoot: project.root,
                                              services: services, environment: environment) else {
            banner = services.problem
            return
        }
        freshSession(for: id).start(spec, settings: AgentSettings(card))
    }

    func startOrchestrator() {
        guard let environment = services.environment else { return }
        if flow.orchestratorSessionID.flatMap(UUID.init(uuidString:)) == nil { flow.orchestratorSessionID = UUID().uuidString.lowercased() }
        guard let spec = ClaudeLauncher.orchestrator(flow: flow, sessionID: flow.orchestratorSessionID!, projectRoot: project.root,
                                                     services: services, environment: environment) else {
            banner = services.problem
            return
        }
        freshSession(for: Self.orchestratorKey).start(spec)
    }

    /// A terminal that has run a process doesn't take a second one, so a restart gets a new terminal.
    private func freshSession(for id: String) -> TerminalSession {
        if let old = sessions[id], old.state != .notStarted {
            old.terminate()
            sessions[id] = nil
            sessionGeneration += 1
        }
        return session(forCard: id)
    }

    private func sessionExited(_ id: String) {
        guard id != Self.orchestratorKey, isRunning, let engine else { return }
        let name = flow.card(id)?.name ?? id
        markFailed(id)
        Task { self.absorb(await engine.agentFailed(flow: self.flow, cardID: id, reason: "\(name)'s session exited"), sender: nil) }
    }

    private func readyEngine() -> Engine? {
        if let engine { return engine }
        guard let environment = services.environment, let claude = environment.claude else { return nil }
        let made = Engine(judge: ClaudeJudge(claude: claude, environment: environment.variables()))
        engine = made
        return made
    }

    // MARK: Requests from sessions

    /// A Claude Code hook fired in one of this flow's sessions.
    func handleHook(from who: String, payload: JSONValue) {
        guard let session = sessions[who] else { return }
        let event = payload["hook_event_name"]?.stringValue ?? ""
        let type = payload["notification_type"]?.stringValue
            ?? ((payload["message"]?.stringValue ?? "").localizedCaseInsensitiveContains("permission") ? "permission_prompt" : nil)
        let wasWaiting = session.state == .needsYou
        session.apply(hook: event, notificationType: type)
        if session.state == .needsYou, !wasWaiting {
            let name = who == Self.orchestratorKey ? "The orchestrator" : flow.card(who)?.name ?? "An agent"
            Notifier.post(title: "\(name) needs you", body: "In \(flow.name). It is waiting for an answer or a permission.",
                          flowID: flow.id, cardID: who == Self.orchestratorKey ? nil : who)
        }
        if event == "Stop", let reply = payload["last_assistant_message"]?.stringValue { session.lastReply = reply }
        guard who != Self.orchestratorKey else { return }
        switch event {
        case "SessionStart":
            pluginSpoke.remove(who)
        case "Stop":
            let reply = payload["last_assistant_message"]?.stringValue ?? ""
            session.lastReply = reply
            routeIfPluginIsSilent(who, reply: reply)
        case "StopFailure":
            guard isRunning, let engine else { return }
            let name = flow.card(who)?.name ?? who
            markFailed(who)
            Task { self.absorb(await engine.agentFailed(flow: self.flow, cardID: who, reason: "\(name)'s turn ended with an API error"), sender: nil) }
        default:
            break
        }
    }

    /// The plugin normally reports a finished turn within milliseconds. If it hasn't after a
    /// few seconds it isn't loaded, so the app routes the reply itself and types the hand-offs in.
    private func routeIfPluginIsSilent(_ who: String, reply: String) {
        guard isRunning, !pluginSpoke.contains(who), let engine else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard self.isRunning, !self.pluginSpoke.contains(who) else { return }
            self.append("The session plugin didn't report \(self.flow.card(who)?.name ?? who)'s reply, so the app passed it on")
            self.absorb(await engine.agentReplied(flow: self.flow, cardID: who, text: reply), sender: nil)
        }
    }

    /// An agent's turn ended and its plugin asks where the reply goes. The answer is the
    /// hand-offs for that plugin to send as session messages.
    func handleRoute(from who: String, answer: String) async -> [(to: String, text: String)] {
        guard who != Self.orchestratorKey, flow.card(who) != nil else { return [] }
        pluginSpoke.insert(who)
        sessions[who]?.lastReply = answer
        guard let engine = readyEngine() else { return [] }
        return absorb(await engine.agentReplied(flow: flow, cardID: who, text: answer), sender: who)
    }

    /// The plugin reports how its sends went. A hand-off that didn't arrive is typed in.
    func handleSent(from who: String, results: [JSONValue]) {
        for result in results {
            guard let to = result["to"]?.stringValue, let delivery = inFlight.removeValue(forKey: to) else { continue }
            if result["isDelivered"]?.boolValue == false {
                let name = flow.card(delivery.toCardID)?.name ?? delivery.toCardID
                append("Couldn't message \(name) (\(result["reason"]?.stringValue ?? "no reason given")), so the hand-off was typed in")
                session(forCard: delivery.toCardID).send(delivery.text)
            }
        }
    }

    /// What to do with a SendMessage from one of this flow's sessions.
    struct SendVerdict {
        var refusal: String?
        /// The exact session to deliver to, when the recipient is part of this flow.
        var sessionID: String?
    }

    /// Decides a SendMessage a session's model is making. A recipient named like one of this
    /// flow's cards is that card, whatever other sessions on the machine share the name, so
    /// the answer carries the card's session id. An agent may only message agents its card is
    /// linked to, and the orchestrator. The orchestrator may message any agent.
    func judgeSend(from who: String, to: String) -> SendVerdict {
        let address = to.lowercased()
        if who != Self.orchestratorKey, address.hasPrefix(ClaudeLauncher.orchestratorName(for: flow).lowercased()) {
            return SendVerdict(sessionID: flow.orchestratorSessionID)
        }
        let target = flow.cards
            .filter { card in
                guard card.kind == .agent, card.id != who else { return false }
                if let sid = card.sessionID, address.contains(sid) { return true }
                let name = card.name.lowercased()
                return address == name || address.hasPrefix(name + "-") || address.hasPrefix(name + " ")
            }
            .max { $0.name.count < $1.name.count }
        // Not one of this flow's sessions: Claude Code decides.
        guard let target else { return SendVerdict() }
        if who != Self.orchestratorKey, let sender = flow.card(who), !linkedAgents(of: who).contains(target.id) {
            return SendVerdict(refusal: "\(sender.name) isn't linked to \(target.name) in the flow \"\(flow.name)\". Ask the person or the orchestrator to link the two cards first.")
        }
        return SendVerdict(sessionID: target.sessionID)
    }

    /// The agents a card reaches, or is reached by, through logic cards alone.
    private func linkedAgents(of id: String) -> Set<String> {
        var found = Set<String>()
        for forward in [true, false] {
            var seen: Set<String> = [id]
            var stack = [id]
            while let at = stack.popLast() {
                let next = flow.links.filter { forward ? $0.from == at : $0.to == at }.map { forward ? $0.to : $0.from }
                for n in next where !seen.contains(n) {
                    seen.insert(n)
                    guard let card = flow.card(n) else { continue }
                    if card.kind == .agent { found.insert(n) } else { stack.append(n) }
                }
            }
        }
        return found
    }

    // MARK: Runs

    @discardableResult
    func run(command: String? = nil) async -> String {
        guard let engine = readyEngine() else { return services.problem ?? "Claude Code isn't ready yet." }
        if !isRunning {
            results.removeAll()
            marks.removeAll()
            linkPasses.removeAll()
            liveLinks.removeAll()
            handOffs = 0
            runLogStart = log.count
        }
        let output = await engine.start(flow: flow, startCardID: nil, command: command)
        absorb(output, sender: nil)
        return output.log.last ?? (output.runID.map { "Run \($0) started" } ?? "Nothing to run")
    }

    func stop() async {
        guard let engine else { return }
        absorb(await engine.stop(), sender: nil)
    }

    /// Takes in what the engine decided: logs it, shows End results, and delivers hand-offs.
    /// With `sender` set, that agent's plugin sends the hand-offs as session messages and they
    /// are returned for it; hand-offs it can't send that way are typed into the target's terminal.
    @discardableResult
    private func absorb(_ output: RunOutput, sender: String?) -> [(to: String, text: String)] {
        output.log.forEach(append)
        record(output.visits, sender: sender)
        handOffs += output.deliveries.count
        for result in output.results {
            results[result.cardID] = result.text
            if let file = result.saveTo, !file.isEmpty { save(result.text, to: file, card: result.cardName) }
        }
        var forPlugin: [(to: String, text: String)] = []
        for delivery in output.deliveries {
            let target = session(forCard: delivery.toCardID)
            if !target.isLive { startSession(forCard: delivery.toCardID) }
            let live = session(forCard: delivery.toCardID)
            let settled = live.state == .idle || live.state == .working || live.state == .needsYou
            // A session can't message itself, so a hand-off that loops straight back to the
            // agent that just replied is typed in.
            if let sender, sender != delivery.toCardID, settled, let sid = live.claudeSessionID {
                forPlugin.append((sid, delivery.text))
                inFlight[sid] = delivery
            } else {
                live.send(delivery.text)
            }
        }
        scheduleHistorySave()
        if output.finished {
            isRunning = false
            liveLinks.removeAll()
            notifyOrchestrator(of: output)
            let stopped = marks.values.contains(where: \.failed)
            Notifier.post(title: stopped ? "\(flow.name) stopped" : "\(flow.name) finished",
                          body: log.last?.text ?? "", flowID: flow.id, cardID: nil)
        } else if output.runID != nil {
            isRunning = true
        }
        return forPlugin
    }

    /// Adds what an event did to the per-card tallies. The links an event travelled stay live
    /// until the agents they led to have answered.
    private func record(_ visits: [CardVisit], sender: String?) {
        if let sender { liveLinks[sender] = nil }
        let travelled = Set(visits.compactMap(\.viaLinkID))
        for visit in visits {
            var mark = marks[visit.cardID] ?? RunMark()
            if let link = visit.viaLinkID {
                linkPasses[link, default: 0] += 1
                mark.arrivals += 1
            }
            // An agent's own reply: whatever was on its way to it has arrived and been dealt with.
            if visit.viaLinkID == nil { liveLinks[visit.cardID] = nil }
            if let port = visit.port {
                mark.passes += 1
                mark.ports[port, default: 0] += 1
                mark.lastPort = port
                mark.holding = 0
            } else if visit.viaLinkID != nil {
                mark.holding += 1
                if flow.card(visit.cardID)?.kind == .agent { liveLinks[visit.cardID, default: []].formUnion(travelled) }
            }
            marks[visit.cardID] = mark
        }
    }

    private func markFailed(_ cardID: String) {
        var mark = marks[cardID] ?? RunMark()
        mark.failed = true
        marks[cardID] = mark
    }

    private func save(_ text: String, to file: String, card: String) {
        // Symlinks are followed before the check, so a link inside the project can't point the save somewhere else.
        let root = project.root.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(file).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else {
            append("\(card) didn't save: \(file) is outside the project folder")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Creating the folders may have gone through a link that didn't resolve while they were missing.
            guard url.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(root.path) else {
                append("\(card) didn't save: \(file) is outside the project folder")
                return
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            append("\(card) saved the answer to \(file)")
        } catch {
            append("\(card) couldn't save to \(file): \(error.localizedDescription)")
        }
    }

    private func notifyOrchestrator(of output: RunOutput) {
        guard flow.notifyOrchestrator, orchestrator.isLive else { return }
        let lines = log.dropFirst(runLogStart).suffix(12).map { "- \($0.text)" }.joined(separator: "\n")
        var text = "[Queen Bee · notice] The run\(output.runID.map { " \($0)" } ?? "") has ended. This is information from the app, not a new request.\n\nWhat happened:\n\(lines)"
        for result in output.results {
            text += "\n\nFinal answer at \(result.cardName):\n\(result.text.prefix(4000))"
        }
        orchestrator.send(text)
    }

    private func append(_ text: String) {
        log.append(LogLine(date: Date(), text: text))
        scheduleHistorySave()
        if log.count > 600 {
            log.removeFirst(log.count - 600)
            runLogStart = max(0, runLogStart - 1)
        }
    }

    // MARK: ToolHost, for the orchestrator's tools

    func snapshot() async -> FlowSnapshot {
        var agents: [String: AgentStatus] = [:]
        for card in flow.cards where card.kind == .agent {
            let session = sessions[card.id]
            agents[card.id] = AgentStatus(state: (session?.state ?? .notStarted).rawValue, lastReply: session?.lastReply)
        }
        return FlowSnapshot(flow: flow, agents: agents, isRunning: isRunning)
    }

    func mutate<T: Sendable>(_ body: @Sendable (inout Flow) throws -> T) async throws -> T {
        var copy = flow
        let value = try body(&copy)
        let old = flow
        flow = copy
        // The orchestrator builds a flow in a burst of calls. They undo together.
        registerUndo(from: old, "Orchestrator's Changes", key: "orchestrator", within: 8)
        reconcile()
        return value
    }

    func runFlow(command: String?) async throws -> String {
        await run(command: command)
    }

    func stopFlow() async {
        await stop()
    }

    func runLog() async -> [String] {
        log.dropFirst(runLogStart).map(\.text)
    }
}
