## Context

The repo currently exposes its validated operator flow through a Swift CLI, while the underlying telemetry pieces already exist: `TemperatureInventory.refreshAll()` produces aggregate readings including `cpu_core_average` and `gpu_cluster_average`, and `SMCConnection.readFans()` exposes current RPM data for each fan. That means the hard part is not hardware discovery; it is introducing a UI surface that consumes those readings safely and repeatedly through the emerging shared-runtime boundary.

Feasibility is good, with two important caveats. Apple’s current SwiftUI API provides `MenuBarExtra` on macOS 13+, including a richer `.window` style for data-heavy panels, so the UI surface itself is straightforward. But this change should no longer assume the current CLI package shape is the long-term architecture, and it should not prematurely lock the GUI host to one packaging path before the shared-runtime split lands.

> Migration note: the shared-runtime extraction now lives concretely at `FanControlRuntime`, while the validated CLI shell lives at `FanControlCLI` / `fan-control-cli`. Menu bar work should target `FanControlRuntime` directly and treat the CLI as a sibling client, not as an integration layer.

## Goals / Non-Goals

**Goals:**
- Add a menu bar surface that shows CPU average temperature, GPU average temperature, and current fan RPM at a glance
- Reuse the shared telemetry/runtime APIs instead of parsing CLI stdout or duplicating hardware access logic
- Keep the current CLI workflows working unchanged as the primary bring-up and debugging interface
- Define the menu bar app as a thin GUI shell over shared runtime APIs
- Leave room for a practical app-hosting path that produces a menu bar-capable macOS app bundle with `LSUIElement` support

**Non-Goals:**
- Adding menu-bar-based fan writes or automatic-control configuration in this change
- Replacing the existing CLI product as the primary operator workflow
- Solving background login startup, helper installation, or code-sign/notarization beyond the minimum shape needed for local development
- Expanding sensor coverage beyond the already available aggregate CPU/GPU temperatures and current fan RPM data

## Decisions

### Decision: Build the menu bar UI with SwiftUI `MenuBarExtra`
- **Chosen:** implement the UI as a macOS 13+ SwiftUI menu bar app using `MenuBarExtra`, using a compact title for the bar item and a `.window`-style panel for richer detail.
- **Why:** Apple’s current API directly supports persistent menu bar extras and richer popover-like windows, which matches the desired “glanceable summary plus expanded details” interaction.
- **Alternative considered:** use `NSStatusItem` and hand-built AppKit menus.
- **Why not:** AppKit would work, but it adds more imperative glue for a first version without buying much value for this telemetry-only scope.

### Decision: Extract a shared telemetry snapshot layer from existing probe code
- **Chosen:** add a reusable snapshot API that returns the menu bar’s needed values as structured data: CPU average, GPU average, fan summaries, refresh time, and per-signal availability.
- **Why:** the current CLI probe path prints formatted text, while the menu bar needs typed values and explicit “unavailable” states. A shared snapshot layer keeps the hardware reads in one place and lets both CLI and UI consume the same inventory through the shared runtime architecture.
- **Alternative considered:** spawn the existing CLI commands and parse stdout.
- **Why not:** that would be brittle, slower, and would mix presentation formatting with data transport.

### Decision: Keep the CLI and menu bar app as separate entrypoints over shared runtime code
- **Chosen:** preserve the CLI workflow and introduce a second entrypoint for the menu bar app that depends on the same telemetry/runtime module.
- **Why:** this avoids regressing the existing debugging/validation workflow while letting the menu bar app adopt the macOS app lifecycle cleanly.
- **Alternative considered:** fold menu bar behavior into the existing CLI executable behind a new command.
- **Why not:** a true menu bar experience needs app lifecycle, run loop, bundle metadata, and `LSUIElement`; treating that as just another CLI mode would blur concerns and complicate packaging.

### Decision: Leave the app host choice open until the shared runtime split lands
- **Chosen:** require the menu bar app to consume shared runtime APIs, but defer the final host choice between a SwiftPM-plus-bundling path and an Xcode macOS app target/project.
- **Why:** the menu bar feature’s durable requirement is the shared runtime boundary, not a premature commitment to one app packaging workflow.
- **Alternative considered:** lock the change now to a SwiftPM-only app-bundle assembly path.
- **Why not:** that is feasible, but it would overfit to the current repo shape before the architectural refactor is complete.

### Decision: Refresh on a timer with graceful stale/unavailable handling
- **Chosen:** poll telemetry on a modest interval (for example, once every 1-2 seconds), update the label/panel from the latest successful snapshot, and surface unavailable readings explicitly instead of hiding them.
- **Why:** these metrics change continuously but do not need sub-second UI churn; explicit stale/unavailable handling is safer than presenting misleading blanks.
- **Alternative considered:** refresh only when the menu opens.
- **Why not:** that would make the menu bar title less useful as a live at-a-glance status surface.

## Risks / Trade-offs

- **The GUI host choice is still open while the shared-runtime split is in flight** → make the runtime boundary the hard requirement first, then choose the least painful app host once that boundary exists
- **Some machines may lack one of the aggregate signals at runtime** → model telemetry availability explicitly and show fallback text such as `GPU --` rather than failing the whole UI
- **Frequent polling could create unnecessary sensor/UI churn** → keep the refresh interval conservative and reuse the existing inventory/runtime rather than reinitializing hardware connections on every tiny view update
- **The menu bar title has very limited horizontal space** → keep the bar item compact and move full detail into the expanded panel
- **Future write/control features could pressure the menu bar app into becoming the main product shell** → keep this change read-only and retain the CLI as the operational source of truth

## Migration Plan

1. Wait for the shared-runtime extraction to establish the correct telemetry API boundary.
2. Add a menu bar app entrypoint that renders compact summary text plus a richer detail panel over the shared runtime APIs.
3. Choose the app host path that best fits the post-refactor structure, then add the bundle metadata and packaging needed for `LSUIElement=true`.
4. Validate that the CLI still works unchanged and that the menu bar app can refresh readings on supported hardware.
5. Document how to launch the menu bar app for local testing without changing the existing CLI workflows.

## Open Questions

- Should the menu bar title show both temperatures and fan RPM at once, or rotate/prioritize when space becomes tight on smaller menu bars?
- Do we want one combined fan RPM summary in v1 (for example, average or first fan), or multiple fan rows only inside the expanded panel?
- After the shared-runtime split, is a pure SwiftPM-plus-bundling workflow sufficient for the team, or will implementation quickly justify switching to an Xcode app target for day-to-day development?
