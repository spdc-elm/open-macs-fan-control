## Why

The project direction has converged on a Swift-based, terminal-first macOS tool with privileged fan writes isolated from the main control path. Before investing in the full daemon/helper product shape, the highest-risk unknowns need to be reduced by proving that Swift can read the target machine's temperature sensors and fan RPMs and can drive a visible fan speed change through the intended low-level path.

## What Changes

- Add an MVP validation path focused on hardware I/O rather than full automatic control
- Verify readable terminal output for temperature sensors and current fan RPM values
- Verify a manual fan write path whose result can be checked against visible RPM changes
- Keep this change scoped to feasibility validation, not full login-start automation or production control policy

## Capabilities

### New Capabilities
- `swift-mvp-validation`: minimal operator-visible validation flows for probing temperatures, reading fan RPMs, and verifying manual fan write behavior on the target machine

### Modified Capabilities
- None

## Impact

- Swift-based macOS implementation direction
- Low-level hardware access paths for sensor reads, fan RPM reads, and fan RPM writes
- Early validation of the future control stack before daemonization and full helper packaging are completed

## Current Status

- The Swift Package / terminal-first MVP scaffold is now in place and builds successfully.
- AppleSMC fan RPM readback is partially de-risked: the current MVP can read plausible fan RPM / min / max values on the current machine.
- Temperature validation is not yet de-risked: the current SMC-only candidate-key approach produces unstable or implausible readings on Apple Silicon and is not sufficient to claim success.
- Manual fan write / restore flows exist in code, but the empirical validation tasks remain open until they are confirmed on the target machine.

## Next Phase Focus

- Add an IOHID-based temperature validation path for Apple Silicon instead of relying only on guessed SMC temperature keys.
- Keep AppleSMC as the fan RPM / fan write path while treating IOHID temperature probing as the next highest-priority uncertainty to retire.
