# Queen Bee

A Mac app for building and running flows of Claude Code agents on a canvas. Each agent is a live `claude` session in a terminal on a card. Logic cards route each agent's reply to the next cards, and an orchestrator session beside the canvas can edit and run the flow.

These are the instructions for any coding agent working in this repo. `README.md` and `CONTRIBUTING.md` say more for people.

## What you need

- A Mac with Apple silicon, on macOS 26 or later. Nothing here builds or runs on Linux or Windows.
- Xcode 27 and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- [Claude Code](https://claude.com/claude-code) 2.1.287 or later, signed in. Only the app and the end-to-end tests need it; the unit tests don't.

## Where things live

- `Core/` is a Swift package with no UI: the flow model, the file store, the routing engine, the orchestrator's tools, the browser's tools and the socket messages. It has its own `AGENTS.md`.
- `App/` is the SwiftUI and AppKit app. It has its own `AGENTS.md`.
- `Helper/` builds `qb`, a small binary inside the app bundle. Hooks, the plugin and the orchestrator's tool server all run it. Its logic lives in `Core/Sources/QueenBeeCore/HelperCommand.swift`, so it is tested there.
- `Plugin/qb-link/` is the Claude Code plugin the app loads into every session.
- `scripts/` holds the build, the end-to-end tests, the installer and the release script.
- `project.yml` describes the Xcode project. `QueenBee.xcodeproj` is generated from it and not checked in: change `project.yml`, never the project.

## Commands

```sh
./scripts/build.sh                            # Debug build into build/; also rewrites CAPABILITIES.md
./scripts/build.sh Release                    # the same, Release
open build/Build/Products/Debug/QueenBee.app  # run it
cd Core && swift test                         # unit tests, under a second
./scripts/e2e.py [scenario ...]               # end-to-end tests, about seven minutes
```

- `build.sh` regenerates the Xcode project, prints only errors and the result, and exits non-zero when the build fails. Trust its exit code.
- A build from source is called Queen Bee Dev. It keeps its own settings and support folder, so it runs beside an installed copy.
- Launch flags: `--open <folder>` opens a project folder, `--float` keeps the window above others, `--testing` turns on the test harness and lets a second copy run, `--welcome` shows the first-run walk-through. `--testing`, `--welcome` and `QB_SUPPORT_DIR` only work in a Debug build.
- `swift test` is the only thing CI runs. Run it before you call any change done.
- `e2e.py` starts real Claude Code sessions on Haiku, which uses the person's account. **Ask before running it.** Name scenarios to run only the ones near your change; they are listed at the top of `scripts/e2e.py`. It needs a Debug build first.

## Capabilities are declared once

`Core/Sources/QueenBeeCore/Capabilities.swift` is the one place that says what the app can do: every kind of card, each card's settings and limits, and what an agent can do. The orchestrator's instructions, the settings its tools accept and `CAPABILITIES.md` are all made from it.

Whenever you add, remove or change a card, a card setting, an agent tool or a limit on any of them:

1. Change it in `Capabilities.swift` (browser tools: `BrowserTools.swift`, whose definitions and `limits` the reference is built from). Write for the orchestrator: what it does, and what it can't do.
2. Run `./scripts/build.sh`. It rewrites `CAPABILITIES.md`. Never edit that file by hand.
3. Run `cd Core && swift test`. It fails if a setting in `CardPatch` isn't described, if a described setting can't be set, or if `CAPABILITIES.md` is out of date.
4. Commit `CAPABILITIES.md` with the change.

The app also writes the reference into each project as `.queenbee/CAPABILITIES.md` when an orchestrator's session starts, and tells the orchestrator to read it when it has changed. A session that is resumed keeps the system prompt it began with, so anything a running session must learn goes through that file or the session-start hook (`FlowController.startContext`), never through the prompt alone.

Don't describe a capability anywhere else: not in the orchestrator's prompt in `ClaudeLauncher.swift`, and not in a tool's description.

## How the code is written

- Anything that can be decided without a window goes in `Core/` and gets a test there.
- Every colour, type size, spacing step and timing comes from `App/Design/Tokens.swift`.
- Words people read are plain, with no jargon. Claude Code's own option names (effort, permission modes, model) stay exactly as Claude Code writes them. Comments and docs follow the same plain style.
- Swift 6 language mode. The app target isolates to the main actor by default.
- Anything that lets a flow file or the orchestrator do something on the person's Mac without asking needs a line in `SECURITY.md`.
- A change people would notice gets a line under Unreleased in `CHANGELOG.md`.

## Don't, unless asked

- Run `scripts/release.sh`, change version numbers, or edit `appcast.xml`.
- Commit `build/`, `dist/`, `.queenbee/` or a generated `QueenBee.xcodeproj`.
- Push, or open a pull request.

## Done means

- `./scripts/build.sh` succeeds, if you touched anything outside `Core/`.
- `cd Core && swift test` passes.
- `CAPABILITIES.md` is committed if the build changed it.
- You say which end-to-end scenarios you ran, or that you ran none.
- A pull request does one thing and says what changed and how it was checked.
