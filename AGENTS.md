# Queen Bee

A Mac app for building and running flows of Claude Code agents on a canvas. Each agent is a live `claude` session in a terminal on a card. Logic cards route each agent's reply to the next cards, and an orchestrator session beside the canvas can edit and run the flow. A companion iPad and iPhone app pairs with the Mac to watch and edit flows.

These are the instructions for any coding agent working in this repo. `README.md` and `CONTRIBUTING.md` say more for people. `CONTRIBUTING.md` holds the full details on building and testing, so read it there rather than in a copy here. If this file and `CONTRIBUTING.md` disagree, `CONTRIBUTING.md` is right: fix this file.

## What you need

- A Mac with Apple silicon, on macOS 26 or later. Nothing here builds or runs on Linux or Windows.
- Xcode 27 and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- [Claude Code](https://claude.com/claude-code) 2.1.287 or later, signed in. Only the app and the end-to-end tests need it; the unit tests don't.

## Where things live

- `Core/` is a Swift package with no UI, shared by the Mac app and the iPad and iPhone app: the flow model, the file store, the routing engine, the orchestrator's tools, the browser's tools, the socket messages and the device link.
- `App/` is the Mac app, in SwiftUI and AppKit.
- `Mobile/` is the iPad and iPhone app, in SwiftUI and UIKit.
- `Helper/` builds `qb`, a small binary inside the app bundle. Hooks, the plugin and the orchestrator's tool server all run it. Its logic lives in `Core/Sources/QueenBeeCore/HelperCommand.swift`, so it is tested there.
- `Plugin/qb-link/` is the Claude Code plugin the app loads into every session.
- `Tools/RemoteCheck/` is a stand-in for a paired device, used by the end-to-end tests.
- `scripts/` holds the builds, the end-to-end tests, the privacy check, the installer and the release script.
- `project.yml` describes the Xcode project. `QueenBee.xcodeproj` is generated from it and not checked in: change `project.yml`, never the project.

## Commands

```sh
./scripts/build.sh                            # Debug build into build/; also rewrites CAPABILITIES.md
./scripts/build.sh Release                    # the same, Release
open build/Build/Products/Debug/QueenBee.app  # run it
./scripts/build-mobile.sh                     # the iPad and iPhone app, for the Simulator
cd Core && swift test                         # unit tests, under a second
./scripts/check-clean.sh                      # fails if anything private is tracked
./scripts/e2e.py [scenario ...]               # end-to-end tests, about nine minutes
```

- `build.sh` regenerates the Xcode project, prints only errors and the result, and exits non-zero when the build fails. Trust its exit code.
- A build from source is called Queen Bee Dev. It keeps its own settings and support folder, so it runs beside an installed copy.
- The launch flags (`--open`, `--float`, `--testing`, `--welcome`) are listed under Launch flags in `CONTRIBUTING.md`. `--testing`, `--welcome` and `QB_SUPPORT_DIR` only work in a Debug build.
- CI runs `swift test`, builds Core and the iPad and iPhone app for the Simulator, builds the Mac app in Debug and Release and checks that the Release build has no test harness, and runs `check-clean.sh` and a secrets check. It doesn't run the end-to-end tests. Run `swift test` before you call any change done.
- The repo is public. Run `./scripts/check-clean.sh` before every commit: it fails if a signing file, `Mobile/Local.xcconfig`, an Apple team id, a private key or a home folder path is tracked.
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
- Every colour, type size, spacing step and timing comes from `App/Design/Tokens.swift`. `Mobile/Design/Tokens.swift` mirrors it value for value, so change a value in both.
- Words people read are plain, with no jargon. Claude Code's own option names (effort, permission modes, model) stay exactly as Claude Code writes them. Comments and docs follow the same plain style.
- Swift 6 language mode. The app target isolates to the main actor by default.
- Anything that lets a flow file or the orchestrator do something on the person's Mac without asking needs a line in `SECURITY.md`.
- A change people would notice gets a line under Unreleased in `CHANGELOG.md`.

## Core

- Two libraries: `QueenBeeCore`, and `QueenBeeLink`, the device link's networking and keys. Each has its own test target in `Core/Tests/`.
- Tests use Swift Testing (`import Testing`, `@Test`), mostly one test file per source file.
- No SwiftUI, AppKit or UIKit. Core is built for both the Mac and iOS, and CI builds it for the iOS Simulator too.

## The Mac app (`App/`)

- There are no unit tests here. A change is checked by a build, and in the running app by the end-to-end tests, which drive it through `App/Testing/TestHarness.swift`. That harness only exists when the app is launched with `--testing`.
- The canvas is an `NSScrollView` with magnification (`App/Canvas/`); each terminal is a SwiftTerm view inside a card.
- `App/Browser/` runs a hidden Chromium per project and controls it over the Chrome DevTools Protocol.
- `App/Remote/` is the Mac's end of the link to the iPad and iPhone app: it decides what a paired device may see and ask for. After a change there, the end-to-end scenario to run is `remote`. After a change to how the Mac sends a card's page to a device or takes a device's input in it, run `browser-remote` too; it starts a heavy browser, so run it on its own. `mirror` checks the copy of a terminal a device is sent.

## The iPad and iPhone app (`Mobile/`)

- The app shows what a paired Mac sends and asks the Mac to do things. `Mobile/Link/RemoteClient.swift` is its end of the link; the Mac's end is `App/Remote/`. The Mac checks every command a device sends, so never rely on this app to enforce a rule.
- There are no unit tests here. Build with `./scripts/build-mobile.sh`, which needs no Apple account. Logic that doesn't need a screen goes in `Core/`, with a test.
- The end-to-end scenarios for a change here are `terminals panels controls typing editing settings-edit parity browser-canned`. They need no Mac app session and no Claude Code. `mobile` and `browser-mobile` pair with a test copy of the Mac app and start real sessions.
- Run those scenarios on an iPad and on an iPhone (`QB_E2E_SIMULATOR="iPhone 17"`), because the two lay the app out differently. Keep one simulator booted at a time.
- The test hooks are the `Debug*.swift` files in `Mobile/Link/`, which only exist in a Debug build. Their launch arguments are listed at the top of `Mobile/Link/DebugLaunch.swift`. `-qbCannedRun 3` shows a made-up run with no Mac, the quick way to look at a screen.
- Signing for a real device reads a team id and bundle id from `Mobile/Local.xcconfig`, which git ignores. Never put a team id in `Mobile/Config.xcconfig` or `project.yml`.
- The app's version lives in `Mobile/Config.xcconfig`, not `project.yml`.

## Don't, unless asked

- Run `scripts/release.sh`, change version numbers, or edit `appcast.xml`.
- Commit `build/`, `dist/`, `.queenbee/`, a generated `QueenBee.xcodeproj` or `Mobile/Local.xcconfig`, or put an Apple team id anywhere in the repo.
- Push, or open a pull request.

## Done means

- `./scripts/build.sh` succeeds, if you touched anything outside `Core/` and `Mobile/`.
- `./scripts/build-mobile.sh` succeeds, if you touched `Mobile/` or `Core/`.
- `cd Core && swift test` passes.
- `CAPABILITIES.md` is committed if the build changed it.
- `./scripts/check-clean.sh` says `clean`.
- You say which end-to-end scenarios you ran, or that you ran none.
- A pull request does one thing and says what changed and how it was checked.
