## MODIFIED Requirements

### Requirement: Privileged fan writes are isolated
The system MUST isolate low-level fan write operations behind a single minimal root writer daemon so the main control logic, CLI, and future GUI/controller surfaces remain unprivileged.

#### Scenario: Control logic requests a fan speed change
- **WHEN** the non-privileged control path decides to change fan speed
- **THEN** it MUST issue that request to the root writer daemon rather than performing the low-level write inside the main process
- **AND** the root writer daemon MUST perform the low-level write operation

#### Scenario: Another client surface needs fan-write access
- **WHEN** a CLI flow or future GUI/controller surface needs fan inspection or fan-write access
- **THEN** it MUST reuse the same root writer daemon boundary
- **AND** it MUST not introduce a separate privileged helper path for that client surface
