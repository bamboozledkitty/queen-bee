import Foundation

/// How far a run has got, for the progress pill and its line of stops.
///
/// Only cards that take time count: agents, Approval, Script, Flow and Delay cards. Logic cards are over in a moment, so
/// counting them would make the number jump. The number is what is done over what is done plus what is left, and
/// what is left is the longest chain of time-taking cards from where the run is now to the end of the flow, with
/// the links that loop back left out. That way a branch an If doesn't take never holds the number down, and a
/// Loop going round again never takes it back: what it shows only goes up while a run is going, and it reaches
/// 100% only when a message has reached an End.
public struct RunProgress: Equatable, Sendable {
    /// What a stop on the line is doing.
    public enum StopState: String, Equatable, Sendable {
        /// The run has passed through it, and nothing still to come leads back to it.
        case done
        /// The run is at it now.
        case live
        /// The run is at it and waiting for the person.
        case needsYou
        /// The run stopped here.
        case failed
        /// The run ended while it was still here, without anything going wrong here: it was stopped, or it ended
        /// somewhere else first.
        case endedHere
        /// Still to come.
        case notYet
        /// The run didn't go this way, and can't from where it is.
        case skipped
    }

    /// The Loop card that sends a message back to a stop.
    public struct LoopBack: Equatable, Sendable {
        public var loopCardID: String
        /// The try under way, counting from 1, while the loop is part-way through its tries. Nil otherwise.
        public var currentTry: Int?
        public var mostTries: Int
    }

    public struct Stop: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let kind: CardKind
        public var state: StopState
        /// How far the For each it sits in has got, while it is going through its items.
        public var items: RunSnapshot.Items?
        /// A Loop card that sends the message back here.
        public var loopBack: LoopBack?
        /// For a Flow card whose flow is running: how far that run has got, from 0 to 1.
        public var inner: Double?

