## Purpose

Define the behavior for a custom multi-line, multi-color menu bar label that renders telemetry data in a three-column layout with a colored status indicator, using SwiftUI `ImageRenderer` to produce an `NSImage` for the `MenuBarExtra` label.

## Requirements

### Requirement: Menu bar label renders as a custom multi-column layout
The system MUST render the menu bar label as a three-column layout (CPU temperature, GPU temperature, Fan RPM) with a colored status indicator dot, using `ImageRenderer` to produce an `NSImage` displayed via `MenuBarExtra`.

#### Scenario: Normal telemetry display
- **WHEN** the menu bar app has a fresh telemetry snapshot with CPU temperature, GPU temperature, and fan RPM data
- **THEN** the label MUST display three columns, each with a readable title (`CPU`, `GPU`, `Fan`) above its value, plus a colored status indicator dot

#### Scenario: Telemetry partially unavailable
- **WHEN** one or more telemetry values cannot be read from the current machine
- **THEN** the label MUST show a placeholder (`--`) for the unavailable value while continuing to display available values in the same layout

#### Scenario: All telemetry unavailable
- **WHEN** no telemetry values can be read
- **THEN** the label MUST still be visible in the menu bar with placeholder values for all fields

### Requirement: Status indicator dot renders with correct color
The system MUST render a colored circular indicator in the menu bar label that reflects the current automatic control phase.

#### Scenario: Controller is running
- **WHEN** the automatic control phase is `running`
- **THEN** the indicator dot MUST render in green

#### Scenario: Controller is idle
- **WHEN** the automatic control phase is `idle`
- **THEN** the indicator dot MUST render in gray

#### Scenario: Controller is starting or stopping
- **WHEN** the automatic control phase is `starting` or `stopping`
- **THEN** the indicator dot MUST render in red

#### Scenario: Controller has failed
- **WHEN** the automatic control phase is `failed` or an error message is present
- **THEN** the indicator dot MUST render in red

### Requirement: Menu bar label uses legible text color
The system MUST render the menu bar label text in white to ensure legibility against the menu bar background.

#### Scenario: Label is displayed
- **WHEN** the menu bar label is rendered
- **THEN** the label text MUST use white color with the title row at reduced opacity and the value row at full opacity

### Requirement: Menu bar label updates automatically
The system MUST update the menu bar label whenever the underlying telemetry or controller status changes.

#### Scenario: Telemetry snapshot refreshes
- **WHEN** the telemetry store publishes a new snapshot
- **THEN** the menu bar label MUST re-render to reflect the updated values
