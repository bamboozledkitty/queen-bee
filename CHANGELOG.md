# Changelog

All notable changes to Queen Bee are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Approval** cards, which hold a message until you approve, edit or reject it.
- **Script** cards, which run a shell command and route on whether it succeeded. A command you didn't type yourself waits for you to allow it.
- **Flow** cards, which run another of the project's flows as one step.
- Resting the pointer on a card type in the palette explains it in a sentence, with an example.
- A link's settings list the messages it carried in the run on show.
- Every run is kept, with its path, answers and messages. The Log tab can put an earlier run back on the canvas.
- **Run from here** starts a run at any card with a message you give it, and a card a run stopped at can be retried.
- Cost: each agent's card shows what it used in the run, a figure beside the zoom control shows the flow's total, and clicking it breaks the total down by session and by run.
- Agent roles: an agent's instructions, model, effort and permissions saved under a name and reused from the palette in any flow.
- A Start card can run on a schedule (every so often, daily, or on chosen days) or when a file or folder in the project changes.
- Groups: cards framed together under a name, which fold into one card.
- **Tidy Up** (⇧⌘L) lays a flow out left to right in the order its links run.
- **Find** (⌘F) goes to a card or flow by name, and a map in the corner shows the whole flow and where the window is looking.

### Changed

- A card only shows as live or waiting from run marks while a run is under way.
- Wording across the app is plainer: settings, tips, warnings and log lines say what happens without the technical terms. An agent's state reads "ready" and "stopped" where it read "idle" and "exited", and counts of "hand-offs" are now "messages passed".

### Added

- Dragging to the edge of the canvas pans it, so a link, a card, a selection box, a resize or a new card from the palette can reach what is out of view.

## [0.2.0] - 2026-10-09

### Added

- A terminal installer, `scripts/install.sh`, that fetches the latest release, checks its signature and installs it without the Gatekeeper prompt.
- A first-run walk-through of agents, logic cards and the orchestrator, which also checks that Claude Code is installed and new enough. **Help → Welcome to Queen Bee** shows it again.
- Undo and redo for every change to a flow, including the orchestrator's, from the Edit menu.
- Selecting several cards with Shift-click or a dragged box. Selected cards move, nudge with the arrow keys, duplicate, copy, paste and delete together.
- Dragged cards line up with nearby cards, with a guide line, or settle on the grid. Option places a card freely.
- Right-click menus on cards, links and the canvas.
- Escape deselects, ⌃⌘S shows or hides the projects list, and ⌥⌘0 the side panel.
- The run log, End-card output and the last run's marks are kept between launches, with a Clear button on the log.
- Notifications when a card needs you or a run ends while the app is in the background, with a setting to turn them off.
- Below 40% zoom, cards show their name and state in large type.

### Fixed

- The app's own message, such as Claude Code not being found, can be dismissed with a click.

### Changed

- Zooming from the zoom control, the menu, fit and a double-click on a card's title is animated. Hover, selection and panel changes ease instead of snapping.
- A link being dragged previews the route it will take, and lands on the input of a card that would accept it.
- The card settings panel is rebuilt: the name is edited in its header, settings sit in ruled rows, and Delete and the session's Start or Restart share a footer.
- Clicking into a terminal no longer opens that card's settings. Click the card's title for those.
- An empty flow shows a small note pointing at the orchestrator in place of the box in the middle of the canvas. Closing it is remembered.
- Floating panels no longer cast a shadow.

## [0.1.1] - 2026-10-09

### Fixed

- **Queen Bee → Check for Updates…** was always greyed out. It now turns on once the updater is ready.

## [0.1.0] - 2026-10-09

First public release.

### Added

- A canvas of cards joined by links. Agent cards are live Claude Code sessions in terminals you can type into.
- Logic cards that route each agent's finished reply: Start, If / Else, Switch, And, Or, Prompt, Loop until, End and Note.
- An orchestrator session beside the canvas that can build, edit, run and steer the flow.
- Runs with a log, per-card pass counts, live link marking and saved End-card output.
- Project folders in a sidebar, with flows saved in `<project>/.queenbee/flows/`.
- Light and dark appearance, and an app icon that follows it.
- Updates: the app checks for new versions and installs them, and **Queen Bee → Check for Updates…** checks on demand.

### Security

- A folder that already contains flows is only opened after you confirm you trust it.
- Cards can only use the permission modes the app offers. A mode that skips permission checks is refused from flow files and from the orchestrator's tools.
- Each session gets its own secret for talking to the app, and only the orchestrator's session can use the flow-editing tools.
- An End card's save path can't leave the project folder through a symlink.
- The test harness is compiled out of release builds.
- Releases are signed with a Developer ID and use the hardened runtime. They are not yet notarized by Apple.

[Unreleased]: https://github.com/bamboozledkitty/queen-bee/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bamboozledkitty/queen-bee/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/bamboozledkitty/queen-bee/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bamboozledkitty/queen-bee/releases/tag/v0.1.0
