import Foundation

/// What the app knows about an agent's session.
public struct AgentStatus: Codable, Equatable, Sendable {
    /// starting, idle, working, needs you, failed or exited.
    public var state: String
    public var lastReply: String?

    public init(state: String, lastReply: String?) { self.state = state; self.lastReply = lastReply }
}

/// The flow as it is right now, with each agent's status keyed by card id.
public struct FlowSnapshot: Sendable {
    public var flow: Flow
    public var agents: [String: AgentStatus]
    public var isRunning: Bool
    /// The names of the project's other flows that a Flow card here may run.
    public var otherFlows: [String]
    /// How many more levels of sub-flow may sit below this flow, by the limit the person set on the flow at the top.
    public var subflowLevelsLeft: Int

    public init(flow: Flow, agents: [String: AgentStatus], isRunning: Bool, otherFlows: [String] = [], subflowLevelsLeft: Int = 3) {
        self.flow = flow; self.agents = agents; self.isRunning = isRunning; self.otherFlows = otherFlows
        self.subflowLevelsLeft = subflowLevelsLeft
    }
}

/// What the orchestrator's tools need from the app. Edits go through `mutate`, the same path the canvas uses,
/// so the canvas updates when the orchestrator changes the flow.
public protocol ToolHost: Sendable {
    func snapshot() async -> FlowSnapshot
    func mutate<T: Sendable>(_ body: @Sendable (inout Flow) throws -> T) async throws -> T
    /// Starts a run and returns a short status line.
    func runFlow(command: String?) async throws -> String
    func stopFlow() async
    func runLog() async -> [String]
}

public struct ToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name; self.description = description; self.inputSchema = inputSchema
    }
}

public struct ToolResult: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) { self.text = text; self.isError = isError }
}

/// The tools the orchestrator session builds and runs a flow with.
public enum Tools {
    public static func call(name: String, arguments: JSONValue, host: any ToolHost) async -> ToolResult {
        let arguments = Arguments(values: arguments.objectValue ?? [:])
        do {
            return ToolResult(text: try await run(name, arguments, host), isError: false)
        } catch let error as FlowError {
            return ToolResult(text: error.description, isError: true)
        } catch {
            // The host's own errors, for example from run_flow.
            return ToolResult(text: (error as? LocalizedError)?.errorDescription ?? String(describing: error), isError: true)
        }
    }

