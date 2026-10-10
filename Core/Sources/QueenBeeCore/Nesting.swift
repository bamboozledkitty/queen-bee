import Foundation

/// How the flows of a project sit inside one another through their Flow cards, and how deep
/// the flow at the top of each chain allows that to go. Built once from every flow, then
/// asked about any of them, so a project whose files reference each other every which way
/// still answers in a moment.
public struct Nesting: Sendable {
    /// How many levels of sub-flow a flow allows below it when nobody has said otherwise.
    public static let usualLimit = 3
    /// As deep as any flow may ever allow.
    public static let deepestLimit = 10

    private let ids: [String]
    private let names: [String: String]
    private let limits: [String: Int]
    /// The flows each flow's Flow cards run, in canvas order, each once.
    private let inner: [String: [String]]
    /// The flows that run each flow.
    private let outer: [String: [String]]

    public init(flows: [Flow]) {
        ids = flows.map(\.id)
        names = Dictionary(flows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        limits = Dictionary(flows.map { ($0.id, Self.clamped($0.subflowLimit)) }, uniquingKeysWith: { a, _ in a })
        var inner: [String: [String]] = [:], outer: [String: [String]] = [:]
        for flow in flows {
            var seen: Set<String> = []
            for card in flow.cards where card.kind == .flow {
                guard let target = Self.resolve(card.flowRef, in: flows, excluding: flow.id), seen.insert(target).inserted else { continue }
                inner[flow.id, default: []].append(target)
                outer[target, default: []].append(flow.id)
            }
        }
        self.inner = inner
        self.outer = outer
    }

    /// A flow's own limit, within the range the app allows.
    public static func clamped(_ limit: Int?) -> Int {
        min(max(limit ?? usualLimit, 0), deepestLimit)
    }

    /// The flow a reference names: by id, else by name ignoring case, never the flow itself.
    public static func resolve(_ ref: String?, in flows: [Flow], excluding own: String) -> String? {
        guard let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }
        let others = flows.filter { $0.id != own }
        return (others.first { $0.id == ref } ?? others.first { $0.name.caseInsensitiveCompare(ref) == .orderedSame })?.id
    }

    public func innerFlows(of id: String) -> [String] { inner[id] ?? [] }
    public func outerFlows(of id: String) -> [String] { outer[id] ?? [] }
    public func limit(of id: String) -> Int { limits[id] ?? Self.usualLimit }

    /// Every flow below `id`, outermost first, each once, with how many levels down it sits.
    public func subflows(of id: String) -> [(id: String, depth: Int)] {
        var found: [(String, Int)] = [], seen: Set<String> = [id]
        var queue = innerFlows(of: id).map { ($0, 0) }
        while !queue.isEmpty {
            let (next, depth) = queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            found.append((next, depth))
            queue += innerFlows(of: next).map { ($0, depth + 1) }
        }
        return found
    }

    /// How many levels of sub-flow sit below a flow. A flow that runs itself round a circle counts the circle once.
    public func levelsBelow(_ id: String) -> Int {
        var memo: [String: Int] = [:], stack: Set<String> = []
        func below(_ at: String) -> Int {
            if let known = memo[at] { return known }
            guard stack.insert(at).inserted else { return 0 }
            defer { stack.remove(at) }
            let depth = innerFlows(of: at).map { 1 + below($0) }.max() ?? 0
            memo[at] = depth
            return depth
        }
        return below(id)
    }

    /// How many more levels of sub-flow may sit below a flow. The limit belongs to the flow at
    /// the top, and each level down uses one up. A flow that two others run goes by the
    /// stricter of the two. Below zero means the flow is itself past the limit.
    public func levelsLeft(_ id: String) -> Int {
        var memo: [String: Int] = [:], stack: Set<String> = []
        func left(_ at: String) -> Int {
            if let known = memo[at] { return known }
            guard stack.insert(at).inserted else { return limit(of: at) }
            defer { stack.remove(at) }
            let above = outerFlows(of: at).filter { !stack.contains($0) }
            let result = above.map { left($0) - 1 }.min() ?? limit(of: at)
            memo[at] = result
            return result
        }
        return left(id)
    }

    /// The flows at the top of every chain that leads down to a flow. A flow nothing runs is its own top.
    public func topFlows(of id: String) -> [String] {
        var found: [String] = [], seen: Set<String> = []
        func climb(_ at: String) {
            guard seen.insert(at).inserted else { return }
            let above = outerFlows(of: at)
            if above.isEmpty { found.append(at) } else { above.forEach(climb) }
        }
        climb(id)
        return found
    }

    /// Why a Flow card in `host` can't run `inner`, or nil if it can: a flow can't end up
    /// running itself, and sub-flows only go as deep as the flow at the top allows.
    public func problem(placing inner: String, in host: String) -> String? {
        if inner == host { return "A flow can't run itself." }
        if subflows(of: inner).contains(where: { $0.id == host }) {
            return "\(name(inner)) already runs \(name(host)), so the two would go round for ever."
        }
        if 1 + levelsBelow(inner) > levelsLeft(host) { return tooDeep(below: host) }
        return nil
    }

    /// Why `host` can't be given a new sub-flow of its own, or nil if it can.
    public func problemAddingSubflow(to host: String) -> String? {
        levelsLeft(host) < 1 ? tooDeep(below: host) : nil
    }

    private func name(_ id: String) -> String { names[id] ?? id }

    private func tooDeep(below host: String) -> String {
        let top = topFlows(of: host).first ?? host
        let limit = limit(of: top)
        return "\(name(top)) allows sub-flows \(Self.levels(limit)) deep, and this would go deeper. Change the limit in \(name(top))'s flow settings."
    }

    /// "1 level", "3 levels".
    public static func levels(_ n: Int) -> String { "\(n) \(n == 1 ? "level" : "levels")" }
}
