# QueenBeeCore

The part of Queen Bee with no UI. The root `AGENTS.md` applies here too.

- Run `swift test` from this folder. It takes under a second and is what CI runs.
- Tests use Swift Testing (`import Testing`, `@Test`), in `Tests/QueenBeeCoreTests/`, mostly one file per source file. A change here comes with a test.
- Import only Foundation and CoreGraphics. No SwiftUI, no AppKit: anything that needs a window belongs in `App/`.
- `Capabilities.swift` and `BrowserTools.swift` are where the capabilities reference comes from. `CapabilitiesTests.swift` checks that every setting in `CardPatch` is described, that every described setting can be set, and that the root `CAPABILITIES.md` matches the code. If it fails on that last check, run `../scripts/build.sh` to rewrite the file; don't edit it by hand.
- `HelperCommand.swift` holds all of the `qb` helper's logic (`Helper/main.swift` only calls it), so the helper is tested here.