    private static func run(_ name: String, _ arguments: Arguments, _ host: any ToolHost) async throws -> String {
        switch name {
        case "get_flow":
            return describe(await host.snapshot()).text()

        case "add_card":
            let raw = try arguments.required("kind")
            guard let kind = CardKind(rawValue: raw.lowercased()) else {
                throw FlowError.invalid("Unknown card kind \"\(raw)\". Use one of: \(CardKind.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            let patch = try arguments.patch(for: kind)
            let name = try arguments.string("name")
            let card = try await host.mutate { try $0.addCard(kind: kind, name: name, patch: patch, clearOfOthers: true) }
            let outputs = ports(of: card)
            let tail = outputs.isEmpty ? "It has no outputs." : "Outputs: \(outputs.joined(separator: ", "))."
            return "Added \(card.kind.label) \"\(card.name)\" (id \(card.id)) at x \(Int(card.x)), y \(Int(card.y)), \(Int(card.width)) wide. \(tail)"

        case "update_card":
            let ref = try arguments.required("card")
            let card = try await host.mutate { flow in
                guard let current = flow.resolveCard(ref) else { throw FlowError.notFound("No card called \"\(ref)\"") }
                let patch = try arguments.patch(for: current.kind)
                if patch == CardPatch() { throw FlowError.invalid("Give at least one setting to change") }
                return try flow.updateCard(current.id, patch: patch)
            }
            return "Updated \(card.kind.label) \"\(card.name)\"."

        case "remove_card":
            let ref = try arguments.required("card")
            let (card, dropped) = try await host.mutate { flow in
                guard let card = flow.resolveCard(ref) else { throw FlowError.notFound("No card called \"\(ref)\"") }
                let before = flow.links.count
                try flow.removeCard(card.id)
                return (card, before - flow.links.count)
            }
            return "Removed \(card.kind.label) \"\(card.name)\" and \(dropped) \(dropped == 1 ? "link" : "links")."

        case "add_link":
            let from = try arguments.required("from")
            let to = try arguments.required("to")
            let port = try arguments.string("port")
            let passes = try arguments.int("max_passes")
            let (link, source, target) = try await host.mutate { flow in
                let link = try flow.addLink(from: from, port: port, to: to, maxPasses: passes)
                return (link, flow.card(link.from)?.name ?? from, flow.card(link.to)?.name ?? to)
            }
            return "Linked \"\(source)\" (\(link.port)) to \"\(target)\" (link id \(link.id), max passes \(link.maxPasses))."

        case "remove_link":
            let id = try arguments.required("link")
            try await host.mutate { try $0.removeLink(id) }
            return "Removed link \(id)."

        case "run_flow":
            return try await host.runFlow(command: try arguments.string("command"))

        case "stop_flow":
            guard await host.snapshot().isRunning else { return "No run is going." }
            await host.stopFlow()
            return "Stopped the run."

        case "read_agent":
            let ref = try arguments.required("card")
            let snapshot = await host.snapshot()
            guard let card = snapshot.flow.resolveCard(ref) else { throw FlowError.notFound("No card called \"\(ref)\"") }
            guard card.kind == .agent else {
                throw FlowError.invalid("\"\(card.name)\" is a \(card.kind.label) card, not an agent")
            }
            let status = snapshot.agents[card.id]
            let state = "\(card.name) is \(status?.state ?? "not started")."
            guard let reply = status?.lastReply, !reply.isEmpty else { return "\(state) It has not replied yet." }
            return "\(state) Its last reply:\n\n\(reply)"

        case "get_run_log":
            let lines = await host.runLog()
            return lines.isEmpty ? "No run has been logged yet." : lines.joined(separator: "\n")

        default:
            throw FlowError.notFound("Unknown tool \"\(name)\"")
        }
    }

    // MARK: get_flow

    /// Built field by field rather than encoded from `Flow`, so session ids can never leak into it.
    private static func describe(_ snapshot: FlowSnapshot) -> JSONValue {
        let flow = snapshot.flow
        let found = warnings(for: flow)
        func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }

        let cards = flow.cards.map { card -> JSONValue in
            var fields: [String: JSONValue] = [
                "id": .string(card.id), "kind": .string(card.kind.rawValue), "name": .string(card.name),
                "x": .number(card.x), "y": .number(card.y), "width": .number(card.width), "height": .number(card.height),
                "outputs": .array(ports(of: card).map(JSONValue.string)),
            ]
            switch card.kind {
            case .agent:
                fields["instructions"] = text(card.instructions)
                fields["model"] = text(card.model)
                fields["effort"] = text(card.effort)
                fields["permission_mode"] = text(card.permissionMode)
                fields["cwd"] = text(card.cwd)
                let status = snapshot.agents[card.id]
                fields["state"] = .string(status?.state ?? "not started")
                fields["has_last_reply"] = .bool(!(status?.lastReply ?? "").isEmpty)
            case .start, .script:
                fields["command"] = text(card.command)
            case .ifElse, .loop:
                fields["check"] = text(card.check?.rawValue)
                fields["value"] = text(card.value)
                if card.kind == .loop { fields["max_tries"] = card.maxTries.map { .number(Double($0)) } ?? .null }
            case .switchCard:
                fields["branches"] = .array((card.branches ?? []).map(JSONValue.string))
            case .prompt:
                fields["template"] = text(card.template)
            case .end:
                fields["save_to"] = text(card.saveTo)
            case .note, .approval:
                fields["text"] = text(card.text)
            case .flow:
                fields["flow"] = text(card.flowRef)
            case .and, .or:
                break
            }
            if let warning = found[card.id] { fields["warning"] = .string(warning) }
            return .object(fields)
        }

        let links = flow.links.map { link -> JSONValue in
            [
                "id": .string(link.id),
                "from": .string(flow.card(link.from)?.name ?? link.from),
                "port": .string(link.port),
                "to": .string(flow.card(link.to)?.name ?? link.to),
                "max_passes": .number(Double(link.maxPasses)),
            ]
        }

        return ["name": .string(flow.name), "is_running": .bool(snapshot.isRunning), "cards": .array(cards), "links": .array(links),
                "other_flows": .array(snapshot.otherFlows.map(JSONValue.string)),
                "sub_flow_levels_left": .number(Double(max(0, snapshot.subflowLevelsLeft)))]
    }

    // MARK: Definitions

    public static let definitions: [ToolDefinition] = [
        ToolDefinition(
            name: "get_flow",
            description: """
            Read the flow on the canvas: its cards, their settings and positions, each card's outputs, each agent's \
            state, the links between cards, and whether a run is going. A card with a "warning" is wired in a way \
            that would leave a run stuck. Call this before editing, because the person can change the canvas by hand.
            """,
            inputSchema: schema([:])),
        ToolDefinition(
            name: "add_card",
            description: """
            Add a card to the flow. The kinds, with the names of their outputs:
            - agent: a live Claude Code session that does work. Output: out (its reply when a turn ends).
            - start: holds the command a run begins with. Output: out. Takes no input.
            - if: checks the message. Outputs: yes, no.
            - switch: Claude picks the one branch that fits the message. Outputs: one per branch name, plus other.
            - and: waits for a message from every card linked into it, then passes them on together. Output: out.
            - or: passes on the first message that reaches it in a run and drops later ones. Output: out.
            - prompt: rewrites the message from a template. Output: out.
            - loop: checks the message. Outputs: done (the check holds, or max_tries is used up) and again.
            - end: records the final answer and saves it to a file if save_to is set. No outputs.
            - note: text for people. Carries no messages and cannot be linked.
            - approval: holds the message until the person approves or rejects it. They can edit it first. \
            Outputs: approved, rejected. Put one before anything that can't be taken back, such as sending an email.
            - flow: runs another flow in this project as one step, giving it the message as its command. \
            Outputs: done (with that flow's final answer) and fail. Set "flow" to the name of one of the \
            other_flows that get_flow lists. You cannot create a flow: if the one you need isn't listed, ask the \
            person to double-click the Flow card, which makes a new sub-flow and opens it. Never write flow files yourself. \
            Sub-flows only nest as deep as the person allows on the flow at the top: get_flow gives \
            sub_flow_levels_left for this flow. At 0 it can't have a Flow card. other_flows only lists flows that \
            fit, and an edit that would go deeper is refused. Don't try to work round it.
            - script: runs a shell command in the project folder, with the message on its standard input and in \
            $QB_MESSAGE. Outputs: pass (it exited with 0) and fail. What it printed is passed on. The person is \
            asked to allow a command they did not type themselves the first time a run reaches it.
            Only pass the settings that belong to the kind. Leave out x and y to place the card to the right of the \
            others, which is usually what you want. An agent card is 560 points wide and 380 tall, and the other \
            cards are about 240 by 100, so if you do give positions leave 60 points between cards. A card that \
            would land on another is moved right until it is clear. Returns the new card's id, position and \
            outputs. Then connect it with add_link.
            """,
            inputSchema: schema(
                ["kind": ["type": "string", "enum": .array(CardKind.allCases.map { .string($0.rawValue) })],
                 "name": ["type": "string", "description": "Shown on the card and used to refer to it. Must be unique in the flow. Defaults to the kind's label."],
                 "x": ["type": "number", "description": "Left edge on the canvas, in points."],
                 "y": ["type": "number", "description": "Top edge on the canvas, in points."]],
                required: ["kind"], withSettings: true)),
        ToolDefinition(
            name: "update_card",
            description: """
            Change a card's name, position, size or settings. Pass only what should change. A setting that does not \
            belong to the card's kind is refused. Changing a switch's branches removes links from branches that no \
            longer exist. New agent settings (instructions, model, effort, permission_mode, cwd) apply the next \
            time that agent's session starts.
            """,
            inputSchema: schema(
                ["card": cardProperty,
                 "name": ["type": "string", "description": "A new name. Must be unique in the flow."],
                 "x": ["type": "number"], "y": ["type": "number"],
                 "width": ["type": "number"], "height": ["type": "number"]],
                required: ["card"], withSettings: true)),
        ToolDefinition(
            name: "remove_card",
            description: "Remove a card and every link into and out of it.",
            inputSchema: schema(["card": cardProperty], required: ["card"])),
        ToolDefinition(
            name: "add_link",
            description: """
            Link one card's output to another card's input, so messages travel that way during a run. Output names: \
            agent, start, and, or and prompt cards have out; if has yes and no; loop has done and again; switch has \
            one per branch plus other. Leave port out to use the card's first output. Start and note cards take no \
            input, end and note cards have no outputs, and a card cannot link to itself. max_passes is how many \
            times the link may fire in one run, which is what makes a loop between cards end.
            """,
            inputSchema: schema(
                ["from": ["type": "string", "description": "The card the link leaves: its name or id."],
                 "to": ["type": "string", "description": "The card the link goes to: its name or id."],
                 "port": ["type": "string", "description": "Which output of the from card. Defaults to its first."],
                 "max_passes": ["type": "integer", "minimum": 1, "maximum": 50, "description": "Defaults to 3."]],
                required: ["from", "to"])),
        ToolDefinition(
            name: "remove_link",
            description: "Remove a link by its id. Link ids are listed by get_flow and returned by add_link.",
            inputSchema: schema(["link": ["type": "string", "description": "The link's id."]], required: ["link"])),
        ToolDefinition(
            name: "run_flow",
            description: """
            Start a run from the flow's Start card. The command goes to every card linked from Start, and each \
            agent's reply then travels its links. Pass command to use it in place of the Start card's own command \
            for this run. Only one run can go at a time. This returns once the run has started, not when it ends: \
            follow it with get_run_log and read_agent.
            """,
            inputSchema: schema(["command": ["type": "string", "description": "What to send in place of the Start card's command."]])),
        ToolDefinition(
            name: "stop_flow",
            description: "Stop the run that is going. Agents finish the turn they are on, but their replies are no longer passed along.",
            inputSchema: schema([:])),
        ToolDefinition(
            name: "read_agent",
            description: "Read an agent card's state (starting, idle, working, needs you, failed or exited) and the full text of its last reply.",
            inputSchema: schema(["card": cardProperty], required: ["card"])),
        ToolDefinition(
            name: "get_run_log",
            description: "Read the log of the latest run: each hand-off between cards, each If, Switch and Loop decision, and why the run stopped.",
            inputSchema: schema([:])),
    ]

    private static let cardProperty: JSONValue = ["type": "string", "description": "The card's name or id."]

    private static let settingProperties: [String: JSONValue] = [
        "instructions": ["type": "string", "description": "agent: a standing brief added to the session's system prompt."],
        "model": ["type": "string", "description": "agent: a model alias or id, such as opus, sonnet or haiku. An empty string goes back to the person's default."],
        "effort": ["type": "string", "description": "agent: low, medium, high, xhigh or max. An empty string goes back to the model's default."],
        "permission_mode": ["type": "string", "description": "agent: manual, acceptEdits, plan or auto. An empty string goes back to the person's default."],
        "cwd": ["type": "string", "description": "agent: the folder the session works in. An empty string goes back to the project folder."],
        "command": ["type": "string", "description": "start: the message a run begins with. script: the shell command to run."],
        "check": ["type": "string", "enum": .array(CheckKind.allCases.map { .string($0.rawValue) }),
                  "description": "if, loop: how value is tested. judge: Claude decides whether value, a plain-English statement, is true of the message. contains and not-contains: the message has or lacks the text in value, ignoring case. regex: the message matches the pattern in value."],
        "value": ["type": "string", "description": "if, loop: the statement, text or pattern the check tests."],
        "max_tries": ["type": "integer", "minimum": 1, "maximum": 50, "description": "loop: tries before it gives up and takes done. Defaults to 3."],
        "branches": ["type": "array", "items": ["type": "string"], "description": "switch: the branch names. Each one becomes an output."],
        "template": ["type": "string", "description": "prompt: the rewritten message. {{message}} becomes the incoming message and {{from}} the name of the agent it came from."],
        "save_to": ["type": "string", "description": "end: a file to save the final answer to, relative to the project folder."],
        "text": ["type": "string", "description": "note: the note's text. approval: what the person should check before approving."],
        "flow": ["type": "string", "description": "flow: the name of the flow to run, one of other_flows from get_flow."],
    ]

    private static func schema(_ properties: [String: JSONValue], required: [String] = [], withSettings: Bool = false) -> JSONValue {
        let all = withSettings ? properties.merging(settingProperties) { own, _ in own } : properties
        return ["type": "object", "properties": .object(all), "required": .array(required.map(JSONValue.string))]
    }
}

/// A tool call's arguments, read with errors the orchestrator can act on.
private struct Arguments: Sendable {
    let values: [String: JSONValue]

