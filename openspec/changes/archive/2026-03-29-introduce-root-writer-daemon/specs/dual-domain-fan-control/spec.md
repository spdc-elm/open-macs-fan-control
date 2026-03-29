## MODIFIED Requirements

### Requirement: Low-level fan writes stay behind a privileged writer boundary
The system MUST perform low-level manual-mode changes, target RPM writes, and automatic-mode restoration for automatic control through a dedicated root writer daemon boundary rather than inside the main control logic.

#### Scenario: Control loop applies a new target
- **WHEN** the unprivileged controller decides that a managed fan needs a new target RPM
- **THEN** it MUST issue that request through its root writer daemon session
- **AND** the daemon MUST perform the low-level write operation

### Requirement: Automatic control fails safe back to automatic mode
The system MUST relinquish manual fan control when it cannot continue safe automatic control.

#### Scenario: Required thermal input becomes unavailable
- **WHEN** the configured CPU or GPU domain cannot be refreshed reliably during automatic control
- **THEN** the system MUST stop issuing new manual targets for the affected control session
- **AND** the system MUST request restoration of automatic fan mode for managed fans

#### Scenario: Controller exit or writer-session loss is handled
- **WHEN** the automatic-control process exits through a handled shutdown, loses its root writer daemon session, or detects that the root writer daemon is unavailable
- **THEN** the system MUST stop issuing new manual targets for the affected control session
- **AND** it MUST either request restoration of automatic mode before disconnecting or rely on daemon-side session cleanup to restore any still-owned fans
