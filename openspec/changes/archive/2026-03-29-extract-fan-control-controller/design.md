## Context

`src/FanControlCLI/AutomaticControlCommand.swift` currently does three jobs at once: it loads and validates config, launches the writer path, and hosts the long-running automatic-control loop in `runLoop(...)`. That was acceptable for the current CLI-only operator flow, but it creates the wrong ownership boundary for the next phase because the future GUI would either need to duplicate that orchestration or tunnel through the CLI process.

The repo’s current specs already point toward a shared-runtime-first architecture with thin clients and a privileged write boundary. This change sharpens that direction into an explicit three-layer shape:

- CLI/GUI = user-facing clients
- controller executable = non-privileged loop host and control-plane service
- root writer daemon = privileged low-level write service

This change is intentionally sequenced after the root writer daemon change. The controller proposal assumes the privileged write boundary has already been daemonized so the controller can depend on the intended low-level service contract instead of the current `HelperFanWriterClient.launch(... "writer-service")` subprocess model.

## Goals / Non-Goals

**Goals:**
- Move long-running automatic-control orchestration out of the CLI entrypoint into a dedicated controller executable/service
- Keep config loading/validation, telemetry sampling, demand planning, session lifecycle, and fail-safe restoration owned by the controller
- Make both CLI and GUI peer clients of the controller rather than letting either talk to the privileged writer directly
- Define a concrete client/controller contract for start, stop, reload, and status queries
- Preserve the existing dual-domain control behavior while relocating lifecycle ownership

**Non-Goals:**
- Redesigning the dual-domain fan-control algorithm itself
- Finalizing the full packaging/distribution/install UX for launch-at-login or helper blessing
- Using GUI → CLI subprocess execution as the long-term integration architecture
- Adding remote/network control; all controller IPC remains local-only
- Reworking unrelated telemetry-only menu bar behavior beyond what is needed to consume controller status

## Decisions

### Decision: Introduce a dedicated controller executable as the sole loop host
- **Chosen:** create a `fan-control-controller`-style executable/service that owns the automatic-control session and hosts the control loop outside CLI and GUI entrypoints.
- **Why:** `AutomaticControlCommand.runLoop(...)` currently mixes shell concerns with long-lived orchestration. Extracting the loop gives the project one authoritative automatic-control host that both client surfaces can target.
- **Alternative considered:** keep the loop in the CLI and let the GUI invoke the CLI when it wants automatic control.
- **Why not:** that would turn the CLI process into a hidden integration boundary, couple GUI behavior to terminal-oriented process semantics, and violate the intended client/service split.

### Decision: Keep orchestration logic in shared runtime, with a thin controller host above it
- **Chosen:** move loop-hosting mechanics into controller-focused runtime components (session state machine, sampling cycle, planning/apply cycle, status model, controller client protocol), while the controller executable remains a thin service shell.
- **Why:** this preserves the repo’s shared-runtime-first direction and keeps controller behavior testable without binding it to one executable main file.
- **Alternative considered:** place most orchestration directly inside the controller executable target.
- **Why not:** that would repeat the same architectural mistake currently present in the CLI, just in a new binary.

### Decision: Use a local controller IPC contract that is independent from CLI text output
- **Chosen:** define explicit controller commands and status payloads in shared runtime, with a local IPC transport suitable for CLI and GUI clients.
- **Why:** the important boundary is not the exact transport but the existence of a typed client/service contract that both clients can use without scraping terminal output or linking to privileged code.
- **Alternative considered:** treat CLI process invocation as the integration mechanism.
- **Why not:** CLI output is presentation, not a control contract. It is brittle for GUI integration and obscures lifecycle/state errors.

### Decision: Start with request/response control and snapshot status, not mandatory event streaming
- **Chosen:** require start/stop/reload/status operations and a structured status snapshot that reports lifecycle phase, config source, last sample timing, writer connectivity, per-fan state, and last error context.
- **Why:** snapshot-style status is enough to unblock both CLI inspection and GUI display while keeping IPC complexity contained. Event streaming can be added later if polling proves insufficient.
- **Alternative considered:** require push/event subscriptions in the first controller change.
- **Why not:** it adds concurrency and reconnection complexity before the basic service boundary is proven.