    /// Which kinds each setting belongs to. A setting passed for another kind is refused rather than dropped,
    /// so the orchestrator finds out instead of believing the change was made.
    private static let settings: [(key: String, kinds: Set<CardKind>)] = [
        ("instructions", [.agent]), ("model", [.agent]), ("effort", [.agent]), ("permission_mode", [.agent]), ("cwd", [.agent]),
        ("command", [.start, .script]), ("check", [.ifElse, .loop]), ("value", [.ifElse, .loop]), ("max_tries", [.loop]),
        ("branches", [.switchCard]), ("template", [.prompt]), ("save_to", [.end]), ("text", [.note, .approval]), ("flow", [.flow]),
    ]

    private func value(_ key: String) -> JSONValue? {
        guard let value = values[key], !value.isNull else { return nil }
        return value
    }

    func string(_ key: String) throws -> String? {
        guard let value = value(key) else { return nil }
        guard let text = value.stringValue else { throw FlowError.invalid("\"\(key)\" must be text") }
        return text
    }

    func required(_ key: String) throws -> String {
        guard let text = try string(key), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlowError.invalid("\"\(key)\" is required")
        }
        return text
    }

    func number(_ key: String) throws -> Double? {
        guard let value = value(key) else { return nil }
        // Models sometimes quote numbers.
        if let number = value.doubleValue ?? value.stringValue.flatMap(Double.init), number.isFinite { return number }
        throw FlowError.invalid("\"\(key)\" must be a number")
    }

