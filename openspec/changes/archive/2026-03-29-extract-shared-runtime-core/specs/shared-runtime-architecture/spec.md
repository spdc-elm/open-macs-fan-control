## ADDED Requirements

### Requirement: Reusable fan-control runtime exists outside client entrypoints
The system MUST place reusable hardware access, telemetry assembly, configuration loading, and control-support APIs in a shared runtime layer that is not itself the CLI or GUI entrypoint.

#### Scenario: CLI uses shared runtime
- **WHEN** the command-line client needs temperature, fan, or control-support functionality
- **THEN** it MUST obtain that functionality through the shared runtime layer rather than defining the reusable logic only inside the CLI target

#### Scenario: GUI uses shared runtime
- **WHEN** a GUI or menu bar client is introduced
- **THEN** it MUST be able to consume the same shared runtime layer directly without parsing CLI text output

### Requirement: Client surfaces remain thin over the shared runtime
The system MUST keep client-specific concerns separated from the shared runtime layer.

#### Scenario: CLI-specific behavior stays in CLI shell
- **WHEN** command parsing or terminal formatting is needed
- **THEN** that behavior MUST live in the CLI client layer rather than inside the shared runtime API boundary

#### Scenario: GUI-specific behavior stays in GUI shell
- **WHEN** app lifecycle, menu bar UI, or other GUI presentation behavior is needed
- **THEN** that behavior MUST live in the GUI client layer rather than inside the shared runtime API boundary
