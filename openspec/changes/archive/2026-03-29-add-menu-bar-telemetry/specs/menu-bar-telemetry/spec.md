## ADDED Requirements

### Requirement: Menu bar extra shows live thermal summary
The system MUST provide a macOS menu bar extra that shows a compact live summary of aggregate CPU temperature, aggregate GPU temperature, and fan RPM telemetry.

#### Scenario: Summary telemetry is available
- **WHEN** the menu bar app has a fresh telemetry snapshot with aggregate CPU temperature, aggregate GPU temperature, and at least one current fan RPM reading
- **THEN** the menu bar extra MUST render a compact summary using those values without requiring the user to open a terminal window

#### Scenario: Some summary telemetry is unavailable
- **WHEN** one or more summary values cannot be refreshed from the current machine
- **THEN** the menu bar extra MUST remain present
- **AND** it MUST show an explicit unavailable placeholder for the missing value instead of silently omitting the signal

### Requirement: Expanded menu bar panel shows detailed telemetry state
The system MUST provide an expanded menu bar panel that shows the latest telemetry snapshot in a more readable form than the compact menu bar label.

#### Scenario: User opens the menu bar panel
- **WHEN** the user opens the menu bar extra
- **THEN** the panel MUST show the latest available CPU average temperature, GPU average temperature, and fan RPM readings
- **AND** it MUST show enough context for the user to distinguish current values from unavailable values

#### Scenario: User exits from the menu bar panel
- **WHEN** the user chooses the app's quit action from the menu bar panel
- **THEN** the menu bar app MUST terminate cleanly

### Requirement: Menu bar telemetry refreshes automatically
The system MUST refresh menu bar telemetry automatically while the menu bar app is running.

#### Scenario: Refresh succeeds
- **WHEN** the configured refresh interval elapses while the menu bar app is active
- **THEN** the system MUST attempt a new telemetry snapshot
- **AND** it MUST update the compact summary and expanded panel with the latest successful readings

#### Scenario: Refresh fails after a prior success
- **WHEN** a telemetry refresh attempt fails after the app has already shown a previous snapshot
- **THEN** the system MUST preserve the last successful snapshot for display
- **AND** it MUST indicate that current refresh data is unavailable or stale rather than presenting the failure as fresh live data
