## MODIFIED Requirements

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

### Requirement: Automatic control fails safe back to automatic mode
The system MUST relinquish manual fan control when the controller cannot continue safe automatic control.

#### Scenario: Required thermal input becomes unavailable
- **WHEN** the configured CPU or GPU domain cannot be refreshed reliably during automatic control
- **THEN** the controller MUST stop issuing new manual targets for the affected control session
- **AND** it MUST request restoration of automatic fan mode for managed fans

#### Scenario: Controller shutdown or writer failure is handled
- **WHEN** the active automatic-control session ends through a handled controller shutdown, controlled restart, or privileged-writer failure
- **THEN** the controller MUST attempt to restore automatic fan mode for managed fans before declaring the session stopped or failed
