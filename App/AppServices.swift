import AppKit
import Foundation
import Network
import Observation
import QueenBeeCore

/// What the whole app shares: where its files are, the socket the helper talks to,
/// and which open flow each session belongs to.
@Observable
final class AppServices {
    static let shared = AppServices()

    @ObservationIgnored let supportDirectory: URL
    @ObservationIgnored let socketPath: String
    @ObservationIgnored let helperPath: String
    @ObservationIgnored let pluginDirectory: URL
    /// Nil until the login shell has been asked for its PATH.
    private(set) var environment: ResolvedEnvironment?
    /// Why the app can't start sessions, shown in every window.
    private(set) var problem: String?

    /// The project folders in the sidebar, in the order they were added.
    private(set) var projects: [ProjectModel] = []
    /// The flow on the canvas.
    var selectedFlowID: String? {
        didSet { if selectedFlowID != oldValue { current?.open() } }
    }
    /// How much of the canvas the floating panels cover, published by the window for the canvas.
    @ObservationIgnored var canvasObstruction = CanvasObstruction(left: 400, right: 450)
    /// The first-run walk-through is on screen.
    var showsWelcome = false
    /// Blank flows whose pointer to the orchestrator has been closed.
    private(set) var dismissedHints: Set<String> = []
    private static let hintsKey = "dismissedOrchestratorHints"

    func dismissHint(forFlow id: String) {
        dismissedHints.insert(id)
        if remembersProjects { UserDefaults.standard.set(dismissedHints.sorted(), forKey: Self.hintsKey) }
    }

    func closeWelcome() {
        showsWelcome = false
        if remembersProjects { UserDefaults.standard.set(true, forKey: OnboardingView.seenKey) }
    }

    /// Flows kept at the top of the sidebar.
    private(set) var pinnedFlowIDs: Set<String> = []

    @ObservationIgnored private var controllers: [String: WeakController] = [:]
    @ObservationIgnored private var serverTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false

    private init() {
        // QB_SUPPORT_DIR lets a test copy of the app keep its socket and plugin apart from the real one's.
        if TestHarness.isEnabled, let override = ProcessInfo.processInfo.environment["QB_SUPPORT_DIR"], !override.isEmpty {
            supportDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            supportDirectory = base.appendingPathComponent("QueenBee", isDirectory: true)
        }
        socketPath = supportDirectory.appendingPathComponent("qb.sock").path
        helperPath = Bundle.main.url(forAuxiliaryExecutable: "qb")?.path
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/qb").path
        pluginDirectory = supportDirectory.appendingPathComponent("plugin/qb-link", isDirectory: true)
    }

    /// Runs once at launch: finds `claude`, puts the plugin where Claude Code can write
    /// beside it, and opens the socket.
    func start() {
        guard !didStart else { return }
        didStart = true
        // The socket and the plugin live here, so only this account may look inside.
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
        installPlugin()
        startServer()
        restoreProjects()
        // A test run isn't a first run, unless it asks to see the walk-through.
        showsWelcome = remembersProjects ? !UserDefaults.standard.bool(forKey: OnboardingView.seenKey) : LaunchArguments.welcome
        if remembersProjects { dismissedHints = Set(UserDefaults.standard.stringArray(forKey: Self.hintsKey) ?? []) }
        Task {
            let resolved = await ResolvedEnvironment.resolve()
            self.environment = resolved
            if resolved.claude == nil {
                self.problem = "Claude Code isn't installed, or `claude` isn't on your PATH. Install it from claude.com/claude-code, then reopen Queen Bee."
            }
        }
    }

