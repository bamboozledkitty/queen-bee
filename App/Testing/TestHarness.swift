import AppKit
import QueenBeeCore

/// A back door for automated checks, open only when the app is launched with `--testing`.
/// A script asks what the app is showing and does what a person would do with the mouse
/// and keyboard, over the same socket the helper uses. `scripts/e2e.py` is that script.
enum TestHarness {
    static var isEnabled: Bool { CommandLine.arguments.contains("--testing") }

    /// Questions about the app as a whole, for when no flow is involved.
    static func handleApp(_ payload: JSONValue) -> JSONValue {
        let services = AppServices.shared
        return [
            "problem": services.problem.map(JSONValue.string) ?? .null,
            "environmentReady": .bool(services.environment != nil),
            "claude": services.environment?.claude.map(JSONValue.string) ?? .null,
            "windows": .number(Double(NSApp.windows.filter(\.isVisible).count)),
            "allWindows": .array(NSApp.windows.map { .string("\(type(of: $0)) visible=\($0.isVisible) title=\($0.title)") }),
            "projects": .array(services.openProjectPaths.map(JSONValue.string)),
            "arguments": .array(CommandLine.arguments.dropFirst().map(JSONValue.string)),
        ]
    }

    static func handle(_ payload: JSONValue, controller: FlowController) async -> JSONValue {
        let cardRef = payload["card"]?.stringValue
        let cardID = cardRef == FlowController.orchestratorKey ? cardRef : cardRef.flatMap { controller.flow.resolveCard($0)?.id }

        switch payload["op"]?.stringValue {
        case "state":
            return state(of: controller)
        case "select":
            AppServices.shared.selectedFlowID = controller.flow.id
            return [:]
        case "close":
            controller.shutDown()
            return [:]
        case "run":
            return ["status": .string(await controller.run(command: payload["command"]?.stringValue))]
        case "stop":
            await controller.stop()
            return [:]
        case "type":
            guard let cardID, let text = payload["text"]?.stringValue else { return ["error": "type needs card and text"] }
            controller.session(forCard: cardID).send(text)
            return [:]
        case "kill":
            // What a crash looks like from outside: the process is gone without a goodbye.
            guard let cardID, let pid = controller.sessions[cardID]?.view.process?.shellPid, pid > 0 else { return ["error": "no process"] }
            kill(pid, SIGKILL)
            return ["pid": .number(Double(pid))]
        case "restart":
            guard let cardID else { return ["error": "restart needs card"] }
            controller.startSession(forCard: cardID)
            return [:]
        case "edit":
            // Changes a card's settings the way the settings panel does.
            guard let cardID else { return ["error": "edit needs card"] }
            var patch = CardPatch()
            patch.instructions = payload["instructions"]?.stringValue
            patch.model = payload["model"]?.stringValue
            patch.effort = payload["effort"]?.stringValue
            controller.update(cardID, patch)
            return [:]
        case "revert":
            guard let cardID else { return ["error": "revert needs card"] }
            controller.revertSettings(forCard: cardID)
            return [:]
        case "focus":
            controller.canvas?.testFocus(cardID: cardID)
            return [:]
        case "scroll":
            let how = controller.canvas?.testScroll(cardID: cardID, dy: payload["dy"]?.doubleValue ?? -120,
                                                    mode: payload["mode"]?.stringValue ?? "direct")
            return ["posted": how.map(JSONValue.string) ?? .null]
        case "zoom":
            if let to = payload["to"]?.doubleValue { controller.canvas?.testSetMagnification(to) }
            return [:]
        default:
            return ["error": "unknown op"]
        }
    }

    private static func state(of controller: FlowController) -> JSONValue {
        var sessions: [String: JSONValue] = [:]
        for card in controller.flow.cards where card.kind == .agent {
            var described = describe(controller.sessions[card.id]).objectValue ?? [:]
            described["awaitingRestart"] = .array(controller.settingsAwaitingRestart(forCard: card.id).map(JSONValue.string))
            described["instructions"] = .string(card.instructions ?? "")
            described["model"] = card.model.map(JSONValue.string) ?? .null
            described["effort"] = card.effort.map(JSONValue.string) ?? .null
            sessions[card.name] = .object(described)
        }
        var results: [String: JSONValue] = [:]
        for (id, text) in controller.results { results[controller.flow.card(id)?.name ?? id] = .string(text) }
        var marks: [String: JSONValue] = [:]
        for (id, mark) in controller.marks {
            var ports: [String: JSONValue] = [:]
            for (port, count) in mark.ports { ports[port] = .number(Double(count)) }
            marks[controller.flow.card(id)?.name ?? id] = [
                "arrivals": .number(Double(mark.arrivals)), "passes": .number(Double(mark.passes)), "ports": .object(ports),
                "lastPort": mark.lastPort.map(JSONValue.string) ?? .null, "holding": .number(Double(mark.holding)), "failed": .bool(mark.failed),
            ]
        }
        return [
            "name": .string(controller.flow.name),
            "isRunning": .bool(controller.isRunning),
            "log": .array(controller.log.map { .string($0.text) }),
            "results": .object(results),
            "sessions": .object(sessions),
            "orchestrator": describe(controller.sessions[FlowController.orchestratorKey]),
            "banner": controller.banner.map(JSONValue.string) ?? .null,
            "problem": AppServices.shared.problem.map(JSONValue.string) ?? .null,
            "marks": .object(marks),
            "linkPasses": .array(controller.flow.links.map { .number(Double(controller.linkPasses[$0.id] ?? 0)) }),
            "liveLinks": .number(Double(controller.liveLinkIDs.count)),
            "handOffs": .number(Double(controller.handOffs)),
            "activity": .string("\(controller.activity)"),
            "focusedCard": controller.focusedCardID.flatMap { controller.flow.card($0)?.name }.map(JSONValue.string) ?? .null,
            "canvas": controller.canvas?.testViewState ?? .null,
        ]
    }

    private static func describe(_ session: TerminalSession?) -> JSONValue {
        guard let session else { return ["state": "notStarted", "lastReply": .null] }
        return [
            "state": .string(session.state.rawValue),
            "lastReply": session.lastReply.map(JSONValue.string) ?? .null,
            "scrollPosition": .number(session.view.scrollPosition),
            "canScroll": .bool(session.view.canScroll),
        ]
    }
}
