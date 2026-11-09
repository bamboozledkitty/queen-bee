# Rehearsal mode

Date: 2026-11-09
Status: design approved by Keith, not built yet.

## Goal

A rehearsal runs the whole flow cheaply, on Haiku at low effort, to check its routing, loops and approvals before
a real run spends anything. Your files and your agents' real conversations are left alone. Later v1 features
build on it: the self-coaching flow and self-repairing runs test their suggested changes with a rehearsal.

## Decisions

| Question | Decision |
|---|---|
| Where do the agents run? | Each agent gets a fresh, throwaway copy of itself (a stand-in) on Haiku at low effort. The real conversations are never touched. A stand-in doesn't remember what the real agent has built up, so its replies can differ from a real run's. |
| What does a Script card do? | It is skipped. It passes on its last real output, or a "skipped" note if it has never run. A new card setting, **Runs in rehearsals**, lets a card run its command for real. |
| What do Approval and Delay cards do? | An Approval asks you as usual, marked as a rehearsal. A Delay passes the message on at once. |
| Where does the work happen? | In a temporary git copy of the flow's workplace, deleted when the rehearsal ends. A project that isn't in git runs read-only. |
| How was the build approach chosen? | A rehearsal is a kind of run in the same flow, so the canvas you're looking at lights up. Copying the flow into a hidden flow was turned down: you'd watch a flow you can't see, and history, progress and sub-flows would all need extra wiring. |

## What the person sees

- **Rehearse** sits beside Run on the Mac, in the same menu as "Run from". The iPad and iPhone app has it in the same place as Run. The orchestrator can start one with a tool.
- Schedules, `qb run` and `queenbee://run` links never start a rehearsal.
- While a rehearsal runs:
  - The run pill says "Rehearsal".
  - Each agent card that has a stand-in shows the stand-in's terminal, under a strip that says "Rehearsing on Haiku".
  - When the rehearsal ends, each card shows its real agent's terminal again.
- Afterwards:
  - The rehearsal appears in Runs with a "Rehearsal" pill, its path, its decisions and its cost.
  - Rehearsals keep their own list of the 5 latest, apart from the 20 latest real runs, so they never push a real run out.
  - A rehearsal can't be kept for good.
  - Rehearsals don't appear in Compare, and later features that learn from past runs leave them out.
- The log's first line names the rehearsal. It says where it works (the copy, or read-only), and which Script cards will run for real.

## How each card behaves in a rehearsal

| Card | In a rehearsal |
|---|---|
| Agent | A stand-in: a new session id, `--model haiku --effort low`, the card's own instructions and permission mode, started in the copy. It has no browser, even when the card's Browser setting is on. It gets no MCP servers but the plugin's own, and `git push` is refused. |
| Script | Skipped. It passes on the last real output stored for the card, or "Rehearsal: skipped `<command>`, which has never run." With **Runs in rehearsals** on, the command runs for real, in the copy. |
| Approval | Asks as usual. The question, the notification and the Needs you entry say it is a rehearsal. Its time limit and "when no answer" still apply. |
| Delay | Passes the message on at once. The log says how long it would have waited. |
| If, Switch, Loop until | As usual. The judge already uses Haiku. |
| Flow | The flow it runs rehearses too, with the same rules, in the same copy. |
| End | As usual. A file it saves goes into the copy, so nothing is saved for real, and the log says so. "Fail the run" still fails the rehearsal. |
| Start, Prompt, And, Or, For each, Note | As usual. |

- The orchestrator isn't told when a rehearsal ends, even with "Tell the orchestrator" on. That saves its cost.
- The flow's spending limit and the cap on hand-offs apply as usual.

## What a rehearsal can't stop

The copy keeps your files safe, but it isn't a full sandbox. Stand-ins keep their card's permissions, and get:

- no browser
- none of your other connected tools (MCP servers), such as email or Slack
- no `git push`

They can still reach the internet in other ways. For example, a shell command like `curl` or a deploy tool would still really run. A rehearsal is safe for your files, but not for an agent whose instructions tell it to publish something. `SECURITY.md` says this.

Claude Code has the switches for these limits: `--strict-mcp-config`, `--mcp-config` and `--disallowedTools`. The build must check that `--strict-mcp-config` still loads the qb-link plugin, which a run needs in order to hand messages on. If it doesn't, the stand-ins get the plugin's server by name through `--mcp-config`.

## A real run always wins

A flow has one run at a time.

- If a schedule, a `qb run` link or a device asks for a real run while the flow is rehearsing, the rehearsal stops. The log says "Stopped the rehearsal for a real run", and the real run starts.
- A Flow card in another flow's real run is treated the same way.
- Pressing Run on the Mac during a rehearsal asks first: "Stop the rehearsal and run for real?"
- A rehearsal never starts while a real run is going. Rehearse is turned off then, and the orchestrator's tool says why.

## How it works

### Core

