## ADDED Requirements

### Requirement: Menu bar panel displays active control rules summary
When automatic control is running with an active configuration, the menu bar panel MUST display a "Control rules" section that summarizes the thermal domain control rules parsed from the active config file.

#### Scenario: Controller is running with a valid config
- **WHEN** the controller status phase is `running` and `activeConfigPath` points to a readable, valid config file
- **THEN** the panel MUST display a "Control rules" section showing each configured thermal domain (CPU, GPU, and Memory if present)
- **AND** each domain entry MUST show the sensor name, start temperature, max temperature, and the corresponding fan RPM range

#### Scenario: Controller is running but config file is unreadable or malformed
- **WHEN** the controller status phase is `running` but the config file at `activeConfigPath` cannot be read or fails JSON decoding
- **THEN** the panel MUST NOT display the "Control rules" section
- **AND** the rest of the panel MUST remain fully functional

#### Scenario: Controller is not running
- **WHEN** the controller status phase is `idle`, `stopping`, or `failed`
- **THEN** the panel MUST NOT display the "Control rules" section

### Requirement: Control rules reflect the config file at activeConfigPath
The control rules summary MUST be derived by reading and decoding the JSON file at the path provided by `AutomaticControlStatusSnapshot.activeConfigPath`, using the existing `AutomaticControlConfig` model.

#### Scenario: Config is re-read after controller reload
- **WHEN** the user triggers "Reload control" and the controller reports a new or same `activeConfigPath`
- **THEN** the panel MUST re-read and re-parse the config file to reflect any changes

#### Scenario: Config path changes between refreshes
- **WHEN** the controller's `activeConfigPath` changes from one refresh to the next
- **THEN** the panel MUST parse the new config file and update the control rules display accordingly

### Requirement: Control rules display per-fan RPM ranges for multi-fan configs
When the config defines multiple fans, the control rules section MUST show the RPM range for each fan per domain.

#### Scenario: Single fan configured
- **WHEN** the config contains exactly one fan policy
- **THEN** each domain row MUST show that fan's `minimumRPM`–`maximumRPM` range

#### Scenario: Multiple fans configured
- **WHEN** the config contains more than one fan policy
- **THEN** each domain row MUST show the RPM range for each fan, distinguishing them by fan index
