## 1. Controller runtime extraction

- [x] 1.1 Land the root writer daemon prerequisite and expose the non-privileged writer-daemon client contract the controller will call
- [x] 1.2 Extract controller-owned automatic-control runtime pieces from `src/FanControlCLI/AutomaticControlCommand.swift` into shared runtime types for session lifecycle, sampling/apply cycles, and structured status
- [x] 1.3 Refactor config/bootstrap code in `src/FanControlRuntime/AutomaticControl.swift` so controller start and reload flows can validate candidate configs without CLI-owned behavior

## 2. Controller service implementation

- [x] 2.1 Add a dedicated `fan-control-controller` executable/service target and entrypoint in `Package.swift`
- [x] 2.2 Implement the local client/controller IPC contract for start, stop, reload, and status operations using shared runtime request/response models
- [x] 2.3 Implement controller session transitions for idle, starting, running, stopping, failed, including safe automatic-mode restoration on handled stop/restart/failure

## 3. Client integration

- [x] 3.1 Refactor CLI automatic-control commands so they act as controller clients instead of hosting the long-running loop in-process
- [x] 3.2 Update CLI help/output to describe controller-backed automatic control and surface structured controller status/errors cleanly
- [x] 3.3 Update the menu bar / GUI path to consume controller status and control operations through the controller client boundary rather than any direct writer integration

## 4. Verification and repo truth

- [x] 4.1 Add or update tests covering controller config validation, reload failure preserving the current session, stale-sensor fail-safe behavior, and writer-daemon failure handling
- [x] 4.2 Validate end-to-end controller lifecycle locally: start, status, reload, stop, and automatic-mode restoration across handled shutdown paths
- [x] 4.3 Update repo documentation and architecture notes to describe the final boundary as CLI/GUI clients → controller service → root writer daemon
