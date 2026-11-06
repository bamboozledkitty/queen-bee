import Foundation

/// Two kept runs of one flow side by side: how each ended, how long it took, what it cost, and what each card did.
/// Built from what the run history already keeps, so it changes nothing. A run keeps its path, its decisions and
/// its cost; what agents said is kept for the newest few runs only, so replies are compared only when both runs
/// have them. Something one run didn't keep is unknown, never a difference.
public struct RunComparison: Equatable, Sendable {
    /// One of the two runs.
    public struct Side: Equatable, Sendable {
        public var id: String
        /// "#12", or "the earlier run" and "the later run" for runs kept before runs were numbered.
        public var name: String
        public var started: Date
        public var ended: Date
        /// How it ended, in a few words.
        public var summary: String
        public var outcome: RunRecord.Outcome
        /// What it cost. Nil until the Mac has worked it out, and for runs kept before costs were.
        public var cost: Usage?
        public var handOffs: Int
        /// It still has the messages its links carried.
        public var keepsMessages: Bool

        public var length: String { RunClock.length(from: started, to: ended) }
    }

    /// What one card did in one run.
    public struct CardRun: Equatable, Sendable {
        /// A message reached the card, or left it.
        public var reached = false
        /// How many times it left by each output.
        public var ports: [String: Int] = [:]
        /// The run stopped at this card.
        public var failed = false
        /// What the card's session used. Nil when it isn't known.
        public var cost: Usage?
        /// An agent's last reply, as far as it was kept. Nil when the run kept no messages, it never replied, or
        /// its reply went along a link the flow no longer has.
        public var reply: String?
        /// How many times an agent replied, as in a For each: counted whether or not the run kept its messages.
        public var replies = 0
        /// The answer that reached an End card.
        public var answer: String?
    }

    /// One card, in both runs.
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Nil for a card that has been taken out of the flow since.
        public var kind: CardKind?
        public var before: CardRun
        public var after: CardRun
        /// What differs, in plain words. Empty when nothing that both runs kept differs.
        public var changes: [String]

