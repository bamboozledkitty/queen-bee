import AppKit
import QueenBeeCore

/// A back door for automated checks, open only when the app is launched with `--testing`.
/// A script asks what the app is showing and does what a person would do with the mouse
/// and keyboard, over the same socket the helper uses. `scripts/e2e.py` is that script.
enum TestHarness {
    /// Always off in a release build, so a copy people download has no back door.
    static var isEnabled: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--testing")
        #else
        false
        #endif
    }

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
        case "edgeLink":
            // A link dragged from a card to the canvas's edge, and held there until the card
            // it is for pans into reach.
            guard let cardID, let target = payload["to"]?.stringValue.flatMap({ controller.flow.resolveCard($0)?.id }) else { return ["error": "edgeLink needs card and to"] }
            await controller.canvas?.testEdgeLink(from: cardID, port: payload["port"]?.stringValue ?? "out", to: target,
                                                  edge: payload["edge"]?.stringValue ?? "right")
            return [:]
        case "zoom":
            if let to = payload["to"]?.doubleValue { controller.canvas?.testSetMagnification(to) }
            return [:]
        case "fit":
            // The zoom control's fit button, or a double-click on a card's title.
            if let cardID { controller.canvas?.zoom(toCard: cardID) } else { controller.canvas?.zoomToFit() }
            return [:]
        case "pick":
            // A click on a card's title, or on bare canvas when no card is named.
            controller.select(cardID.map { .card($0) } ?? .none)
            return [:]
        case "add":
            guard let kind = payload["kind"]?.stringValue.flatMap(CardKind.init(rawValue:)) else { return ["error": "add needs kind"] }
            controller.addCard(kind)
            return [:]
        case "hold":
            // Answers the first held message the way the settings panel's buttons do.
            guard let hold = controller.holds.first(where: { cardID == nil || $0.cardID == cardID }) else { return ["error": "nothing is held"] }
            switch payload["answer"]?.stringValue {
            case "approve": controller.approve(hold.id, text: payload["text"]?.stringValue ?? hold.text)
            case "reject": controller.reject(hold.id)
            case "allow": controller.allowScript(hold.id)
            case "refuse": controller.refuseScript(hold.id)
            default: return ["error": "hold needs answer"]
            }
            return [:]
        case "script":
            guard let cardID, let command = payload["command"]?.stringValue else { return ["error": "script needs card and command"] }
            controller.setScriptCommand(cardID, command)
            return [:]
        case "runFrom":
            guard let cardID, let message = payload["message"]?.stringValue else { return ["error": "runFrom needs card and message"] }
            return ["status": .string(await controller.run(from: cardID, message: message))]
        case "viewRun":
            controller.view(run: payload["run"]?.stringValue)
            return [:]
        case "showCost":
            controller.showsCost = true
            return [:]
        case "saveRole":
            guard let cardID else { return ["error": "saveRole needs card"] }
            controller.saveRole(fromCard: cardID)
            return ["roles": .array(AppServices.shared.roles.map { .string($0.name) })]
        case "addRole":
            guard let role = AppServices.shared.roles.first(where: { $0.name == payload["role"]?.stringValue }) else { return ["error": "no such role"] }
            controller.addCard(.agent, role: role)
            return [:]
        case "trigger":
            // Sets a Start card to run every `minutes`, the way the settings panel does.
            guard let cardID else { return ["error": "trigger needs card"] }
            controller.setTrigger(payload["minutes"]?.doubleValue.map { Trigger(kind: .interval, minutes: Int($0)) }
                                  ?? payload["path"]?.stringValue.map { Trigger(kind: .file, path: $0) }, onCard: cardID)
            return ["next": .array(controller.nextFires.values.map { .number($0.timeIntervalSinceNow) })]
        case "pickMany":
            let ids = (payload["cards"]?.arrayValue ?? []).compactMap { $0.stringValue }.compactMap { controller.flow.resolveCard($0)?.id }
            controller.select(.of(Set(ids)))
            return [:]
        case "openSub":
            guard let cardID else { return ["error": "openSub needs card"] }
            controller.openSubflow(forCard: cardID)
            return ["now": .string(AppServices.shared.current?.flow.name ?? ""), "trail": .number(Double(AppServices.shared.flowTrail.count))]
        case "find":
            AppServices.shared.showsFind = true
            return [:]
        case "tidy":
            controller.tidy()
            return [:]
        case "group":
            controller.groupSelection()
            return [:]
        case "fold":
            guard let group = controller.selectedGroup else { return ["error": "no group is selected"] }
            controller.setFolded(payload["folded"]?.boolValue ?? true, group: group.id)
            return [:]
        case "selectAll":
            controller.selectAll()
            return [:]
        case "duplicate":
            controller.duplicateSelection()
            return [:]
        case "delete":
            controller.deleteSelection()
            return [:]
        case "nudge":
            controller.nudgeSelection(dx: payload["dx"]?.doubleValue ?? 0, dy: payload["dy"]?.doubleValue ?? 0)
            return [:]
        case "undo":
            controller.undo()
            return [:]
        case "redo":
            controller.redo()
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
            "cards": .array(controller.flow.cards.map { ["name": .string($0.name), "x": .number($0.x), "y": .number($0.y)] }),
            "links": .number(Double(controller.flow.links.count)),
            "cost": .number(controller.totalUsage.cost),
            "runs": .array(controller.runs.map { ["id": .string($0.id), "outcome": .string($0.outcome.rawValue), "command": .string($0.command)] }),
            "viewedRun": controller.viewedRunID.map(JSONValue.string) ?? .null,
            "messages": .number(Double(controller.messages.values.reduce(0) { $0 + $1.count })),
            "holds": .array(controller.holds.map { ["card": .string(controller.flow.card($0.cardID)?.name ?? ""), "text": .string($0.text), "needsAllow": .bool($0.needsAllow)] }),
            "selected": .array(controller.flow.cards.filter { controller.selection.cardIDs.contains($0.id) }.map { .string($0.name) }),
            "undo": .string(controller.undoManager.canUndo ? controller.undoManager.undoActionName : ""),
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
