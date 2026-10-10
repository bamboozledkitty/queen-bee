# Security

## Reporting a problem

Please report security problems privately through
[GitHub's private vulnerability reporting](https://github.com/bamboozledkitty/queen-bee/security/advisories/new),
not in a public issue. Say what you found, how to reproduce it and which version you used.

Only the latest release gets security fixes.

## What Queen Bee does on your Mac

Queen Bee starts Claude Code sessions as you, in the folders you choose. It is not sandboxed. A session can do
whatever Claude Code can do under the permission mode its card has, so treat a flow like a script you are about to run.

- **Flow files are instructions.** A flow in `<project>/.queenbee/flows/` holds each agent's instructions, working
  folder and permission mode, and opening the flow starts those sessions. When you add a folder that already has
  flows in it, the app asks whether you trust it first. The `.queenbee` folder ignores itself in git, so flows are
  not shared by accident. Flows that arrive later in a folder you already trusted are not asked about again.
- **Permission modes are limited.** A card can use manual, accept edits, plan or auto. A mode that skips permission
  checks cannot be set from a flow file, the settings panel or the orchestrator's tools.
- **Script cards run commands with no prompt.** A Script card runs a shell command as you when a run reaches it.
  It only runs a command you typed into its settings or allowed yourself on this Mac. A command written by the
  orchestrator, pasted in, or arriving in a flow file stops the run and asks you first. What you allowed is kept in
  the app's own settings, not in the flow file.
- **Schedules start runs with nobody watching.** A Start card can run on the clock or when a file in the project
  changes, while the app is open. A schedule only fires once you have set it or turned it on in this app, so one
  that arrives in a flow file stays off until you agree. A copied Start card never brings its schedule with it.
- **Sub-flows have a depth limit.** A Flow card runs another flow of the same project. How deep that can nest is
  set on the flow at the top, three levels unless changed and never more than ten, and a run stops at the limit, so
  flows can't be chained without end.
- **The orchestrator can edit and run the flow without asking.** Its tools are pre-approved. Text an agent reads
  from the web or a file can end up in front of the orchestrator, so the usual prompt-injection caution applies.
- **The app's socket is local.** The helper talks to the app over a unix socket in
  `~/Library/Application Support/QueenBee/`, a folder only your account can open. Each session has its own secret,
  and only the orchestrator's secret unlocks the flow-editing tools. A program already running as you with shell
  access could read those secrets, so this limits agents, not other software on your account.
- **Updates are signed.** The app only installs an update signed with the project's update key. Releases are signed
  with a Developer ID but are not yet notarized by Apple.

## Known limits

- The session plugin is copied to Application Support at launch, where another program running as you could change it.
- A flow's regular-expression checks run as written. A pathological pattern can stall a run.
