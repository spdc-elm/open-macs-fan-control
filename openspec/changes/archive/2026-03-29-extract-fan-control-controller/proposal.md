## Why

The current automatic-control loop still lives inside `src/FanControlCLI/AutomaticControlCommand.swift`, so the CLI is acting as both a user-facing shell and the long-running control engine. That is the wrong boundary for the next phase: after the root writer daemon change lands, the project needs a dedicated controller executable that owns the loop and becomes the stable integration point for both CLI and GUI clients.

## What Changes

- Extract the long-running automatic-control orchestration out of `AutomaticControlCommand.runLoop(...)` into a dedicated `fan-control-controller`-style executable/service.
- Move controller-owned responsibilities behind that executable boundary: config loading and validation, telemetry sampling, dual-domain demand planning, loop lifecycle, safe shutdown, and calls to the root writer daemon.
- Refactor the CLI from loop host into a client/control surface that starts, stops, queries, and observes the controller rather than running automatic control in-process.
- Define the GUI/menu bar app as a peer client of the controller and explicitly reject GUI → CLI subprocess chaining as the target architecture.
- Add an IPC/service contract for controller control and status reporting, including realistic handling for stale telemetry, writer-daemon failures, and restart/reload semantics.
- Sequence this work after the root writer daemon change so the controller talks to the intended privileged writer boundary instead of baking in the current CLI-launched helper shape.
- **BREAKING**: automatic-control lifecycle ownership moves out of the CLI process; client commands and service startup behavior will change accordingly.

## Capabilities

### New Capabilities
- `fan-control-controller`: Define the dedicated controller service that hosts automatic control and exposes client-facing control/status operations.

### Modified Capabilities
- `fan-control-service`: Sharpen the service shape into three layers: CLI/GUI clients, a non-privileged controller service, and a low-level privileged writer daemon.
- `shared-runtime-architecture`: Require long-running automatic-control orchestration to live outside CLI/GUI entrypoints, with clients remaining thin over shared runtime and controller-facing APIs.
- `dual-domain-fan-control`: Reframe automatic-control lifecycle ownership around the controller service while preserving the existing dual-domain demand and fail-safe requirements.

## Impact

- Affected code: `src/FanControlCLI/AutomaticControlCommand.swift`, `src/FanControlCLI/CLI.swift`, `src/FanControlRuntime/AutomaticControl.swift`, `src/FanControlRuntime/FanWriter.swift`, `src/FanControlMenuBar/**`, and `Package.swift`.
- Affected systems: automatic-control process model, IPC boundaries, status reporting, login/session lifecycle, and integration between user-facing clients and the privileged write path.
- Dependency: this change follows the root writer daemon change and assumes the privileged write boundary is already daemonized.
