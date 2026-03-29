## MODIFIED Requirements

### Requirement: Shared-runtime-first service model
The project MUST treat the shared runtime layer and controller service together as the architectural center of the product, with CLI and GUI/app surfaces acting as peer clients of that controller-facing runtime rather than as competing loop hosts.

#### Scenario: Operator uses the tool from the terminal
- **WHEN** a user interacts with automatic control through the command-line surface
- **THEN** the CLI MUST act as a client of the controller service rather than hosting the long-running control loop in-process

#### Scenario: New user-facing surface is added
- **WHEN** the project introduces another user-facing surface such as a menu bar app
- **THEN** that surface MUST integrate as a peer client of the controller service
- **AND** it MUST NOT rely on spawning the CLI as the intended long-term integration boundary

### Requirement: Privileged fan writes are isolated
The system MUST isolate low-level fan write operations behind a dedicated privileged writer daemon, with the non-privileged controller service as the only automatic-control caller of that privileged boundary.

#### Scenario: Control logic requests a fan speed change
- **WHEN** the non-privileged controller service decides to change fan speed
- **THEN** the low-level write operation MUST be performed by the dedicated privileged writer daemon rather than by the controller process itself

#### Scenario: GUI or CLI requests a control action
- **WHEN** a user-facing client needs to affect automatic fan control
- **THEN** that client MUST send the request to the controller service
- **AND** it MUST NOT communicate with the privileged writer daemon directly
