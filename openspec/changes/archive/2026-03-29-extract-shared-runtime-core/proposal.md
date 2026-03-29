## Why

The current Swift package mixes reusable hardware/runtime logic with a single CLI executable target, which makes the menu bar app direction awkward and keeps future surface expansion coupled to one entrypoint. Now that the project intends to support both CLI and GUI shells, it needs an explicit shared runtime layer instead of treating the MVP executable as the architecture.

## What Changes

- Extract the reusable hardware, telemetry, config, and control-facing APIs out of the current MVP executable target into a shared Swift module.
- Rename the current MVP/CLI-facing package surface to stable CLI naming (for example `FanControlCLI` / `fan-control-cli`) so it is clearly one client of the shared runtime rather than the whole product.
- Define the project’s long-lived product shape as shared runtime + CLI + future GUI/menu bar app, instead of “terminal-first only”.
- **BREAKING**: package/target/module names and source layout may change as part of the split.
- Update repo-level documentation/context so future work does not keep assuming the old MVP-only structure.

## Capabilities

### New Capabilities
- `shared-runtime-architecture`: Define the requirement that reusable fan-control logic lives in a shared runtime layer that can be consumed by multiple app surfaces.

### Modified Capabilities
- `fan-control-service`: Change the service-shape requirement from terminal-first-only to shared-runtime-first with CLI as the initial operational surface and GUI/menu bar support as an allowed peer surface.

## Impact

- Affected code: `Package.swift`, `src/FanControlMVP/**`, CLI entrypoints, and any new shared module / renamed source directories.
- Affected systems: package structure, module boundaries, build targets, and future app integration points.
- Affected docs/specs: `AGENT.md`, `openspec/specs/fan-control-service/spec.md`, and new shared-runtime capability spec.
