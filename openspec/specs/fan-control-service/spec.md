## Purpose

Define the long-lived service shape for this project: shared-runtime-first operation with CLI as the initial operator surface, user-login startup as the near-term default, and privilege isolation for low-level fan writes.

## Requirements

### Requirement: Shared-runtime-first service model
The project MUST treat a shared runtime layer as the architectural center of the product, with CLI and future GUI/app surfaces acting as clients of that runtime.

#### Scenario: Operator uses the tool from the terminal
- **WHEN** a user interacts with the project through the currently supported operator surface
- **THEN** the CLI acts as one client of the shared runtime rather than the whole product architecture

#### Scenario: New user-facing surface is added
- **WHEN** the project introduces another user-facing surface such as a menu bar app
- **THEN** that surface integrates through the shared runtime instead of reimplementing core fan-control behavior independently

### Requirement: User-session startup by default
The service MUST support starting automatically at user login as the default self-start model for the near-term product.

#### Scenario: User enables login startup
- **WHEN** the user configures the tool to start automatically
- **THEN** the tool starts when that user logs into macOS

### Requirement: Privileged fan writes are isolated
The system MUST isolate low-level fan write operations from the main control logic through a minimal privileged boundary.

#### Scenario: Control logic requests a fan speed change
- **WHEN** the non-privileged control path decides to change fan speed
- **THEN** the low-level write operation is performed by a dedicated privileged component rather than by the entire main process
