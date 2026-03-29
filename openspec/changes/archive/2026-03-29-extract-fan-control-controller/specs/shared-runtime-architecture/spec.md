## MODIFIED Requirements

### Requirement: Reusable fan-control runtime exists outside client entrypoints
The system MUST place reusable hardware access, telemetry assembly, configuration loading, control-planning APIs, and controller/client service contracts in a shared runtime layer that is not itself the CLI or GUI entrypoint.

#### Scenario: Controller uses shared runtime
- **WHEN** the dedicated controller executable hosts automatic fan control
- **THEN** it MUST obtain configuration, telemetry, planning, and lifecycle support through the shared runtime layer rather than defining those reusable behaviors only inside the controller target

#### Scenario: CLI and GUI use shared runtime-facing service contracts
- **WHEN** a CLI or GUI client needs automatic-control functionality
- **THEN** it MUST use the shared runtime’s controller-facing APIs or models
- **AND** it MUST NOT rely on parsing CLI text output to integrate with automatic control

### Requirement: Client surfaces remain thin over the shared runtime
The system MUST keep client-specific concerns separated from the shared runtime and controller boundary so that CLI and GUI surfaces remain clients rather than loop hosts or privileged-writer callers.

#### Scenario: CLI-specific behavior stays in CLI shell
- **WHEN** command parsing, terminal formatting, or operator-oriented command dispatch is needed
- **THEN** that behavior MUST live in the CLI client layer
- **AND** the long-running automatic-control loop MUST NOT live in the CLI entrypoint

#### Scenario: GUI-specific behavior stays in GUI shell
- **WHEN** app lifecycle, menu bar UI, or other GUI presentation behavior is needed
- **THEN** that behavior MUST live in the GUI client layer
- **AND** the GUI MUST NOT directly communicate with the privileged writer daemon
