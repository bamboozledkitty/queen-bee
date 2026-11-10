import Foundation
import QueenBeeCore
import Subprocess
import System

/// The few things Queen Bee asks git about a project, and the two it asks git to do: switch the project
/// folder to a branch, and add a worktree. Every name reaches git after "--" or as a value it can't take
/// for an option, and none is typed by anything but the person.
nonisolated enum Git {
    /// What the project's repository looks like right now.
    nonisolated struct Info: Equatable, Sendable {
        /// The branch the project folder is on, or nil when it has none checked out.
        var current: String?
        var branches: [String]
        /// The branch new worktrees start from unless the person picks another: the remote's default, else
        /// main or master, else the current branch.
        var defaultBranch: String
        var worktrees: [Workplace.Worktree]
    }

    nonisolated static let executable = "/usr/bin/git"
    nonisolated static let readLimit = 4_000_000
    /// git asks nothing of anyone here: no password, no editor.
    nonisolated private static var quiet: [Environment.Key: String] {
        var env: [Environment.Key: String] = [:]
        for (k, v) in ProcessInfo.processInfo.environment { if let key = Environment.Key(rawValue: k) { env[key] = v } }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        env["LC_ALL"] = "C"
        return env
    }

    /// Runs git in `folder`. Whether it exited with 0, and what it printed.
    nonisolated static func run(_ arguments: [String], in folder: URL) async -> (ok: Bool, output: String, error: String) {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return (false, "", "git isn't installed on this Mac.") }
        do {
            let result = try await Subprocess.run(
                .path(FilePath(executable)), arguments: Arguments(arguments), environment: .custom(quiet),
                workingDirectory: FilePath(folder.path), input: .none,
                output: .string(limit: readLimit), error: .string(limit: readLimit))
            return (result.terminationStatus.isSuccess,
                    (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    (result.standardError ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, "", "git couldn't be started: \(error.localizedDescription)")
        }
    }

    /// The repository at `root`, or nil when the project folder isn't in one.
    nonisolated static func info(at root: URL) async -> Info? {
        guard await run(["rev-parse", "--is-inside-work-tree"], in: root).output == "true" else { return nil }
        let current = await run(["branch", "--show-current"], in: root).output
        let branches = await run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: root).output
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let worktrees = Workplace.parseWorktrees(await run(["worktree", "list", "--porcelain"], in: root).output)
        let remote = await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root)
        var preferred: String?
        if remote.ok, remote.output.hasPrefix("origin/") {
            let name = String(remote.output.dropFirst("origin/".count))
            if branches.contains(name) { preferred = name }
        }
        let checkedOut: String? = current.isEmpty ? nil : current
        let usual = ["main", "master"].first { branches.contains($0) }
        let fallback = preferred ?? usual ?? checkedOut ?? branches.first ?? "main"
        return Info(current: checkedOut, branches: branches, defaultBranch: fallback, worktrees: worktrees)
    }

    /// Files git tracks that have changes not yet committed, which switching branch could carry along or refuse over.
    nonisolated static func hasUncommittedChanges(at root: URL) async -> Bool {
        let status = await run(["status", "--porcelain", "--untracked-files=no"], in: root)
        return !status.ok || !status.output.isEmpty
    }

    /// Switches the project folder to `branch`. Nil when it worked, else what git said.
    nonisolated static func switchBranch(to branch: String, at root: URL) async -> String? {
        let done = await run(["switch", "--no-guess", branch], in: root)
        return done.ok ? nil : (done.error.isEmpty ? "git couldn't switch to \(branch)." : done.error)
    }

    /// Carries out a worktree plan. Nil when it worked, else what git said.
    nonisolated static func make(_ plan: Workplace.WorktreePlan, at root: URL) async -> String? {
        guard let arguments = plan.gitArguments else { return nil }
        makeIgnoredFolder(root.appendingPathComponent(Workplace.worktreesFolder, isDirectory: true))
        let done = await run(arguments, in: root)
        return done.ok ? nil : (done.error.isEmpty ? "git couldn't make the worktree." : done.error)
    }

    /// Makes `folder` if it isn't there, with a `.gitignore` that keeps everything in it out of git, even in a
    /// project that has chosen to commit its .queenbee folder.
    nonisolated static func makeIgnoredFolder(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ignore = folder.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignore.path) { try? Data("*\n".utf8).write(to: ignore) }
    }

    // MARK: Rehearsal copies

    nonisolated struct RehearsalCopyError: Error, Sendable {
        let text: String
        init(_ text: String) { self.text = text }
    }

    /// Makes a throwaway copy of `source`, where a flow works, for the rehearsal `runID`: a worktree on a new
    /// branch at `source`'s current commit, in `folder`, the project's rehearsals folder, with `source`'s
    /// uncommitted changes, tracked and untracked but not ignored, copied in. The folder in the copy that stands for
    /// `source`, or what went wrong. A worktree is of the whole repository, so for a `source` in a subfolder of its
    /// repository that is the same subfolder of the copy. A copy that went wrong part-way is removed.
    /// Off the main actor, since copying untracked files can take a while.
    @concurrent
    nonisolated static func makeRehearsalCopy(of source: URL, runID: String, in folder: URL) async -> Result<URL, RehearsalCopyError> {
        let copy = folder.appendingPathComponent(runID, isDirectory: true)
        // Ignored before anything is copied, as the copy can sit inside `source` itself: no rehearsal copies another.
        makeIgnoredFolder(folder)
        let prefix = await run(["rev-parse", "--show-prefix"], in: source)
        guard prefix.ok, let work = Rehearsal.workFolder(inCopy: copy, subfolder: prefix.output) else {
            return .failure(.init(prefix.error.isEmpty ? "git couldn't say where the project is in its repository." : prefix.error))
        }
        let branch = Rehearsal.branch(forRun: runID)
        let made = await run(["worktree", "add", "-b", branch, copy.path, "HEAD"], in: source)
        guard made.ok else {
            // git can make the branch and then fail to fill the folder.
            await removeRehearsalCopy(copy, runID: runID, from: source)
            return .failure(.init(made.error.isEmpty ? "git couldn't make the copy." : made.error))
        }
        // Tracked changes: a stash commit made without touching the working tree or the stash list, applied in the copy.
        // When git can't make one, as in a merge that is part-way, the copy would be without them, so it isn't made.
        let stash = await run(["stash", "create"], in: source)
        guard stash.ok else {
            await removeRehearsalCopy(copy, runID: runID, from: source)
            return .failure(.init(Rehearsal.uncommittedRefusal(stash.error)))
        }
        if !stash.output.isEmpty {
            let applied = await run(["stash", "apply", stash.output], in: copy)
            if !applied.ok {
                await removeRehearsalCopy(copy, runID: runID, from: source)
                return .failure(.init(Rehearsal.uncommittedRefusal(applied.error)))
            }
        }
        // Untracked files that git doesn't ignore, which git names from `source`, wherever it is in the repository.
        let untracked = await run(["ls-files", "--others", "--exclude-standard", "-z"], in: source)
        for path in untracked.output.split(separator: "\0").map(String.init) where !path.isEmpty {
            let from = source.appendingPathComponent(path)
            let to = work.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: from, to: to)
        }
        return .success(work)
    }

    /// Removes a rehearsal's copy and its branch. Nothing in it is kept.
    nonisolated static func removeRehearsalCopy(_ copy: URL, runID: String, from root: URL) async {
        _ = await run(["worktree", "remove", "--force", copy.path], in: root)
        try? FileManager.default.removeItem(at: copy)
        _ = await run(["worktree", "prune"], in: root)
        _ = await run(["branch", "-D", Rehearsal.branch(forRun: runID)], in: root)
    }

    /// Removes the copies and branches of rehearsals a crash or a quit left behind, in the repository at `root`.
    /// Only copies in `folder`, the project's rehearsals folder, are touched, and only ones made more than
    /// `Rehearsal.leftoverAge` ago: another flow of the project, or another copy of the app, can be rehearsing in a
    /// newer one. `isInUse` is asked again just before each removal, as a rehearsal can start while this goes on.
    /// A branch whose copy is still there is left, as git refuses to delete a branch open in a worktree.
    nonisolated static func sweepRehearsalCopies(at root: URL, in folder: URL, isInUse: @Sendable (String) async -> Bool) async {
        guard let info = await info(at: root) else { return }
        let ours = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        func isOurs(_ path: String) -> Bool {
            URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(ours)
        }
        func id(of branch: String) -> String { String(branch.dropFirst(Rehearsal.branchPrefix.count)) }
        func made(_ path: String) -> Date? {
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.creationDateKey]))?.creationDate
        }
        // The branches of the copies still there, which are left alone.
        var open: Set<String> = []
        for worktree in info.worktrees {
            guard let branch = worktree.branch, Rehearsal.isRehearsalBranch(branch) else { continue }
            guard isOurs(worktree.path) else {
                open.insert(branch)
                continue
            }
            // A worktree git knows of whose folder has gone is forgotten by the prune below.
            guard FileManager.default.fileExists(atPath: worktree.path) else { continue }
            guard Rehearsal.isLeftover(madeAt: made(worktree.path)), await !isInUse(id(of: branch)) else {
                open.insert(branch)
                continue
            }
            _ = await run(["worktree", "remove", "--force", worktree.path], in: root)
            if FileManager.default.fileExists(atPath: worktree.path) { open.insert(branch) }
        }
        _ = await run(["worktree", "prune"], in: root)
        for branch in info.branches where Rehearsal.isRehearsalBranch(branch) && !open.contains(branch) {
            // A copy is made by making its branch first, so a young branch with no folder yet can be a copy on its way.
            guard Rehearsal.isLeftover(madeAt: await lastMoved(branch, at: root)), await !isInUse(id(of: branch)) else { continue }
            _ = await run(["branch", "-D", branch], in: root)
        }
    }

    /// When `branch` last moved: from its reflog, or else its commit's date, which is no later.
    nonisolated private static func lastMoved(_ branch: String, at root: URL) async -> Date? {
        let reflog = await run(["log", "-g", "-1", "--date=unix", "--format=%gd", "refs/heads/" + branch, "--"], in: root)
        if reflog.ok, let moved = Rehearsal.branchMoved(reflogLine: reflog.output) { return moved }
        let commit = await run(["log", "-1", "--format=%ct", "refs/heads/" + branch, "--"], in: root)
        return commit.ok ? TimeInterval(commit.output).map(Date.init(timeIntervalSince1970:)) : nil
    }
}
