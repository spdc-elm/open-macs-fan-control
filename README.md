# macs-fan-control

Swift macOS fan-control workspace organized around a shared runtime (`FanControlRuntime`) plus a CLI client (`fan-control-cli`), with room for future GUI/menu bar surfaces over the same core APIs.

## Current architecture

- `FanControlRuntime` owns reusable hardware access, telemetry assembly, configuration loading, and control-support logic.
- `fan-control-cli` is a thin command-line shell over that runtime.
- `fan-control-menu-bar` is a SwiftUI menu bar shell over the same runtime.
- Future GUI/menu bar work should depend on `FanControlRuntime` directly rather than shelling out to the CLI.

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
- `swift run fan-control-cli auto --config <path> [--dry-run]`
- `swift run fan-control-cli write --fan <index> --rpm <target>`
- Remove the daemon with: `sudo swift run fan-control-cli daemon remove`
- `swift run fan-control-menu-bar`

## Menu bar app packaging

- Chosen app host path: a SwiftPM menu bar executable plus a small local bundling script.
- Build/package a runnable app bundle with: `./scripts/package-menu-bar-app.sh`
- Launch the packaged app with: `open dist/MacsFanControlMenuBar.app`

## Reference work

This project's Apple Silicon SMC temperature-key family tables were adapted with reference to:

- [dkorunic/iSMC](https://github.com/dkorunic/iSMC)

In particular, the current Swift implementation borrows from iSMC's documented `src/temp.txt` Apple Silicon key mapping approach and its model-family grouping strategy.
