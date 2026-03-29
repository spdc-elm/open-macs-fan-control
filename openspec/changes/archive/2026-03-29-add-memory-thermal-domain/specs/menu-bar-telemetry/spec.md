## MODIFIED Requirements

### Requirement: Menu bar extra shows live thermal summary
The system MUST provide a macOS menu bar extra that shows a compact live summary of aggregate CPU temperature, aggregate GPU temperature, aggregate memory temperature, and fan RPM telemetry, rendered as a custom multi-column image label via `ImageRenderer`.

#### Scenario: Summary telemetry is available
- **WHEN** the menu bar app has a fresh telemetry snapshot with aggregate CPU temperature, aggregate GPU temperature, aggregate memory temperature, and at least one current fan RPM reading
- **THEN** the menu bar extra MUST render a multi-column compact summary using readable labels (`CPU`, `GPU`, `Mem`, `Fan`) and a colored status indicator, without requiring the user to open a terminal window

#### Scenario: Some summary telemetry is unavailable
- **WHEN** one or more summary values (including memory) cannot be refreshed from the current machine
- **THEN** the menu bar extra MUST remain present
- **AND** it MUST show an explicit unavailable placeholder for the missing value instead of silently omitting the signal

### Requirement: Expanded menu bar panel shows detailed telemetry state
The system MUST provide an expanded menu bar panel that shows the latest telemetry snapshot in a more readable form than the compact menu bar label.

#### Scenario: User opens the menu bar panel
- **WHEN** the user opens the menu bar extra
- **THEN** the panel MUST show the latest available CPU average temperature, GPU average temperature, memory average temperature, and fan RPM readings
- **AND** it MUST show enough context for the user to distinguish current values from unavailable values