### Decision: Make config changes explicit controller restarts/reloads, not implicit hot file watching
- **Chosen:** the controller accepts an explicit start or reload request with a config path. It validates the candidate config before changing the active session. If a reload fails validation or the writer daemon is unavailable, the existing running session remains active and the failure is reported in status.
- **Why:** automatic file watching creates ambiguous ownership and failure semantics. An explicit reload boundary is easier to reason about and safer for fan-control lifecycle management.
- **Alternative considered:** watch the config file and live-apply edits automatically.
- **Why not:** partial writes, invalid intermediate states, and unclear rollback behavior make that unsafe for an early service boundary.

### Decision: Treat stop/restart as controlled session transitions with automatic-mode restoration
- **Chosen:** a stop or successful restart first ends the active control session, restores automatic mode for managed fans, clears per-session smoothing state, and only then enters idle or starts the replacement session.
- **Why:** this keeps lifecycle boundaries sharp and avoids leaking stale `FanControlState` or manual-mode ownership across sessions.
- **Alternative considered:** reuse existing state across restarts or attempt in-place mutation of a live loop.
- **Why not:** it makes status and safety guarantees harder to reason about, especially around config changes and writer reconnection.

### Decision: Only the controller talks to the root writer daemon
- **Chosen:** CLI and GUI clients communicate only with the controller; the controller is the sole non-privileged component allowed to issue low-level write requests to the root writer daemon.
- **Why:** this preserves a narrow privileged boundary and prevents GUI/client code from growing ad hoc writer integration paths.
- **Alternative considered:** allow GUI and CLI to call the writer daemon directly for some operations.
- **Why not:** that would create multiple privileged callers, duplicate failure handling, and weaken the architectural split the project is trying to establish.

## Risks / Trade-offs

- **IPC design churn between controller and clients** → keep command/status models transport-agnostic in shared runtime so transport details can evolve without redefining the product boundary
- **Status reporting becomes too thin for debugging or GUI state** → include explicit lifecycle phase, timestamps, last error, and per-fan control details in the initial snapshot model rather than only returning “running/not running”
- **Reload semantics can accidentally drop a healthy session** → validate replacement config before committing and preserve the current session on failed reload attempts
- **Controller/writer lifecycle coupling can produce hard-to-debug failures** → surface writer connectivity and last writer error in controller status, and always restore automatic mode on handled controller shutdown
- **Service extraction can leave the CLI as a half-client/half-host hybrid** → explicitly remove loop hosting from `AutomaticControlCommand` and keep CLI responsibilities to parsing, request dispatch, and human-readable output only
- **GUI pressure may reintroduce CLI subprocess shortcuts during implementation** → document that CLI invocation may be used only as a temporary spike, not as the accepted target architecture

## Migration Plan

1. Land the root writer daemon change first and stabilize its local request contract.
2. Extract controller-owned runtime components from the current CLI loop path (`AutomaticControlCommand`, bootstrap, sampling/apply lifecycle, status model).
3. Add the controller executable/service target and local IPC entrypoint.
4. Refactor CLI automatic-control commands into controller-client operations for start/stop/status/reload flows.
5. Update the menu bar/GUI path to consume controller status and control operations through the same client contract rather than direct writer access.
6. Verify controlled shutdown, stale-sensor failure, writer-daemon failure, and config-reload behavior against the new lifecycle boundary.

## Open Questions

- Which local transport best fits the controller packaging plan after the root writer daemon work settles: launchd/XPC, Unix domain socket, or another local-only mechanism?
- Should the near-term controller be user-started by CLI first and later moved behind automatic login startup, or should launch-at-login be part of the first controller implementation?
- Does the GUI need a lightweight status polling cadence only, or is there already enough UX pressure to justify streaming/subscription semantics in the first implementation?
