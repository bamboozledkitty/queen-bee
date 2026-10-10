import Foundation

/// What a Claude Code session has used: tokens, and what they would cost at API prices.
nonisolated struct Usage: Codable, Equatable, Sendable {
    var cost = 0.0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var tokens: Int { input + output + cacheRead + cacheWrite }
    var isZero: Bool { cost == 0 && tokens == 0 }

    static func + (a: Usage, b: Usage) -> Usage {
        Usage(cost: a.cost + b.cost, input: a.input + b.input, output: a.output + b.output,
              cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }

    /// What was used since `earlier`, never less than nothing.
    func since(_ earlier: Usage) -> Usage {
        Usage(cost: max(0, cost - earlier.cost), input: max(0, input - earlier.input), output: max(0, output - earlier.output),
              cacheRead: max(0, cacheRead - earlier.cacheRead), cacheWrite: max(0, cacheWrite - earlier.cacheWrite))
    }

    /// "$0.37", "<$0.01", "$124".
    var price: String {
        if cost <= 0 { return "$0.00" }
        if cost < 0.01 { return "<$0.01" }
        return cost >= 100 ? String(format: "$%.0f", cost) : String(format: "$%.2f", cost)
    }

    /// "182k tokens", "1.2M tokens".
    var tokenCount: String {
        let n = Double(tokens)
        if n >= 1_000_000 { return String(format: "%.1fM tokens", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk tokens", n / 1_000) }
        return "\(tokens) tokens"
    }
}

/// Reads a session's usage from the transcript Claude Code keeps. Claude Code works the cost
/// out itself and writes a running total there, so no prices are kept in this app.
enum UsageReader {
    /// The session's usage so far, or nil when it has no transcript yet.
    nonisolated static func usage(sessionID: String) -> Usage? {
        guard let url = transcript(for: sessionID), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Each process the session has run in keeps its own running total. A total that falls
        // means a new process began from nothing, so what the last one reached is banked.
        var banked = Usage(), latest = Usage()
        for line in text.split(separator: "\n") where line.contains("\"cost-state\"") {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  entry["type"] as? String == "cost-state" else { continue }
            var now = Usage(cost: entry["totalCostUSD"] as? Double ?? 0)
            for (_, model) in entry["modelUsage"] as? [String: [String: Any]] ?? [:] {
                now.input += model["inputTokens"] as? Int ?? 0
                now.output += model["outputTokens"] as? Int ?? 0
                now.cacheRead += model["cacheReadInputTokens"] as? Int ?? 0
                now.cacheWrite += model["cacheCreationInputTokens"] as? Int ?? 0
            }
            if now.cost < latest.cost || now.tokens < latest.tokens { banked = banked + latest }
            latest = now
        }
        return banked + latest
    }

    private nonisolated static func transcript(for sessionID: String) -> URL? {
        // A session id is a UUID. Anything else is not used to build a path.
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent("\(sessionID).jsonl") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
