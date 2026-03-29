## Why

The current menu bar label is wider than necessary for an always-visible surface, and its status dot does not clearly communicate whether automatic fan control is actually active. This makes the label consume more status bar space while still leaving the auto-control state ambiguous.

## What Changes

- Compact the menu bar label into a denser grouped layout for CPU, GPU, and fan summary values.
- Make the status indicator visible and map it to automatic-control lifecycle state rather than using a generic "not failed" green state.
- Keep the expanded panel behavior and control actions unchanged in this change.

## Capabilities

### Modified Capabilities
- `menu-bar-telemetry`: Refine the compact summary presentation so it uses less space and makes automatic-control state legible at a glance.

## Impact

- Affected code: `src/FanControlMenuBar/AppState.swift`
- Affected UI: compact menu bar summary label only
- Out of scope: splitting the menu bar into multiple independent status items