        public var isChanged: Bool { !changes.isEmpty }
    }

    /// The older run.
    public var before: Side
    /// The newer run.
    public var after: Side
    /// What differs between the runs as a whole, in plain words.
    public var changes: [String]
    /// Each card either run reached, in canvas order, then cards taken out since.
    public var rows: [Row]
    /// Both runs kept their messages, so agents' replies can be set side by side. End answers are kept with every run.
    public var comparesReplies: Bool

    /// Why replies aren't compared, when they aren't.
    public var repliesNote: String? {
        comparesReplies ? nil : "Replies are kept only for the \(Self.runsWithMessages) latest runs, so only the paths, decisions and costs are compared."
    }

    /// How many runs keep the messages their links carried: the Mac's own number.
    public static let runsWithMessages = 3

    /// The two runs, older first whichever way round they come. Nil for a run set against itself.
    public init?(_ one: RunRecord, _ two: RunRecord, in flow: Flow) {
        guard one.id != two.id else { return nil }
        let (a, b) = one.started <= two.started ? (one, two) : (two, one)
        before = Self.side(a, fallback: "the earlier run")
        after = Self.side(b, fallback: "the later run")
        comparesReplies = !a.messages.isEmpty && !b.messages.isEmpty
        changes = Self.changes(before, after)

        var ids = flow.cards.map(\.id)
        let gone = Set(a.marks.keys).union(b.marks.keys).union(a.results.keys).union(b.results.keys).subtracting(ids)
        ids += gone.sorted()
        let (first, second, replies) = (before, after, comparesReplies)
        rows = ids.compactMap { id in
            let card = flow.card(id)
            let one = Self.cardRun(id, card, in: a, flow: flow, replies: replies)
            let two = Self.cardRun(id, card, in: b, flow: flow, replies: replies)
            guard one.reached || two.reached else { return nil }
            return Row(id: id, name: card?.name ?? "A card since removed", kind: card?.kind, before: one, after: two,
                       changes: Self.changes(one, two, card: card, before: first, after: second))
        }
    }

    // MARK: Words

    /// What a card did in one run, in a few words: "Not reached", "Yes", "Yes 2 · No 1", "Stopped the run".
    public func line(for run: CardRun, in row: Row) -> String {
        guard run.reached else { return "Not reached" }
        var parts: [String] = []
        if run.failed { parts.append(row.kind == .end ? "Ended the run as failed" : "Stopped the run") }
        let order = row.kind.map { kind in ports(of: Card.make(kind: kind, name: "", x: 0, y: 0)) } ?? []
        let taken = run.ports.filter { $0.value > 0 }.sorted { (order.firstIndex(of: $0.key) ?? .max, $0.key) < (order.firstIndex(of: $1.key) ?? .max, $1.key) }
        // Leaving once by Out, the way most cards go, is nothing worth naming.
        if !(taken.count == 1 && taken[0].key == "out" && taken[0].value == 1) {
            parts += taken.map { $0.value == 1 ? portLabel($0.key) : "\(portLabel($0.key)) \($0.value)" }
        }
        if parts.isEmpty {
            parts.append(row.kind == .end ? "Got an answer" : row.kind == .agent ? (run.replies > 0 ? "Replied" : "Didn't reply") : "Passed it on")
        }
        if let cost = run.cost, !cost.isZero { parts.append(cost.price) }
        return parts.joined(separator: " · ")
    }

    private static func side(_ run: RunRecord, fallback: String) -> Side {
        Side(id: run.id, name: run.number.map { "#\($0)" } ?? fallback, started: run.started, ended: run.ended, summary: run.summary,
             outcome: run.outcome, cost: run.usage == nil ? nil : run.cost, handOffs: run.handOffs, keepsMessages: !run.messages.isEmpty)
    }

    private static func changes(_ a: Side, _ b: Side) -> [String] {
        var out: [String] = []
        if a.summary != b.summary { out.append("Ended: \(a.summary) in \(a.name), \(b.summary) in \(b.name)") }
        if a.handOffs != b.handOffs { out.append("Hand-offs: \(a.handOffs) → \(b.handOffs)") }
        if let one = a.cost, let two = b.cost, one.price != two.price { out.append("Cost: \(one.price) → \(two.price)") }
        return out
    }

    private static func cardRun(_ id: String, _ card: Card?, in run: RunRecord, flow: Flow, replies: Bool) -> CardRun {
        var out = CardRun()
        let mark = run.marks[id]
        out.reached = (mark.map { $0.arrivals > 0 || $0.passes > 0 || $0.failed } ?? false) || run.results[id] != nil
        out.ports = mark?.ports ?? [:]
        out.failed = mark?.failed ?? false
        out.cost = run.usage?[id]
        if run.usage != nil, out.cost == nil, card?.kind == .agent, out.reached { out.cost = Usage() }
        out.answer = run.results[id]
        guard card?.kind == .agent else { return out }
        out.replies = mark?.ports["out"] ?? 0
        guard replies else { return out }
        // A reply goes along every link from Out, so the link that carried the most has the agent's replies, once.
        // Its Error links carry the message it was given, not a reply.
        let carried = flow.links(from: id, port: "out").map { run.messages[$0.id] ?? [] }.max { $0.count < $1.count } ?? []
        out.reply = carried.last?.text
        return out
    }

    private static func changes(_ a: CardRun, _ b: CardRun, card: Card?, before: Side, after: Side) -> [String] {
        if a.reached != b.reached { return ["Reached only in \(a.reached ? before.name : after.name)"] }
        var out: [String] = []
        if a.failed != b.failed {
            let which = a.failed ? before.name : after.name
            out.append(card?.kind == .end ? "Ended the run as failed in \(which)" : "Stopped the run in \(which)")
        }
        if card?.kind == .agent {
            if a.ports["error"] != b.ports["error"] { out.append("Failed a different number of times") }
            if a.replies != b.replies { out.append("Replies: \(a.replies) → \(b.replies)") }
        } else if a.ports.filter({ $0.value > 0 }) != b.ports.filter({ $0.value > 0 }) {
            out.append("Went a different way")
        }
        if let one = a.cost, let two = b.cost, one.price != two.price { out.append("Cost: \(one.price) → \(two.price)") }
        // A reply that wasn't kept, or went along a link since replaced, is unknown: only two kept replies are compared.
        if let one = a.reply, let two = b.reply, one != two, a.replies == b.replies { out.append("Said something different") }
        // Every kept run keeps its answers.
        if let one = a.answer, let two = b.answer, one != two { out.append("A different answer") }
        return out
    }
}
