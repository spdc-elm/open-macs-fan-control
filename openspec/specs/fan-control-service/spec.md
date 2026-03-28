## Purpose

Define the long-lived service shape for this project: terminal-first operation, user-login startup as the near-term default, and privilege isolation for low-level fan writes.

## Requirements

### Requirement: Terminal-first service model
The project MUST target a terminal-first operating model rather than a GUI-first application model.

#### Scenario: Operator uses the tool from the terminal
- **WHEN** a user interacts with the project in its primary supported mode
- **THEN** the interaction model is command-line driven

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
