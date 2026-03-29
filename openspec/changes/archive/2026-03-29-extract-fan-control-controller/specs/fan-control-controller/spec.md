## ADDED Requirements

### Requirement: Dedicated controller service hosts automatic control
The system MUST host long-running automatic fan control inside a dedicated non-privileged controller executable/service rather than inside a CLI or GUI entrypoint.

#### Scenario: Automatic control is started from a client
- **WHEN** a CLI or GUI client requests that automatic control start
- **THEN** the controller service MUST become the process that owns the control loop for that session
- **AND** the requesting client MUST remain a control surface rather than the loop host

### Requirement: Controller owns config loading, validation, and session transitions
The controller MUST load and validate automatic-control configuration before activating a control session, and it MUST treat stop and reload as explicit session transitions.

#### Scenario: Valid config starts a controller-managed session
- **WHEN** a client requests start or reload with a valid config path and the writer daemon is reachable
- **THEN** the controller MUST validate the config against current hardware and writer-visible fan inventory before entering the running state

#### Scenario: Invalid reload does not replace a healthy session
- **WHEN** a client requests reload and the candidate config fails validation or cannot be activated safely
- **THEN** the controller MUST reject the reload
- **AND** it MUST keep the existing active control session unchanged if one is already running

### Requirement: Controller publishes structured lifecycle and control status
The controller MUST expose structured status for local clients, including lifecycle phase, active config identity, recent telemetry timing, per-fan control state, and the latest error context.

#### Scenario: Client queries controller status
- **WHEN** a CLI or GUI client requests status from the controller
- **THEN** the controller MUST return machine-readable state that distinguishes idle, starting, running, stopping, and failed conditions
- **AND** the response MUST include enough detail for clients to present current control health without inspecting privileged writer internals directly

### Requirement: Controller is the only client of the root writer daemon
The controller MUST be the sole non-privileged service that issues automatic-control write requests to the root writer daemon.

#### Scenario: Fan target must be applied during automatic control
- **WHEN** the controller determines that a managed fan needs a new target RPM
- **THEN** it MUST issue the write through the root writer daemon
- **AND** no CLI or GUI client MUST call the root writer daemon directly for that automatic-control write

### Requirement: Controller handles safe session shutdown and restart boundaries
The controller MUST restore automatic fan mode for managed fans when a handled stop, restart, or controller-managed failure ends the active session.

#### Scenario: Controller stops or restarts a control session
- **WHEN** the controller transitions an active session to stopped state because of a client stop request, handled shutdown, or successful replacement restart
- **THEN** it MUST attempt to restore automatic mode for all managed fans before the old session is considered ended
