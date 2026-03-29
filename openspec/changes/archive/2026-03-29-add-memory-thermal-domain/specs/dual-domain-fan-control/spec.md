## ADDED Requirements

### Requirement: Memory average aggregate sensor is available
The system MUST compute a `memory_average` aggregate temperature reading by averaging all base readings with `type == "memory"`.

#### Scenario: Memory sensors are present
- **WHEN** the temperature inventory contains one or more base readings with `type == "memory"`
- **THEN** the system MUST produce an aggregate reading with `rawName == "memory_average"`, `source == .aggregate`, `group == "Memory"`, and `type == "memory"`
- **AND** its value MUST be the arithmetic mean of all matching base readings

#### Scenario: No memory sensors are present
- **WHEN** the temperature inventory contains no base readings with `type == "memory"`
- **THEN** the system MUST NOT produce a `memory_average` aggregate reading

### Requirement: Optional memory domain participates in fan target calculation
The system MUST support an optional `memoryDomain` in the automatic-control configuration. When present, memory thermal demand MUST participate in the conservative `max()` fan target policy alongside CPU and GPU.

#### Scenario: memoryDomain is configured and sensor is available
- **WHEN** the configuration includes a `memoryDomain` with a valid sensor reference and threshold range
- **THEN** the system MUST resolve the memory temperature reading each control cycle
- **AND** the fan target MUST be `max(cpuDemand, gpuDemand, memoryDemand)`

#### Scenario: memoryDomain is configured but sensor is unavailable
- **WHEN** the configuration includes a `memoryDomain` whose sensor cannot be found in the inventory
- **THEN** the system MUST reject the configuration with an appropriate error, consistent with existing CPU/GPU domain validation

#### Scenario: memoryDomain is absent from configuration
- **WHEN** the configuration does not include a `memoryDomain` field
- **THEN** the system MUST behave identically to the existing dual-domain model (`max(cpuDemand, gpuDemand)`)
- **AND** no memory-related validation or resolution MUST occur

## MODIFIED Requirements

### Requirement: Config-driven dual-domain control settings
The system MUST load and validate automatic fan-control settings through the controller-managed control session, including CPU domain, GPU domain, optional memory domain, threshold ranges, fan policy, and polling settings.

#### Scenario: Valid automatic-control config is loaded
- **WHEN** a client starts or reloads automatic control with a valid configuration file
- **THEN** the controller MUST load the configured CPU and GPU domain settings before starting the control loop
- **AND** the controller MUST load the optional memory domain settings if present
- **AND** the controller MUST load the fan policy and polling settings needed to run automatic control

#### Scenario: Invalid config blocks automatic control
- **WHEN** the configuration file is missing required domain thresholds, references unknown sensors, or contains invalid threshold ranges (including for the optional memory domain if present)
- **THEN** the controller MUST refuse to start or replace the automatic-control session
- **AND** it MUST report a configuration error without placing managed fans into manual mode for the rejected session

### Requirement: Dual-domain thermal demand determines fan target
The system MUST evaluate CPU, GPU, and (when configured) memory thermal demand separately and derive the requested fan target from the most demanding domain.

#### Scenario: CPU demand dominates
- **WHEN** the computed CPU-domain target RPM is the highest among all configured domains
- **THEN** the system MUST use the CPU-domain target as the requested fan target for that control cycle

#### Scenario: GPU demand dominates
- **WHEN** the computed GPU-domain target RPM is the highest among all configured domains
- **THEN** the system MUST use the GPU-domain target as the requested fan target for that control cycle

#### Scenario: Memory demand dominates
- **WHEN** the memory domain is configured and the computed memory-domain target RPM is the highest among all configured domains
- **THEN** the system MUST use the memory-domain target as the requested fan target for that control cycle

### Requirement: Automatic control fails safe back to automatic mode
The system MUST relinquish manual fan control when the controller cannot continue safe automatic control.

#### Scenario: Required thermal input becomes unavailable
- **WHEN** the configured CPU, GPU, or memory domain cannot be refreshed reliably during automatic control
- **THEN** the controller MUST stop issuing new manual targets for the affected control session
- **AND** it MUST request restoration of automatic fan mode for managed fans
