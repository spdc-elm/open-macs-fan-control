## Why

The current privileged writer path is still an MVP: `HelperFanWriterClient` launches `sudo -n <executable> writer-service`, which ties low-level fan writes to one CLI executable, depends on pre-authorized sudo behavior, and does not give the new menu bar / future controller surfaces a stable privileged endpoint. Now that the repo already has a shared runtime plus multiple client surfaces, it needs one minimal root daemon that owns fan writes and can be reused by every client.

## What Changes

- Introduce a dedicated root writer daemon that is responsible only for fan inspection, manual-mode transitions, target RPM writes, automatic-mode restoration, and orderly shutdown/cleanup.
- Replace the current `sudo -n` helper launch path in `FanWriter.swift` and the direct privileged CLI write path with a shared daemon client used by CLI automatic control, CLI write flows, and future GUI/controller clients.
- Add a local-first daemon installation/startup workflow suitable for personal use on one machine, including explicit lifecycle management and failure reporting, without taking on productized helper signing/notarization workflows in this change.
- Keep configuration loading, control-loop orchestration, policy decisions, and UI/app lifecycle outside the daemon so the privileged boundary stays narrow.
- **BREAKING**: the temporary `writer-service` subprocess workflow and any local scripts that depend on `sudo -n <cli> writer-service` will be replaced by a daemon install/connect workflow.

## Capabilities

### New Capabilities
- `root-writer-daemon`: Define the locally installed root daemon, its minimal IPC surface, session cleanup behavior, and failure semantics for fan-write operations.

### Modified Capabilities
- `fan-control-service`: Tighten the privileged-write architecture so one minimal root daemon is the only privileged component used by CLI and future GUI/controller clients.
- `dual-domain-fan-control`: Update automatic-control behavior so privileged writes flow through daemon-backed sessions instead of an ad hoc sudo-launched helper subprocess.

## Impact

- Affected code: `Package.swift`, `src/FanControlRuntime/FanWriter.swift`, `src/FanControlCLI/AutomaticControlCommand.swift`, `src/FanControlCLI/Probes.swift`, CLI command parsing, and new daemon/install assets.
- Affected systems: privilege model, local IPC boundary, daemon installation/startup, fan-write cleanup on disconnect/shutdown, and replacement of the current `sudo -n` path.
- Affected docs/specs: `openspec/specs/fan-control-service/spec.md`, `openspec/specs/dual-domain-fan-control/spec.md`, and a new `root-writer-daemon` capability spec.
