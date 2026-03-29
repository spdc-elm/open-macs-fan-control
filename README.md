# macs-fan-control

Swift macOS fan-control workspace organized around a shared runtime (`FanControlRuntime`), a dedicated automatic-control service (`fan-control-controller`), a privileged root writer daemon (`root-writer-daemon`), and thin CLI / menu bar clients over those shared boundaries.

## Prerequisites

- macOS 13 (Ventura) or later
- Swift 6.0+ (included with Xcode 16+)
- Apple Silicon Mac (Intel Macs are not currently tested)

## Current architecture

- `FanControlRuntime` owns reusable hardware access, telemetry assembly, configuration loading, controller IPC models, and control-support logic.
- `fan-control-controller` is the non-privileged long-running host for automatic control.
- `root-writer-daemon` is the only privileged component allowed to read or write low-level fan state.
- `fan-control-cli` and `fan-control-menu-bar` are peer clients of the controller service rather than loop hosts or privileged writer callers.

## Current temperature model

- IOHID temperature services are read as one provider.
- SMC temperature keys are read as another provider.
- Aggregate sensors such as CPU/GPU averages are computed on top of the unified readings.
- Disk remains a reserved provider slot for later SMART/NVMe work.

## Current CLI surface

- Install or refresh the root writer daemon with: `sudo swift run fan-control-cli daemon install`
- Inspect daemon status with: `swift run fan-control-cli daemon status`
- `swift run fan-control-cli temps [--friendly|--raw]`
- `swift run fan-control-cli fans`
- `swift run fan-control-cli auto start --config <path> [--dry-run]`
- `swift run fan-control-cli auto reload --config <path>`
- `swift run fan-control-cli auto status`
- `swift run fan-control-cli auto stop`
- `swift run fan-control-cli write --fan <index> --rpm <target>`
- Remove the daemon with: `sudo swift run fan-control-cli daemon remove`
- `swift run fan-control-controller`
- `swift run fan-control-menu-bar`

## Common local workflows

### Automatic control from the CLI

- First make sure the privileged writer daemon is installed: `sudo swift run fan-control-cli daemon install`
- Start automatic control: `swift run fan-control-cli auto start --config <path>`
- Validate a config without starting control: `swift run fan-control-cli auto start --config <path> --dry-run`
- Inspect controller state: `swift run fan-control-cli auto status`
- Reload a changed config: `swift run fan-control-cli auto reload --config <path>`
- Stop automatic control: `swift run fan-control-cli auto stop`

Notes:
- `auto start` will try to launch `fan-control-controller` for you if it is not already running.
- The old shorthand `swift run fan-control-cli auto --config <path>` is still accepted as a compatibility alias for `auto start`, but the explicit `start|reload|status|stop` form is now the canonical interface.

### Running the controller directly

- Start the controller service yourself: `swift run fan-control-controller`
- The controller listens on: `~/Library/Application Support/macs-fan-control/fan-control-controller.sock`
- The controller log file is: `~/Library/Application Support/macs-fan-control/fan-control-controller.log`

## Automatic-control boundary

- CLI / menu bar surfaces talk to the local `fan-control-controller` socket for automatic-control lifecycle operations.
- The controller validates config, owns session lifecycle, samples telemetry, computes demand, and restores automatic fan mode on handled stop / restart / failure.
- Only the controller talks to the root writer daemon for automatic-control fan writes.

## Menu bar app packaging

- Chosen app host path: a SwiftPM menu bar executable plus a small local bundling script.
- Build/package a runnable app bundle with: `./scripts/package-menu-bar-app.sh`
- The packaged app bundle is written to: `dist/MacsFanControlMenuBar.app`
- The app binary inside the bundle is: `dist/MacsFanControlMenuBar.app/Contents/MacOS/fan-control-menu-bar`
- Launch the packaged app with: `open dist/MacsFanControlMenuBar.app`
- For development-only runs without packaging, you can also use: `swift run fan-control-menu-bar`

## Build outputs

- SwiftPM debug executables are built under: `.build/debug/`
- The controller binary is typically: `.build/debug/fan-control-controller`
- The CLI binary is typically: `.build/debug/fan-control-cli`
- The menu bar binary is typically: `.build/debug/fan-control-menu-bar`

## Reference work

This project's Apple Silicon SMC temperature-key family tables were adapted with reference to:

- [dkorunic/iSMC](https://github.com/dkorunic/iSMC)

In particular, the current Swift implementation borrows from iSMC's documented `src/temp.txt` Apple Silicon key mapping approach and its model-family grouping strategy.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
