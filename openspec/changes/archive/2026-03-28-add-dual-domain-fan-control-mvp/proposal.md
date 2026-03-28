## Why

The repo has already de-risked the basic read and write hardware paths enough to move beyond bring-up and assemble the first real automatic-control MVP. The next step is to turn the current sensor work into a usable control loop that combines CPU and GPU thermal demand, is driven by a config file, and preserves the project's privileged-write isolation.

## What Changes

- Add a first automatic fan-control mode that evaluates both CPU and GPU thermal domains instead of binding a fan to only one sensor
- Add a config-driven control model with per-domain temperature thresholds and per-fan policy selection
- Add a long-running control loop that reads sensors, computes target RPM demand, smooths transitions, and avoids overly frequent writes
- Add a minimal privileged helper boundary for fan write operations so the main control logic stays unprivileged by default
- Define fail-safe behavior for invalid sensor data, helper communication failure, and shutdown so the machine returns to automatic control when the MVP cannot safely continue

## Capabilities

### New Capabilities
- `dual-domain-fan-control`: config-driven automatic fan control that combines CPU and GPU thermal demand, computes target RPMs, and applies them through a safe control loop

### Modified Capabilities
- None

## Impact

- Swift control-loop architecture and runtime process split
- Configuration loading and validation for CPU/GPU thresholds and fan policy
- Sensor aggregation over existing CPU/GPU source modeling work
- Privileged write path design between the main controller and helper
- Safety behavior for throttled writes, stale sensors, helper failure, and restore-to-auto handling
