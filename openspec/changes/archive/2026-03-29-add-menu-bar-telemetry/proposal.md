## Why

The project can already read aggregate CPU and GPU temperatures plus current fan RPMs, but the only supported operator surface today is the CLI. A lightweight menu bar surface would make those live thermal signals visible at a glance while preserving the existing CLI workflow and fitting into the new shared-runtime architecture.

## What Changes

- Add a macOS menu bar extra that shows compact live telemetry for CPU average temperature, GPU average temperature, and current fan RPM.
- Add a richer menu bar panel that shows the same readings with refresh state, unavailable-sensor fallback messaging, and a quit action.
- Consume a shared telemetry snapshot/runtime path so the UI can reuse core Swift APIs rather than scraping CLI text output.
- Package the menu bar experience as an optional app surface alongside the existing CLI workflow rather than replacing it.

## Capabilities

### New Capabilities
- `menu-bar-telemetry`: Display live aggregate thermal and fan telemetry from the macOS menu bar without requiring the user to keep a terminal window open.

### Modified Capabilities

None.

## Impact

- Affected code: shared runtime/telemetry code, CLI integration boundaries, and new macOS menu bar app files/packaging assets.
- Affected systems: macOS UI lifecycle, timer-driven telemetry refresh, and app-bundle packaging (`Info.plist` / `LSUIElement`) for a menu bar-only surface.
- Dependencies: this change depends on the shared-runtime split landing first; no new third-party runtime dependency is required, and the UI can rely on native macOS APIs such as `SwiftUI.MenuBarExtra` on macOS 13+.
