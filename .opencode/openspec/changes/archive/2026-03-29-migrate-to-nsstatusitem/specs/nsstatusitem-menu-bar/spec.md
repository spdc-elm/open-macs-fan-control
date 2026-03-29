## ADDED Requirements

### Requirement: Menu bar label renders as a custom two-line NSView
The system MUST render the menu bar status item label using a custom `NSView` hosted inside an `NSStatusItem`, replacing the previous `MenuBarExtra` text label.

#### Scenario: Normal telemetry display
- **WHEN** the menu bar app has a fresh telemetry snapshot with CPU temperature, GPU temperature, and fan RPM data
- **THEN** the status item MUST display a two-line layout where the first line shows CPU and GPU temperatures with readable labels (`CPU`, `GPU`) and the second line shows fan RPM with a readable label (`Fan`) and a colored status indicator dot

#### Scenario: Telemetry partially unavailable
- **WHEN** one or more telemetry values cannot be read from the current machine
- **THEN** the status item MUST show a placeholder (`--`) for the unavailable value while continuing to display available values in the same two-line layout

#### Scenario: All telemetry unavailable
- **WHEN** no telemetry values can be read
- **THEN** the status item MUST still be visible in the menu bar with placeholder values for all fields

### Requirement: Status indicator dot renders with correct color
The system MUST render a colored circular indicator in the status item label that reflects the current automatic control phase.

#### Scenario: Controller is running
- **WHEN** the automatic control phase is `running`
- **THEN** the indicator dot MUST render in green

#### Scenario: Controller is idle
- **WHEN** the automatic control phase is `idle`
- **THEN** the indicator dot MUST render in gray

#### Scenario: Controller is starting or stopping
- **WHEN** the automatic control phase is `starting` or `stopping`
- **THEN** the indicator dot MUST render in orange

#### Scenario: Controller has failed
- **WHEN** the automatic control phase is `failed` or an error message is present
- **THEN** the indicator dot MUST render in red

### Requirement: Status item label adapts to system appearance
The system MUST render the status item label text in a color that is legible under both light and dark macOS menu bar appearances.

#### Scenario: System switches between light and dark mode
- **WHEN** the macOS appearance changes between light and dark mode
- **THEN** the status item label text MUST remain legible by using semantic system colors (e.g., `NSColor.labelColor`)

### Requirement: Clicking the status item shows the detail panel
The system MUST show a popover containing the existing detail panel when the user clicks the status item.

#### Scenario: User clicks the status item
- **WHEN** the user clicks the menu bar status item
- **THEN** the system MUST present an `NSPopover` anchored to the status item containing the `MenuBarPanel` SwiftUI view with full telemetry details and control actions

#### Scenario: User clicks outside the popover
- **WHEN** the popover is visible and the user clicks outside of it
- **THEN** the popover MUST dismiss

### Requirement: Status item label updates automatically
The system MUST update the status item label whenever the underlying telemetry or controller status changes.

#### Scenario: Telemetry snapshot refreshes
- **WHEN** the telemetry store publishes a new snapshot
- **THEN** the status item label MUST redraw to reflect the updated values within the same refresh cycle