    func int(_ key: String) throws -> Int? {
        guard let number = try number(key) else { return nil }
        guard abs(number) < 1e9 else { throw FlowError.invalid("\"\(key)\" is out of range") }
        return Int(number)
    }

    func strings(_ key: String) throws -> [String]? {
        guard let value = value(key) else { return nil }
        guard let items = value.arrayValue, items.allSatisfy({ $0.stringValue != nil }) else {
            throw FlowError.invalid("\"\(key)\" must be a list of text")
        }
        return items.compactMap(\.stringValue)
    }

    /// The name, position, size and settings in the arguments, as a patch for a card of `kind`.
    func patch(for kind: CardKind) throws -> CardPatch {
        for setting in Self.settings where value(setting.key) != nil && !setting.kinds.contains(kind) {
            let article = "aeiou".contains(kind.label.lowercased().prefix(1)) ? "An" : "A"
            throw FlowError.invalid("\(article) \(kind.label) card has no \"\(setting.key)\" setting")
        }
        var patch = CardPatch()
        patch.name = try string("name")
        patch.x = try number("x")
        patch.y = try number("y")
        patch.width = try number("width")
        patch.height = try number("height")
        patch.instructions = try string("instructions")
        patch.model = try string("model")
        patch.effort = try string("effort")
        patch.permissionMode = try string("permission_mode")
        patch.cwd = try string("cwd")
        patch.command = try string("command")
        patch.flowRef = try string("flow")
        if let raw = try string("check") {
            guard let check = CheckKind(rawValue: raw.lowercased()) else {
                throw FlowError.invalid("Unknown check \"\(raw)\". Use one of: \(CheckKind.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            patch.check = check
        }
        patch.value = try string("value")
        patch.maxTries = try int("max_tries")
        patch.branches = try strings("branches")
        patch.template = try string("template")
        patch.saveTo = try string("save_to")
        patch.text = try string("text")
        return patch
    }
}
