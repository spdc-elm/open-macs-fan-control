## ADDED Requirements

### Requirement: Temperature sensor validation output
The system MUST provide an operator-visible validation path that prints readable temperature sensor values from the target Mac.

#### Scenario: Operator runs temperature validation
- **WHEN** the operator invokes the temperature validation path on a supported machine
- **THEN** the system prints temperature sensor values in the terminal
- **AND** those values are suitable for manual comparison with an external reference

### Requirement: Fan RPM readback validation output
The system MUST provide an operator-visible validation path that prints current fan RPM values.

#### Scenario: Operator runs fan RPM readback validation
- **WHEN** the operator invokes the fan RPM readback path on a supported machine
- **THEN** the system prints current fan RPM values in the terminal

### Requirement: Manual fan write verification path
The system MUST provide a manual fan write validation path that attempts to change fan speed through the intended low-level control path.

#### Scenario: Operator validates fan speed writes
- **WHEN** the operator invokes the manual fan write validation path with a requested fan target
- **THEN** the system attempts the fan speed change through the intended privileged write mechanism
- **AND** the result can be manually verified by observing the reported or externally visible fan RPM change

### Requirement: MVP write validation uses a helper-like privileged boundary
The MVP write validation path MUST use a narrowly scoped privileged mechanism that can be run with `sudo` during development while remaining aligned with a future dedicated helper design.

#### Scenario: Operator runs privileged write validation during bring-up
- **WHEN** the operator runs the MVP fan write validation flow during development
- **THEN** the privileged portion of the flow is executed through a minimal write-focused path rather than assuming the full production packaging is already complete

### Requirement: Handled exits restore automatic fan control
The system MUST attempt to restore the default automatic fan control mode on all handled exit and handled error paths after a manual fan write validation attempt.

#### Scenario: Operator exits after manual validation
- **WHEN** the operator ends a manual fan write validation run through a normal, handled shutdown path
- **THEN** the system attempts to restore automatic fan control before exiting

#### Scenario: Validation hits a handled error
- **WHEN** the manual fan write validation path encounters a handled runtime error after fan override has been applied
- **THEN** the system attempts to restore automatic fan control before terminating the validation flow