    /// Claude Code writes type files into a plugin's folder when it loads it, so the copy
    /// it loads lives in Application Support, not inside the app bundle.
    private func installPlugin() {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("qb-link") else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: pluginDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: pluginDirectory)
        do {
            try fm.copyItem(at: bundled, to: pluginDirectory)
        } catch {
            problem = "Couldn't install the session plugin: \(error.localizedDescription)"
        }
    }

    // MARK: Projects and flows

    private static let projectsKey = "projects"
    private static let pinnedKey = "pinnedFlows"
    private static let trustedKey = "trustedProjects"

    /// Whether flows already saved in `root` may be opened. Opening a flow starts sessions with the
    /// instructions, folders and permissions in its file, so a folder that arrives with flows in it,
    /// such as a cloned repository, is only opened once the person has said they trust it.
    func confirmTrust(_ root: URL) -> Bool {
        let path = root.standardizedFileURL.path
        var trusted = Set(UserDefaults.standard.stringArray(forKey: Self.trustedKey) ?? [])
        if trusted.contains(path) || TestHarness.isEnabled { return true }
        let flows = (try? FileManager.default.contentsOfDirectory(at: FlowStore(root: root).directory, includingPropertiesForKeys: nil)) ?? []
        if flows.contains(where: { $0.pathExtension == "json" }) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Trust the flows in “\(root.lastPathComponent)”?"
            alert.informativeText = "This folder already has Queen Bee flows in it. Opening them starts Claude Code sessions with the instructions, working folders and permission settings saved in those files. Only continue if you trust where this folder came from."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Trust and Open")
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
        }
        trusted.insert(path)
        UserDefaults.standard.set(trusted.sorted(), forKey: Self.trustedKey)
        return true
    }
    /// A test run opens scratch folders, which shouldn't come back the next time the app starts.
    private var remembersProjects: Bool { !TestHarness.isEnabled }

    var allFlows: [FlowController] { projects.flatMap(\.controllers) }
    var current: FlowController? { allFlows.first { $0.flow.id == selectedFlowID } }
    var openProjectPaths: [String] { projects.map(\.root.path) }

    /// Puts back the folders that were in the sidebar last time, then the one named on the command line.
    private func restoreProjects() {
        if remembersProjects {
            pinnedFlowIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [])
            for path in UserDefaults.standard.stringArray(forKey: Self.projectsKey) ?? []
            where FileManager.default.fileExists(atPath: path) {
                addProject(URL(fileURLWithPath: path), select: false)
            }
        }
        if let path = LaunchArguments.takeFolder(), confirmTrust(URL(fileURLWithPath: path)) {
            let project = addProject(URL(fileURLWithPath: path), select: true)
            if project.controllers.isEmpty { project.newFlow() }
        } else if selectedFlowID == nil {
            selectedFlowID = allFlows.first?.flow.id
        }
    }

    @discardableResult
    func addProject(_ root: URL, select: Bool = true) -> ProjectModel {
        let key = root.standardizedFileURL
        let project = projects.first { $0.root == key } ?? {
            let made = ProjectModel(root: key)
            projects.append(made)
            rememberProjects()
            return made
        }()
        if select, let first = project.controllers.first { selectedFlowID = first.flow.id }
        return project
    }

    /// Takes a folder out of the sidebar. Its flows stay on disk.
    func removeProject(_ project: ProjectModel) {
        let wasCurrent = project.controllers.contains { $0.flow.id == selectedFlowID }
        project.close()
        projects.removeAll { $0 === project }
        rememberProjects()
        if wasCurrent { selectedFlowID = allFlows.first?.flow.id }
    }

    private func rememberProjects() {
        guard remembersProjects else { return }
        UserDefaults.standard.set(projects.map(\.root.path), forKey: Self.projectsKey)
    }

    func togglePin(_ flowID: String) {
        if !pinnedFlowIDs.insert(flowID).inserted { pinnedFlowIDs.remove(flowID) }
        if remembersProjects { UserDefaults.standard.set(pinnedFlowIDs.sorted(), forKey: Self.pinnedKey) }
    }

    func shutDown() {
        projects.forEach { $0.close() }
        unlink(socketPath)
    }

    func register(_ controller: FlowController) {
        controllers[controller.flow.id] = WeakController(controller)
    }

    func unregister(flowID: String) {
        controllers[flowID] = nil
    }

    // MARK: Socket

    /// What each session was told to call itself, and the session key that belongs to.
    @ObservationIgnored private var credentials: [String: String] = [:]
    @ObservationIgnored private var credentialOwners: [String: String] = [:]

    /// The `QB_SESSION` value for the session `key` ("<flowID>/<cardID>" or "<flowID>/orchestrator"): the key
    /// with a secret on the end. The helper sends it back with every request, which is how the app knows
    /// which session is really asking.
    func credential(for key: String) -> String {
        if let known = credentials[key] { return known }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let made = key + "#" + bytes.map { String(format: "%02x", $0) }.joined()
        credentials[key] = made
        credentialOwners[made] = key
        return made
    }

    private func startServer() {
        let path = socketPath
        unlink(path)
        serverTask = Task.detached {
            do {
                let listener = try NetworkListener<TCP>(
                    using: NWParametersBuilder.parameters { TCP() }.localEndpoint(.unix(path: path)))
                try await listener.run { connection in
                    // One request and one reply per connection, each a 4-byte length then JSON.
                    let header = try await connection.receive(exactly: 4)
                    let length = header.content.reduce(0) { ($0 << 8) | Int($1) }
                    guard length > 0, length < 64_000_000 else { return }
                    let body = try await connection.receive(exactly: length)
                    let reply: JSONValue
                    if let request = try? JSONDecoder().decode(WireRequest.self, from: Data(body.content)) {
                        reply = await AppServices.shared.handle(request)
                    } else {
                        reply = ["error": "unreadable request"]
                    }
                    try await connection.send(Wire.frame(reply.data()))
                }
            } catch {
                await MainActor.run { AppServices.shared.problem = "Couldn't open the app's socket: \(error.localizedDescription)" }
            }
        }
    }

    /// Answers one helper request. `session` is "<flowID>/<cardID>" or "<flowID>/orchestrator".
    func handle(_ request: WireRequest) async -> JSONValue {
        var parts = request.session.split(separator: "/", maxSplits: 1).map(String.init)
        if request.kind != "test" {
            // Who is asking comes from the secret, never from the name the request gives itself.
            guard let owner = credentialOwners[request.session] else { return fallback(for: request) }
            parts = owner.split(separator: "/", maxSplits: 1).map(String.init)
        }
        if request.kind == "test" {
            guard TestHarness.isEnabled else { return ["error": "testing is off"] }
            guard parts.count == 2, let controller = controllers[parts[0]]?.value else { return TestHarness.handleApp(request.payload) }
            return await TestHarness.handle(request.payload, controller: controller)
        }
        guard parts.count == 2, let controller = controllers[parts[0]]?.value else {
            return fallback(for: request)
        }
        let who = parts[1]
        switch request.kind {
        case "hook":
            controller.handleHook(from: who, payload: request.payload)
            return [:]
        case "route":
            let deliveries = await controller.handleRoute(from: who, answer: request.payload["answer"]?.stringValue ?? "")
            return ["deliveries": .array(deliveries.map { ["to": .string($0.to), "text": .string($0.text)] })]
        case "sent":
            controller.handleSent(from: who, results: request.payload["results"]?.arrayValue ?? [])
            return [:]
        case "may-send":
            let verdict = controller.judgeSend(from: who, to: request.payload["to"]?.stringValue ?? "")
            if let reason = verdict.refusal { return ["allowed": false, "reason": .string(reason)] }
            return ["allowed": true, "sessionId": verdict.sessionID.map(JSONValue.string) ?? .null]
        case "mcp":
            // The tools edit and run the flow, so only the orchestrator's own session gets them.
            guard who == FlowController.orchestratorKey else { return fallback(for: request) }
            return await MCPServer.handle(request.payload, host: controller) ?? .null
        default:
            return fallback(for: request)
        }
    }

    /// What to say when the flow a session belongs to isn't open.
    private func fallback(for request: WireRequest) -> JSONValue {
        switch request.kind {
        case "route": return ["deliveries": []]
        case "may-send": return ["allowed": true]
        case "mcp":
            guard let id = request.payload["id"], !id.isNull else { return .null }
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": "This flow isn't open in Queen Bee."]]
        default: return [:]
        }
    }
}

/// The strips at the canvas's left and right that floating panels sit over, in screen points.
nonisolated struct CanvasObstruction: Equatable, Sendable {
    var left: CGFloat
    var right: CGFloat
}

private struct WeakController {
    weak var value: FlowController?
    init(_ value: FlowController) { self.value = value }
}
