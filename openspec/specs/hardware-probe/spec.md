## Purpose

Define the minimal hardware validation behaviors that must exist before the broader fan-control product is treated as technically de-risked.

## Requirements

### Requirement: Temperature probe output for validation
The project MUST provide a way to print readable temperature sensor values so they can be compared against an external reference during bring-up.

#### Scenario: Operator probes temperatures
- **WHEN** the operator runs the temperature probing path on a supported machine
- **THEN** the tool prints temperature sensor values suitable for manual comparison with an external reference

### Requirement: Fan RPM readback for validation
The project MUST provide a way to print current fan RPM values during MVP validation.

#### Scenario: Operator reads current fan speeds
- **WHEN** the operator runs the fan readback path on a supported machine
- **THEN** the tool prints current fan RPM values

### Requirement: Manual fan write validation path
The project MUST provide a way to attempt a manual fan speed change for MVP verification.

#### Scenario: Operator validates fan speed write behavior
- **WHEN** the operator requests a manual fan speed change through the validation path
- **THEN** the system attempts the change through the intended privileged mechanism
- **AND** the result can be verified by observing fan RPM changes externally
