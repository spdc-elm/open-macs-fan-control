## MODIFIED Requirements

### Requirement: Expanded menu bar panel shows detailed telemetry state
The system MUST provide an expanded menu bar panel that shows the latest telemetry snapshot in a more readable form than the compact menu bar label. When automatic control is running with a valid config, the panel MUST also include a control rules summary section between the controller status area and the fans detail area.

#### Scenario: User opens the menu bar panel
- **WHEN** the user opens the menu bar extra
- **THEN** the panel MUST show the latest available CPU average temperature, GPU average temperature, memory average temperature, and fan RPM readings
- **AND** it MUST show enough context for the user to distinguish current values from unavailable values

#### Scenario: User opens the menu bar panel while controller is running
- **WHEN** the user opens the menu bar extra and the controller is running with a valid active config
- **THEN** the panel MUST show the telemetry readings, controller status, control rules summary, fan details, and action buttons in that order

#### Scenario: User exits from the menu bar panel
- **WHEN** the user chooses the app's quit action from the menu bar panel
- **THEN** the menu bar app MUST terminate cleanly
