## ADDED Requirements

### Requirement: Root writer daemon is the only privileged fan-write component
The system MUST provide a locally installed root writer daemon as the only privileged component responsible for fan inspection and low-level fan-write operations.

#### Scenario: Client inspects fan state through the daemon
- **WHEN** an unprivileged client needs current fan inventory or fan state
- **THEN** it MUST obtain that information through the root writer daemon’s local IPC boundary
- **AND** it MUST not need to launch a new `sudo` subprocess for that request

### Requirement: Root writer daemon exposes a minimal write-focused API
The root writer daemon MUST expose only the minimal operations needed to support fan-write clients: inspect fans, place a fan into manual mode when needed for a session, apply a target RPM, restore automatic mode, and perform orderly shutdown/cleanup.

#### Scenario: Client applies a target RPM
- **WHEN** a client requests a target RPM for a fan through the daemon
- **THEN** the daemon MUST ensure the fan is in manual mode before issuing the low-level target write
- **AND** it MUST keep configuration loading, control-loop orchestration, and policy decisions outside the daemon boundary

### Requirement: Root writer daemon starts independently of control sessions
The system MUST support a local installation/startup workflow for the root writer daemon so CLI and future GUI/controller clients can connect without replacing each control session with `sudo -n <executable> writer-service`.

#### Scenario: Operator starts automatic or manual control after daemon install
- **WHEN** the root writer daemon has been installed and started through the supported local workflow
- **THEN** CLI fan-write operations MUST connect to the daemon instead of spawning the old sudo-launched helper path

#### Scenario: Daemon is unavailable
- **WHEN** a client cannot connect to the root writer daemon
- **THEN** the client MUST fail with an explicit daemon-availability error
- **AND** it MUST not silently fall back to direct privileged fan writes

### Requirement: Root writer daemon cleans up session-owned manual fan state
The root writer daemon MUST track manual-control ownership per client session and restore automatic mode for any fan still owned by that session when the session ends or the daemon shuts down.

#### Scenario: Client disconnects unexpectedly
- **WHEN** a client connection owning one or more manually managed fans disconnects without first restoring them
- **THEN** the daemon MUST attempt to restore automatic mode for those session-owned fans during cleanup

#### Scenario: Conflicting client tries to control an owned fan
- **WHEN** one client attempts to write a fan that is already owned by another live session
- **THEN** the daemon MUST reject the conflicting write request with an explicit conflict error
- **AND** it MUST preserve the existing owner’s cleanup responsibility until that session ends or releases the fan
