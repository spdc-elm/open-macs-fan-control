## Purpose

Define the long-lived behavior for config-driven automatic fan control that evaluates CPU and GPU thermal demand together, applies smoothed/throttled fan targets, and fails safe back to automatic mode.
## Requirements
### Requirement: Config-driven dual-domain control settings
The system MUST load and validate automatic fan-control settings through the controller-managed control session, including CPU domain, GPU domain, threshold ranges, fan policy, and polling settings.

#### Scenario: Valid automatic-control config is loaded
- **WHEN** a client starts or reloads automatic control with a valid configuration file
- **THEN** the controller MUST load the configured CPU and GPU domain settings before starting the control loop
- **AND** the controller MUST load the fan policy and polling settings needed to run automatic control

#### Scenario: Invalid config blocks automatic control
- **WHEN** the configuration file is missing required domain thresholds, references unknown sensors, or contains invalid threshold ranges
- **THEN** the controller MUST refuse to start or replace the automatic-control session
- **AND** it MUST report a configuration error without placing managed fans into manual mode for the rejected session

### Requirement: Dual-domain thermal demand determines fan target
The system MUST evaluate CPU and GPU thermal demand separately and derive the requested fan target from the more demanding domain.

#### Scenario: CPU demand dominates
- **WHEN** the computed CPU-domain target RPM is higher than the computed GPU-domain target RPM
- **THEN** the system MUST use the CPU-domain target as the requested fan target for that control cycle

#### Scenario: GPU demand dominates
- **WHEN** the computed GPU-domain target RPM is higher than the computed CPU-domain target RPM
- **THEN** the system MUST use the GPU-domain target as the requested fan target for that control cycle

### Requirement: Automatic control smooths and throttles fan writes
The system MUST avoid writing a freshly computed target RPM directly on every polling cycle and MUST apply smoothing and write throttling before issuing fan updates.

#### Scenario: Target changes within the active threshold band
- **WHEN** domain temperatures move within their configured threshold ranges
- **THEN** the system MUST move the commanded fan target toward the requested RPM gradually rather than jumping immediately to each newly computed value

#### Scenario: Writes would occur too frequently
- **WHEN** a newly computed target would cause overly frequent low-level fan writes without a meaningful control change
- **THEN** the system MUST defer or suppress that write until its throttling rules allow another update

### Requirement: Low-level fan writes stay behind a privileged writer boundary
The system MUST perform low-level manual-mode changes, target RPM writes, and automatic-mode restoration for automatic control through a dedicated root writer daemon boundary rather than inside the main control logic.

#### Scenario: Control loop applies a new target
- **WHEN** the unprivileged controller decides that a managed fan needs a new target RPM
- **THEN** it MUST issue that request through its root writer daemon session
- **AND** the daemon MUST perform the low-level write operation

### Requirement: Automatic control fails safe back to automatic mode
The system MUST relinquish manual fan control when the controller cannot continue safe automatic control.

#### Scenario: Required thermal input becomes unavailable
- **WHEN** the configured CPU or GPU domain cannot be refreshed reliably during automatic control
- **THEN** the controller MUST stop issuing new manual targets for the affected control session
- **AND** it MUST request restoration of automatic fan mode for managed fans

#### Scenario: Controller shutdown or writer failure is handled
- **WHEN** the active automatic-control session ends through a handled controller shutdown, controlled restart, or privileged-writer failure
- **THEN** the controller MUST attempt to restore automatic fan mode for managed fans before declaring the session stopped or failed

