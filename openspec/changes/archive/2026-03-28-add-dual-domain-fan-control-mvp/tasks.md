## 1. Configuration and control model

- [x] 1.1 Define the automatic-control config schema for polling, CPU/GPU domain selection, thresholds, and per-fan policy
- [x] 1.2 Implement config loading and validation that rejects unknown sensors, invalid threshold ranges, and incomplete fan policy entries
- [x] 1.3 Add a dry initialization path that prints or logs the resolved control configuration before any fan override begins

## 2. Dual-domain demand calculation

- [x] 2.1 Add controller-side domain resolvers that read the configured CPU and GPU inputs from the unified temperature inventory
- [x] 2.2 Implement per-domain RPM demand mapping from start/max temperature thresholds to each fan's min/max RPM range
- [x] 2.3 Implement final target selection as `max(cpuDemand, gpuDemand)` for each managed fan and cover both CPU-dominant and GPU-dominant cases

## 3. Smoothed automatic control loop

- [x] 3.1 Create the long-running control loop that polls sensors on the configured interval and tracks per-fan control state
- [x] 3.2 Add smoothing, hysteresis, and write-throttling rules so target changes do not translate into raw writes every poll
- [x] 3.3 Add safety handling for stale sensor data and runtime control errors so managed fans are released back to automatic mode

## 4. Privileged writer boundary

- [x] 4.1 Extract the low-level fan mode and RPM write operations behind a narrow privileged writer interface
- [x] 4.2 Implement an MVP helper/writer path that can receive target requests from the unprivileged controller and perform the underlying fan writes
- [x] 4.3 Implement restore-to-auto behavior for handled shutdown, controller failure, and writer communication failure

## 5. Operator workflow and validation

- [x] 5.1 Add a CLI or service entrypoint for starting automatic control with a specified config file
- [x] 5.2 Preserve the existing `temps`, `fans`, and manual `write` validation commands as debugging tools alongside the automatic mode
- [x] 5.3 Validate end-to-end behavior on target hardware, including config validation, dual-domain control behavior, throttled writes, and restore-to-auto safety
