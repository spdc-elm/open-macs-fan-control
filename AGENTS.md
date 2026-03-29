# Project context

- This repo is about building a macOS fan-control tool, informed by reverse-engineering notes from an existing reference implementation.
- Current direction: a **shared-runtime** architecture with multiple client surfaces (CLI, menu bar app), a dedicated automatic-control controller service, and a privileged root writer daemon for low-level fan writes.
- Current control idea: aggregate thermal input from **CPU** and **GPU** domains, then use a conservative policy such as `max(cpu_demand, gpu_demand)`.

# Where to look

- `openspec/specs/`
  - repo-level capability map and long-lived behavior
  - check here first when you need overall project understanding
- `openspec/changes/<change>/`
  - local truth for one active change
- `openspec/changes/archive/YYYY-MM-DD-<change>/`
  - historical decisions; read only when the current task clearly depends on prior choices
- `.local-research/reverse-engineering/`
  - reverse-engineering notes about the reference binary (not tracked in git; local-only)

# Working stance

- Do **not** read the full archive by default.
- Do **not** start every new conversation from blank-slate explore if repo-level specs already exist.
- Prefer this context-loading order:
  1. relevant `openspec/specs/`
  2. active change artifacts
  3. archived changes only if needed

# OpenSpec complement

OpenSpec is strong at **change-level structure**. The missing piece is often **repo-level continuity**.

So in this repo:

- treat `openspec/specs/` as the closest thing to project-wide truth
- treat change artifacts as change-local truth
- treat archives as selective reference, not default context
- if repo-level specs are missing or thin, say so explicitly instead of pretending the project is well-specified

# Current project understanding

From the current notes and current exploration decisions:

- the reference implementation uses **main process reads + privileged helper writes**
- helper installation uses **Authorization + SMJobBless + launchd**
- aggregate / average sensors already exist in the original product
- the main limitation appears to be the control model being tied to **one sensor key per fan mode**
- the architecture uses a shared runtime consumed by multiple client shells rather than a single monolithic executable

# Current project baseline

- Primary implementation language: **Swift**
- Product shape: **shared runtime + CLI + menu bar app + controller service + privileged root writer daemon**
- Startup model: **start on user login**, not system boot
- Privilege model: sensor reading and control logic run unprivileged; only the root writer daemon has elevated privileges for low-level fan writes

## Current module layout

- `src/CSMCBridge/` — C bridging header for SMC access
- `src/FanControlRuntime/` — reusable hardware, telemetry, config, IPC, and control-support logic
- `src/FanControlCLI/` — CLI parsing, terminal-facing command flow, and executable entrypoint (`fan-control-cli`)
- `src/FanControlController/` — dedicated automatic-control service (`fan-control-controller`)
- `src/FanControlMenuBar/` — SwiftUI menu bar app (`fan-control-menu-bar`)
- `src/RootWriterDaemon/` — minimal privileged helper for fan writes (`root-writer-daemon`)
- `Package.swift` — package name: `MacsFanControl`

## Current architecture direction

- Boundary: **shared runtime** → thin client shells (CLI, menu bar app) → controller service → root writer daemon.
- GUI clients reuse shared Swift APIs directly; they do **not** shell out to the CLI.
- CLI remains a first-class operator/debugging surface, not a disposable prototype.

## Local build / sudo caveat

- Avoid using `sudo swift build` or `sudo swift run` unless root is strictly required for the command being tested.
- If root-owned artifacts end up inside `.build/` after a sudo run, later non-sudo builds may fail with `Operation not permitted` when SwiftPM tries to overwrite them.
- In that case, prefer removing the specific root-owned build artifacts (or cleaning `.build/`) before rebuilding as the normal user.

## OpenSpec single-change shortcut

- For `opsx apply` and `opsx archive`: if exactly one active change exists, do not ask the user to choose; use that single active change directly.

# Menu bar app development

## Build and run

- Build: `swift build --product fan-control-menu-bar`
- Package into `.app` bundle: `bash scripts/package-menu-bar-app.sh`
- Run: `open dist/MacsFanControlMenuBar.app`
- The `.app` bundle is required for menu bar items to display correctly; running the bare executable will not show `NSStatusItem` or `MenuBarExtra` labels.

## UI debugging via process logs

When debugging menu bar UI issues, use `NSLog` statements and read them back via `log show`:

1. Add `NSLog("[FanControlMenuBar] ...")` at key points (e.g., `applicationDidFinishLaunching`, image render size, button existence checks).
2. Launch the bare binary in the background: `.build/debug/fan-control-menu-bar &`
3. Read logs: `log show --predicate 'process == "fan-control-menu-bar"' --last 10s --style compact`

This gives a feedback loop for verifying whether lifecycle methods fire, whether views/images have non-zero sizes, and whether data is flowing — without relying solely on visual inspection by the user.

## Menu bar label rendering approach

The current approach uses **SwiftUI `ImageRenderer`** to render a custom SwiftUI view into an `NSImage`, which is then set as the `MenuBarExtra` label via `Image(nsImage:)`.

Key details:
- Set `renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0` for crisp rendering on Retina displays.
- Set `nsImage.isTemplate = false` to preserve colors (otherwise macOS forces monochrome).
- This avoids the complexity of `NSStatusItem` + `NSPopover` while still allowing multi-line, multi-color labels.
- The `MenuBarExtra(.window)` style handles popover positioning, dismissal, and animation automatically.

### What didn't work (lessons learned)

- **NSStatusItem + custom NSView as button subview**: the button's hit-testing and sizing interact poorly with embedded subviews; the status item may appear invisible even when the view has correct intrinsic size.
- **NSStatusItem + NSPopover**: popover positioning relative to the status bar button is unreliable; it may appear above the screen or with incorrect alignment. The `.transient` behavior also requires manual `NSApp.activate(ignoringOtherApps: true)` for agent apps.
- **`@main` on `NSApplicationDelegate` with `static func main()`**: in Swift 6 strict concurrency, `@MainActor` isolation on the class doesn't always propagate to `static func main()` correctly. Using a separate `main.swift` with explicit `NSApplication.shared` / `app.delegate` / `app.run()` is more reliable, but the SwiftUI `App` lifecycle is simpler when it suffices.
