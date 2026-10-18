# The app

The SwiftUI and AppKit app. The root `AGENTS.md` applies here too.

- There are no unit tests here. Build with `./scripts/build.sh` from the repo root; it must say `BUILD SUCCEEDED`. Move logic that can be decided without a window into `Core/` so it can be tested.
- Checking a change in the running app means the end-to-end tests (`./scripts/e2e.py`), which use the person's Claude Code account. Ask first. They drive the app through `Testing/TestHarness.swift`, which only exists when the app is launched with `--testing`.
- Every colour, type size, spacing step and timing comes from `Design/Tokens.swift`. Don't write a number or a colour in a view.
- The canvas is an `NSScrollView` with magnification (`Canvas/`); each terminal is a SwiftTerm view inside a card.
- `Browser/` runs a hidden Chromium per project and controls it over the Chrome DevTools Protocol. The tools an agent uses on it are defined in `Core`'s `BrowserTools.swift`.
- `Sessions/ClaudeLauncher.swift` writes the orchestrator's prompt. Never describe a capability there. A resumed session keeps the prompt it began with, so anything a running session must learn goes through `.queenbee/CAPABILITIES.md` or `FlowController.startContext`.