        /// The run got here: it is here now, has been, or ended here.
        public var isReached: Bool { state != .notYet && state != .skipped }
    }

    /// Why the person is needed at a card.
    public enum Need: Equatable, Sendable {
        /// An Approval card is waiting for an answer.
        case approval
        /// A Script card's command hasn't been allowed yet.
        case allowCommand
        /// An agent asked a question and is waiting for the answer.
        case question
        /// An agent's session is waiting on the person some other way, such as asking to use a tool.
        case session
    }

    /// The one line that says where the run is.
    public struct Headline: Equatable, Sendable {
        public enum Tone: String, Equatable, Sendable { case working, needsYou, failed, finished, stopped }
        public var tone: Tone
        public var text: String
        /// The card the line is about, for saying how long it has been at it and for going to it.
        public var cardID: String?
    }

    /// From 0 to 1.
    public var fraction: Double
    public var stops: [Stop]
    public var headline: Headline

    /// The fraction as a whole percentage, never 100 until the run has really finished.
    public var percent: Int {
        let whole = Int((fraction * 100).rounded(.down))
        return fraction >= 1 ? 100 : min(whole, 99)
    }

    /// Where a run stands.
    /// - Parameters:
    ///   - marks: where the run has been, card by card.
    ///   - snapshot: the engine's last word on the run, nil before it has said anything.
    ///   - inner: for each Flow card whose flow is running, how far that run has got, from 0 to 1.
    ///   - needs: the cards waiting for the person, and why.
    ///   - ending: how the run ended, nil while it is going.
    ///   - shownBefore: the fraction last shown for this run, so the number never goes back while it is going.
    ///   - endedAt: once the run has ended, the cards it was still at when it did.
    public init(flow: Flow, marks: [String: RunMark], snapshot: RunSnapshot?, inner: [String: Double] = [:],
                needs: [String: Need] = [:], ending: RunEnding? = nil, shownBefore: Double = 0, endedAt: Set<String> = []) {
        let graph = Graph(flow)
        let running = ending == nil
        let failedIDs = Set(marks.filter { $0.value.failed }.map(\.key))
        let live = running ? Set((snapshot?.waitingOn ?? []) + (snapshot?.holding ?? [])) : []
        let active = running ? (snapshot?.items ?? [:]) : [:]
        func visited(_ id: String) -> Bool { (marks[id]?.arrivals ?? 0) > 0 || (marks[id]?.passes ?? 0) > 0 }

        // The For each cards going through their items, outermost first: a card in the body of two counts by the outer one.
        let activeEach = graph.order.filter { active[$0] != nil }
        func enclosing(_ id: String) -> String? { activeEach.first { graph.body(of: $0).contains(id) } }

        // Where the run is: the cards at work, with one inside a For each that is going standing for the For each.
        var frontier: [String] = []
        for id in graph.order where live.contains(id) || active[id] != nil {
            let at = enclosing(id) ?? id
            if !frontier.contains(at) { frontier.append(at) }
        }
        let ahead = graph.reachable(from: frontier)
        // Once it has ended, what lay ahead of where it was is still to come, not a way it didn't go.
        let endedAt = running ? [] : endedAt.subtracting(failedIDs)
        let leftAhead = graph.reachable(from: endedAt.sorted())

        func completion(_ id: String) -> Double {
            guard let card = flow.card(id), Self.takesTime(card.kind) else { return 0 }
            if let each = enclosing(id), let items = active[each], items.count > 0 {
                let own = live.contains(id) && card.kind == .flow ? (inner[id] ?? 0) : 0
                return min(1, (Double(items.current) + own) / Double(items.count))
            }
            if live.contains(id) { return card.kind == .flow ? min(1, max(0, inner[id] ?? 0)) : 0 }
            if ahead.contains(id) { return 0 }
            return visited(id) ? 1 : 0
        }

        // What is left from a card: its own share still to do, then the longest way on. A For each does its body and
        // then goes on by Done, so both count.
        var left: [String: Double] = [:]
        for id in graph.order.reversed() {
            let own = 1 - completion(id)
            let weight = flow.card(id).map { Self.takesTime($0.kind) } == true ? own : 0
            let next = graph.next[id] ?? []
            if flow.card(id)?.kind == .forEach {
                let body = next.filter { $0.port == "each" }.map { left[$0.to] ?? 0 }.max() ?? 0
                let onward = next.filter { $0.port != "each" }.map { left[$0.to] ?? 0 }.max() ?? 0
                left[id] = weight + body + onward
            } else {
                left[id] = weight + (next.map { left[$0.to] ?? 0 }.max() ?? 0)
            }
        }
        let timed = flow.cards.filter { Self.takesTime($0.kind) }
        let done = timed.map { completion($0.id) }.reduce(0, +)
        let remaining = frontier.map { left[$0] ?? 0 }.max() ?? 0
        let raw = done + remaining > 0 ? done / (done + remaining) : 0

        let answered = flow.cards.contains { $0.kind == .end && visited($0.id) }
        switch ending {
        case nil: fraction = min(max(raw, shownBefore), 0.99)
        case .some(let ending) where answered && (ending == .finishedWithAnswer || ending == .gaveUp): fraction = 1
        // A run that ended any other way stays where it got to, even at 0. Nothing is ahead of it any more, so
        // working it out again would say it was all but done.
        case .some: fraction = min(shownBefore, 0.99)
        }

        // The stops, in the order the run reaches them, then top to bottom as they sit on the canvas.
        let loops = Self.loopBacks(flow, graph: graph, snapshot: running ? snapshot : nil)
        let shown = flow.cards.filter { Self.takesTime($0.kind) || $0.kind == .end }
        stops = shown.sorted {
            let a = graph.depth[$0.id] ?? 0, b = graph.depth[$1.id] ?? 0
            return a != b ? a < b : ($0.y, $0.x) < ($1.y, $1.x)
        }.map { card in
            let id = card.id
            let state: StopState
            if failedIDs.contains(id) { state = .failed }
            else if endedAt.contains(id) { state = .endedHere }
            else if leftAhead.contains(id), !visited(id) { state = .notYet }
            else if live.contains(id) { state = needs[id] != nil ? .needsYou : .live }
            else if needs[id] == .question { state = .needsYou }
            else if let each = enclosing(id), let items = active[each] { state = items.current > 0 && visited(id) ? .done : .notYet }
            else if ahead.contains(id) { state = .notYet }
            else if visited(id) { state = .done }
            else { state = .skipped }
            return Stop(id: id, name: card.name, kind: card.kind, state: state,
                        items: enclosing(id).flatMap { active[$0] }, loopBack: loops[id],
                        inner: live.contains(id) && card.kind == .flow ? inner[id] : nil)
        }

        headline = Self.headline(flow: flow, stops: stops, needs: needs, ending: ending, failed: failedIDs, answered: answered)
    }

    /// Whether a kind of card takes time, and so counts towards how far a run has got.
    public static func takesTime(_ kind: CardKind) -> Bool {
        switch kind {
        case .agent, .approval, .script, .flow, .delay: true
        default: false
        }
    }

    // MARK: Loops

    /// For each stop a Loop card sends its message back to, that loop: the first card that takes time along its
    /// Again links.
    private static func loopBacks(_ flow: Flow, graph: Graph, snapshot: RunSnapshot?) -> [String: LoopBack] {
        var found: [String: LoopBack] = [:]
        for loop in flow.cards where loop.kind == .loop {
            let failed = snapshot?.tries[loop.id]
            let back = LoopBack(loopCardID: loop.id, currentTry: failed.map { $0 + 1 },
                                mostTries: max(loop.maxTries ?? Engine.defaultMaxTries, 1))
            var seen: Set<String> = [], next = flow.links(from: loop.id, port: "again").map(\.to)
            while let id = next.popLast() {
                guard seen.insert(id).inserted, let card = flow.card(id), id != loop.id else { continue }
                if takesTime(card.kind) {
                    if found[id]?.currentTry == nil { found[id] = back }
                } else {
                    next += flow.links(from: id).map(\.to)
                }
            }
        }
        return found
    }

    // MARK: The line

    private static func headline(flow: Flow, stops: [Stop], needs: [String: Need], ending: RunEnding?,
                                 failed: Set<String>, answered: Bool) -> Headline {
        if let card = flow.cards.first(where: { failed.contains($0.id) }) {
            // An End set to fail the run is where the flow meant it to end, so the run simply failed.
            return Headline(tone: .failed, text: card.kind == .end ? "Failed" : "Stopped at \(card.name)", cardID: card.id)
        }
        if let ending {
            switch ending {
            case .finishedWithAnswer, .gaveUp:
                return Headline(tone: answered ? .finished : .stopped, text: answered ? "Finished" : capitalized(ending.label))
            case .failed: return Headline(tone: .failed, text: "Failed")
            default: return Headline(tone: .stopped, text: capitalized(ending.label))
            }
        }
        if let stop = stops.first(where: { $0.state == .needsYou }) {
            let text = switch needs[stop.id] {
            case .allowCommand?: "Needs you: allow \(stop.name)'s command"
            case .question?: "\(stop.name) asked you a question"
            default: "Needs you: \(stop.name)"
            }
            return Headline(tone: .needsYou, text: text, cardID: stop.id)
        }
        let at = stops.filter { $0.state == .live }
        guard let first = at.first else { return Headline(tone: .working, text: "Working") }
        var text = switch first.kind {
        case .script: "\(first.name) running its command"
        case .flow: "\(first.name) running its flow"
        case .delay: "\(first.name) waiting"
        default: "\(first.name) working"
        }
        if at.count > 1 { text = "\(first.name) and \(at.count - 1) more working" }
        if let items = first.items { text += " · item \(items.current + 1) of \(items.count)" }
        if let loop = first.loopBack, let now = loop.currentTry, now > 1 { text += " · try \(now) of \(loop.mostTries)" }
        return Headline(tone: .working, text: text, cardID: first.id)
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    // MARK: The flow, with its loops taken out

    /// The flow's links with every link that leads back round a loop left out, so what is left can be walked to its
    /// end without going in circles.
    private struct Graph {
        /// The links on from each card that don't lead back.
        var next: [String: [Link]] = [:]
        /// Every card, each before every card it leads on to.
        var order: [String] = []
        /// How many links on from where a run starts each card is, at most.
        var depth: [String: Int] = [:]
        private var bodies: [String: Set<String>] = [:]

        init(_ flow: Flow) {
            enum Visit { case open, closed }
            var visit: [String: Visit] = [:]
            var finished: [String] = []
            // Walked without recursion, so a long flow can't run out of stack.
            func walk(from root: String) {
                guard visit[root] == nil else { return }
                var stack: [(id: String, links: [Link], index: Int)] = [(root, flow.links(from: root), 0)]
                visit[root] = .open
                while !stack.isEmpty {
                    let top = stack.count - 1
                    if stack[top].index == stack[top].links.count {
                        visit[stack[top].id] = .closed
                        finished.append(stack[top].id)
                        stack.removeLast()
                        continue
                    }
                    let link = stack[top].links[stack[top].index]
                    stack[top].index += 1
                    guard flow.card(link.to) != nil else { continue }
                    switch visit[link.to] {
                    case .open: continue // back round a loop
                    case .closed: next[link.from, default: []].append(link)
                    case nil:
                        next[link.from, default: []].append(link)
                        visit[link.to] = .open
                        stack.append((link.to, flow.links(from: link.to), 0))
                    }
                }
            }
            for card in flow.cards where card.kind == .start { walk(from: card.id) }
            for card in flow.cards { walk(from: card.id) }
            order = finished.reversed()
            for card in flow.cards where card.kind == .forEach {
                var cards: Set<String> = [], todo = flow.links(from: card.id, port: "each").map(\.to)
                while let id = todo.popLast() {
                    guard id != card.id, cards.insert(id).inserted else { continue }
                    todo += flow.links(from: id).map(\.to)
                }
                bodies[card.id] = cards
            }
            // A For each goes through its body before it goes on by Done, so what comes after Done sits after the
            // body. Worked out again until nothing moves, never deeper than there are cards.
            let deepest = flow.cards.count
            var moved = true, rounds = 0
            while moved, rounds <= deepest {
                moved = false
                rounds += 1
                func push(_ id: String, to wanted: Int) {
                    let wanted = min(wanted, deepest)
                    if wanted > depth[id] ?? 0 { depth[id] = wanted; moved = true }
                }
                for id in order {
                    for link in next[id] ?? [] { push(link.to, to: (depth[id] ?? 0) + 1) }
                }
                for (each, body) in bodies {
                    guard let last = body.map({ depth[$0] ?? 0 }).max() else { continue }
                    for link in next[each] ?? [] where link.port != "each" { push(link.to, to: last + 1) }
                }
            }
        }

        /// The cards a For each card's items go through.
        func body(of id: String) -> Set<String> { bodies[id] ?? [] }

        /// The cards `starts` lead on to, them included.
        func reachable(from starts: [String]) -> Set<String> {
            var seen: Set<String> = [], todo = starts
            while let id = todo.popLast() {
                guard seen.insert(id).inserted else { continue }
                todo += (next[id] ?? []).map(\.to)
            }
            return seen
        }
    }
}
