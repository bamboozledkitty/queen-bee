import AppKit
import Foundation
import Observation
import QueenBeeCore

nonisolated enum Selection: Equatable, Sendable {
    case none
    case card(String)
    case link(String)
}

nonisolated struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let text: String
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

    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored private var sessions: [String: TerminalSession] = [:]
    @ObservationIgnored private var engine: Engine?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isOpen = false
    /// Agents whose plugin has reported a finished turn since their session started. Once a
    /// plugin has spoken it is loaded, and the app never routes that agent's replies itself.
    @ObservationIgnored private var pluginSpoke: Set<String> = []
    /// Hand-offs given to a plugin to send, by the receiving session's id, until it says how they went.
    @ObservationIgnored private var inFlight: [String: Delivery] = [:]
    @ObservationIgnored private var runLogStart = 0

    private var services: AppServices { AppServices.shared }
    var warnings: [String: String] { QueenBeeCore.warnings(for: flow) }

    init(flow: Flow, fileURL: URL, project: ProjectModel) {
        self.flow = flow
        self.fileURL = fileURL
        self.project = project
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
        sessions.values.forEach { $0.terminate() }
        sessions.removeAll()
        isOpen = false
    }

    // MARK: Editing

    /// Applies a change to a copy of the flow and keeps it only if it is valid.
    @discardableResult
    private func perform(_ body: (inout Flow) throws -> Void) -> Bool {
        var copy = flow
        do {
            try body(&copy)
        } catch {
            banner = String(describing: error)
            return false
        }
        banner = nil
        flow = copy
        reconcile()
        return true
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
        default: break
        }
        if isOpen, services.environment != nil { startMissingSessions() }
    }

    func select(_ new: Selection) {
        if selection != new { selection = new }
    }

    func moveCard(_ id: String, x: Double, y: Double) {
        guard let i = flow.cards.firstIndex(where: { $0.id == id }) else { return }
        flow.cards[i].x = x
        flow.cards[i].y = y
    }

    func resizeCard(_ id: String, width: Double, height: Double) {
        var patch = CardPatch()
        patch.width = width
        patch.height = height
        perform { try $0.updateCard(id, patch: patch) }
    }

    func update(_ id: String, _ patch: CardPatch) {
        perform { try $0.updateCard(id, patch: patch) }
    }

    func addCard(_ kind: CardKind) {
        var made: Card?
        let center = canvas?.visibleCenter ?? CGPoint(x: 400, y: 300)
        // Step each new card a little so several added in a row don't stack exactly.
        let nudge = Double(flow.cards.count % 6) * 28
        perform {
            let size = Card.make(kind: kind, name: "x", x: 0, y: 0)
            made = try $0.addCard(kind: kind, x: max(20, center.x - size.width / 2 + nudge),
                                  y: max(20, center.y - size.height / 2 + nudge))
        }
        if let made { selection = .card(made.id) }
    }

    func link(from: String, port: String, to: String) {
        var made: Link?
        perform { made = try $0.addLink(from: from, port: port, to: to) }
        if let made { selection = .link(made.id) }
    }

    func setMaxPasses(_ id: String, _ value: Int) {
        perform { try $0.updateLink(id, maxPasses: value) }
    }

    func deleteSelection() {
        switch selection {
        case .card(let id): perform { try $0.removeCard(id) }
        case .link(let id): perform { try $0.removeLink(id) }
        case .none: break
        }
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        flow.name = trimmed
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
        if flow.cards[index].sessionID == nil { flow.cards[index].sessionID = UUID().uuidString.lowercased() }
        let card = flow.cards[index]
        guard let spec = ClaudeLauncher.agent(flow: flow, card: card, sessionID: card.sessionID!, projectRoot: project.root,
                                              services: services, environment: environment) else {
            banner = services.problem
            return
        }
        freshSession(for: id).start(spec)
    }

    func startOrchestrator() {
        guard let environment = services.environment else { return }
        if flow.orchestratorSessionID == nil { flow.orchestratorSessionID = UUID().uuidString.lowercased() }
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
        session.apply(hook: event, notificationType: type)
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

    /// Why an agent may not message `to`, or nil when it may. Agents talk along the links
    /// drawn on the canvas, and to the orchestrator.
    func refusal(from who: String, to: String) -> String? {
        guard who != Self.orchestratorKey, let sender = flow.card(who) else { return nil }
        let address = to.lowercased()
        if address.hasPrefix(ClaudeLauncher.orchestratorName(for: flow).lowercased()) { return nil }
        let target = flow.cards
            .filter { card in
                guard card.kind == .agent, card.id != who else { return false }
                if let sid = card.sessionID, address.contains(sid) { return true }
                let name = card.name.lowercased()
                return address == name || address.hasPrefix(name + "-") || address.hasPrefix(name + " ")
            }
            .max { $0.name.count < $1.name.count }
        guard let target, !linkedAgents(of: who).contains(target.id) else { return nil }
        return "\(sender.name) isn't linked to \(target.name) in the flow \"\(flow.name)\". Ask the person or the orchestrator to link the two cards first."
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
            if sender != nil, settled, let sid = live.claudeSessionID {
                forPlugin.append((sid, delivery.text))
                inFlight[sid] = delivery
            } else {
                live.send(delivery.text)
            }
        }
        if output.finished {
            isRunning = false
            notifyOrchestrator(of: output)
        } else if output.runID != nil {
            isRunning = true
        }
        return forPlugin
    }

    private func save(_ text: String, to file: String, card: String) {
        let url = project.root.appendingPathComponent(file).standardizedFileURL
        guard url.path.hasPrefix(project.root.path + "/") else {
            append("\(card) didn't save: \(file) is outside the project folder")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        flow = copy
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
