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
    /// How far into a transcript has been read, and what it added up to. A transcript only
    /// grows, so each read takes in what was written since the last one.
    private struct Progress {
        var path: String
        var offset: UInt64 = 0
        var banked = Usage()
        var latest = Usage()
    }

    private nonisolated(unsafe) static var progress: [String: Progress] = [:]
    private nonisolated static let lock = NSLock()

    /// The session's usage so far, or nil when it has no transcript yet.
    nonisolated static func usage(sessionID: String) -> Usage? {
        lock.lock()
        defer { lock.unlock() }
        var state: Progress
        if let known = progress[sessionID], FileManager.default.fileExists(atPath: known.path) {
            state = known
        } else if let url = transcript(for: sessionID) {
            state = Progress(path: url.path)
        } else {
            return nil
        }
        guard let handle = FileHandle(forReadingAtPath: state.path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // A file shorter than what was read has been replaced: start again.
        if size < state.offset { state = Progress(path: state.path) }
        try? handle.seek(toOffset: state.offset)

        var carry = Data()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            carry.append(chunk)
            // Whole lines only. A line still being written is left for the next read.
            while let newline = carry.firstIndex(of: 0x0A) {
                let line = carry[carry.startIndex..<newline]
                state.offset += UInt64(line.count + 1)
                carry = carry[carry.index(after: newline)...]
                take(Data(line), into: &state)
            }
        }
        progress[sessionID] = state
        return state.banked + state.latest
    }

    /// Adds one line of a transcript to the running figures, if it is one of Claude Code's cost entries.
    private nonisolated static func take(_ line: Data, into state: inout Progress) {
        guard line.range(of: Data("\"cost-state\"".utf8)) != nil,
              let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "cost-state" else { return }
        var now = Usage(cost: entry["totalCostUSD"] as? Double ?? 0)
        for (_, model) in entry["modelUsage"] as? [String: [String: Any]] ?? [:] {
            now.input += model["inputTokens"] as? Int ?? 0
            now.output += model["outputTokens"] as? Int ?? 0
            now.cacheRead += model["cacheReadInputTokens"] as? Int ?? 0
            now.cacheWrite += model["cacheCreationInputTokens"] as? Int ?? 0
        }
        // Each process the session has run in keeps its own running total. A total that falls
        // means a new process began from nothing, so what the last one reached is banked.
        if now.cost < state.latest.cost || now.tokens < state.latest.tokens { state.banked = state.banked + state.latest }
        state.latest = now
    }

    private nonisolated static func transcript(for sessionID: String) -> URL? {
        // A session id is a UUID. Anything else is not used to build a path.
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent("\(sessionID).jsonl") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
