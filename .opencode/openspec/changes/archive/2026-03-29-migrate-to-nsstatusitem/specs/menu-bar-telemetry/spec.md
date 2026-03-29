## MODIFIED Requirements

### Requirement: Menu bar extra shows live thermal summary
The system MUST provide a macOS menu bar status item that shows a compact live summary of aggregate CPU temperature, aggregate GPU temperature, and fan RPM telemetry.

#### Scenario: Summary telemetry is available
- **WHEN** the menu bar app has a fresh telemetry snapshot with aggregate CPU temperature, aggregate GPU temperature, and at least one current fan RPM reading
- **THEN** the menu bar status item MUST render a two-line compact summary using readable labels (`CPU`, `GPU`, `Fan`) and a colored status indicator, without requiring the user to open a terminal window

#### Scenario: Some summary telemetry is unavailable
- **WHEN** one or more summary values cannot be refreshed from the current machine
- **THEN** the menu bar status item MUST remain present
- **AND** it MUST show an explicit unavailable placeholder for the missing value instead of silently omitting the signal

### Requirement: Expanded menu bar panel shows detailed telemetry state
The system MUST provide an expanded panel via `NSPopover` that shows the latest telemetry snapshot in a more readable form than the compact status item label.

#### Scenario: User opens the menu bar panel
- **WHEN** the user clicks the menu bar status item
- **THEN** the system MUST present an `NSPopover` showing the latest available CPU average temperature, GPU average temperature, and fan RPM readings
- **AND** it MUST show enough context for the user to distinguish current values from unavailable values

#### Scenario: User exits from the menu bar panel
- **WHEN** the user chooses the app's quit action from the popover panel
- **THEN** the menu bar app MUST terminate cleanly
