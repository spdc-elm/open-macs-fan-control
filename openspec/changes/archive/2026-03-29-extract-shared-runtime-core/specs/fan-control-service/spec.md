## ADDED Requirements

### Requirement: Shared-runtime-first service model
The project MUST treat the shared runtime layer as the architectural center of the product, with CLI and GUI/app surfaces acting as clients of that runtime rather than competing implementations.

#### Scenario: New user-facing surface is added
- **WHEN** the project introduces another user-facing surface such as a menu bar app
- **THEN** that surface MUST integrate through the shared runtime architecture rather than redefining core fan-control behavior independently

## REMOVED Requirements

### Requirement: Terminal-first service model
**Reason**: The product is no longer intended to be modeled as terminal-only. The CLI remains important, but it is now one client surface over a shared runtime that may also support GUI/app shells.

**Migration**: Treat the CLI as the initial operational surface and preserve its workflows, while allowing future GUI/menu bar clients to consume the same runtime without violating the service model.
