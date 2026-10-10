import CryptoKit
import Foundation
import Subprocess
import System

/// Runs a Script card's command, and remembers which commands the person has allowed.
enum ScriptRunner {
    /// A command that hasn't finished by now is stopped and counts as failed.
    nonisolated static let timeout: Duration = .seconds(600)
    /// As much of what a command printed as is passed on: the end of it, where a failure usually is.
    nonisolated static let outputLimit = 20_000

    /// Runs `command` in a login shell in `folder`, with the message on standard input and in
    /// QB_MESSAGE. Returns whether it exited with 0, and what it printed.
    nonisolated static func run(_ command: String, message: String, from: String, in folder: URL,
                                environment: ResolvedEnvironment) async -> (passed: Bool, output: String) {
        var variables: [Environment.Key: String] = [:]
        for (key, value) in environment.variables(adding: ["QB_MESSAGE": message, "QB_FROM": from]) {
            if let key = Environment.Key(rawValue: key) { variables[key] = value }
        }
        let work = Task { () -> (Bool, String) in
            let result = try await Subprocess.run(
                .path("/bin/zsh"), arguments: ["-lc", command], environment: .custom(variables),
                workingDirectory: FilePath(folder.path), input: .string(message),
                output: .string(limit: 400_000), error: .string(limit: 400_000))
            let printed = [result.standardOutput, result.standardError].compactMap { $0 }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
            return (result.terminationStatus.isSuccess, String(printed.suffix(outputLimit)))
        }
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
        }
        defer { watchdog.cancel() }
        do {
            let (passed, printed) = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            return (passed, printed)
        } catch is CancellationError {
            return (false, "The command was stopped before it finished.")
        } catch {
            return (false, "The command couldn't be run: \(error.localizedDescription)")
        }
    }

    // MARK: Allowed commands

    // A Script card runs with no permission prompt, so only a command the person has typed or
    // allowed themselves may run. One command is remembered per card: the latest they approved.
    // This lives in the app's own settings, never in the flow file, so a file can't allow itself.
    private static let key = "allowedScripts"

    private static func fingerprint(_ command: String) -> String {
        SHA256.hash(data: Data(command.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isAllowed(_ command: String, flowID: String, cardID: String) -> Bool {
        let allowed = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return allowed["\(flowID)/\(cardID)"] == fingerprint(command)
    }

    static func allow(_ command: String, flowID: String, cardID: String) {
        var allowed = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        allowed["\(flowID)/\(cardID)"] = fingerprint(command)
        UserDefaults.standard.set(allowed, forKey: key)
    }
}