- `RunRecord.rehearsal: Bool?`, written only when true. Old records read as real runs.
- `RunKeeping`:
  - Trims rehearsals to their own 5 latest. Like any run, a rehearsal keeps its messages only while it is one of the 3 newest runs.
  - Refuses to keep a rehearsal for good.
  - `trimmed` keeps the 20 latest real runs apart from rehearsals.
- `Rehearsal`, a new file of rules that need no window, each with a test:
  - The launch arguments for a stand-in, built from a card.
  - What a Script card passes on: the stored output, or the "skipped" note.
  - Whether a Script card runs for real.
  - What a Delay does.
  - The rule that a real run stops a rehearsal.
  - The log's first line.
- `Card.runsInRehearsals: Bool?`, Script cards only.
  - It goes in `Capabilities.swift` and `CardPatch`, and `CAPABILITIES.md` is rebuilt.
  - The orchestrator and devices may turn it off but never on. The check is the same one that holds a Script card's command.
  - `SECURITY.md` gets a line, because it lets a command run in a rehearsal without asking again.
- The engine is told a run is a rehearsal when it starts, and records it. Cards ask the app what to do, as they do now: the rehearsal rules live in the app's hand-offs and in `Rehearsal`, not in new engine branches.
- The last real output of each Script card is stored with the flow's history, capped like a message (`CarriedMessages`, 8,000 characters). A real run updates it.

### The Mac app

- `FlowController.start(...)` takes `rehearsal: Bool`, and so does `runToEnd`, so sub-flows rehearse too.
- **The copy:**
  - `Git` makes a worktree of the flow's workplace at its current commit, in the project's `.queenbee/rehearsals` folder, with a branch named `queenbee-rehearsal-<run id>`. The folder has a `.gitignore` of `*`, as `.queenbee/worktrees` does. It is inside the project because Claude Code asks whether to trust a folder it hasn't seen, which would stop every stand-in, and a folder inside one the person trusts doesn't ask.
  - Uncommitted changes, both tracked and untracked but not ignored, are copied in.
  - When the rehearsal ends, however it ends, the worktree and its branch are removed.
  - On launch, the app removes any `queenbee-rehearsal-*` worktrees and branches a crash left behind.
- **Read-only:** in a folder that isn't in git, stand-ins start with `--permission-mode plan`, and no Script card runs for real.
- **Stand-ins:**
  - Their sessions live in a dictionary next to the cards' own sessions, keyed by card id.
  - Their ids are never written to `Card.sessionID` or the flow file.
  - `--resume` and the carry-over of conversations never apply to them.
  - The hand-off code sends a card's messages to its stand-in during a rehearsal.
  - When the rehearsal ends, the stand-ins quit.
- **Cost:** `UsageReader` reads the stand-ins' transcripts from the copy's folder, so the spending limit and the cost are right. The transcripts are deleted with the copy, once the cost has been read. In a read-only rehearsal there is no copy, so once the cost has been read, each stand-in's own transcript and the folder Claude Code keeps beside it are deleted by its session id, and nothing else, so it never shows among the person's conversations.
- **Showing a stand-in:** the card view shows the stand-in's terminal and the "Rehearsing on Haiku" strip while one exists.
- **Rehearse in the window:** the Run menu gains Rehearse, the Runs page gains the pill, and the Run pill gains its label. All of them come from the design system.

### The orchestrator

A `rehearse_flow` tool works like `run_flow`, with the same command and start card. It is described in `Capabilities.swift`, so the orchestrator learns it through `CAPABILITIES.md`.

### The iPad and iPhone app

- A new `RemoteCommand.rehearse(flowID:command:startCardID:)` and `RemoteFeature.rehearsals`. A device offers Rehearse only to a Mac that announces it.
- The wire fingerprint is updated. `Remote.version` stays the same: the new field and command are optional, and older apps ignore them.
- Rehearsal runs carry the pill on a device, as kept runs carry "Kept".
- The canned Mac in `DebugCannedRun` answers `rehearse`.

## Testing

- **Core unit tests:**
  - stand-in arguments, including no browser, no outside MCP servers and no `git push`
  - Script and Delay rules
  - trimming with rehearsals in the mix
  - a real run winning over a rehearsal
  - the "runs in rehearsals" refusal from a device and from the orchestrator
  - old records decoding as real runs
  - wire parity and the fingerprint
- **End-to-end tests** (ask Keith before running them):
  - **Mac (`gates`):**
    - A rehearsal of a small flow on Haiku: its agents' real sessions are untouched, a script is skipped, and a Delay passes on at once.
    - The copy is gone afterwards.
    - The record is marked and trimmed apart from real runs.
    - A real run stops a rehearsal.
  - **Device:** `remote` with the stand-in device; `parity` and `panels` on an iPad and an iPhone.
- **Real app:** a rehearsal of a mock flow with an agent, a Script card, an Approval, a Delay and a Flow card, watched on screen.

## Not in this version

- Rehearsing from a single card ("rehearse from here").
- Choosing another model or effort for a rehearsal.
- Comparing a rehearsal with a real run.
- Copying ignored files such as `.env` into the copy.
