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

    @ObservationIgnored private var controllers: [String: WeakController] = [:]
    @ObservationIgnored private var projects: [URL: ProjectModel] = [:]
    @ObservationIgnored private var serverTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = base.appendingPathComponent("QueenBee", isDirectory: true)
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
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        installPlugin()
        startServer()
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

    func project(for root: URL) -> ProjectModel {
        let key = root.standardizedFileURL
        if let existing = projects[key] { return existing }
        let project = ProjectModel(root: key)
        projects[key] = project
        return project
    }

    func close(_ project: ProjectModel) {
        projects[project.root] = nil
    }

    func register(_ controller: FlowController) {
        controllers[controller.flow.id] = WeakController(controller)
    }

    func unregister(flowID: String) {
        controllers[flowID] = nil
    }

    // MARK: Socket

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
        let parts = request.session.split(separator: "/", maxSplits: 1).map(String.init)
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
            if let reason = controller.refusal(from: who, to: request.payload["to"]?.stringValue ?? "") {
                return ["allowed": false, "reason": .string(reason)]
            }
            return ["allowed": true]
        case "mcp":
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

private struct WeakController {
    weak var value: FlowController?
    init(_ value: FlowController) { self.value = value }
}
