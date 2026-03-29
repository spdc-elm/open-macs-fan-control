## Context

The current privileged write path lives in `src/FanControlRuntime/FanWriter.swift`. `HelperFanWriterClient.launch(executablePath:)` either runs the current executable as `writer-service` when already root or shells out to `/usr/bin/sudo -n <executable> writer-service` when unprivileged. `AutomaticControlCommand` creates that helper-backed writer for each automatic-control run, while the CLI manual write validation path still talks to `SMCConnection` directly under `sudo`.

That arrangement was acceptable for MVP validation, but it is the wrong long-lived boundary for the current repo shape. The project now has `FanControlRuntime`, `FanControlCLI`, and `FanControlMenuBar`, and future GUI/controller surfaces need the same low-level write capability without scraping CLI output or inventing their own privilege story. At the same time, this project is still local-first and personal-use-first, so the design should solve the real operational problem now without prematurely committing to Apple’s fully productized helper workflows.

The current request/response shape is already close to what we need: inspect fans, set manual mode when first writing, apply a target RPM, restore automatic mode, and clean up on shutdown. The change is mostly about turning that MVP subprocess helper into a real long-lived root daemon with a stable install/startup path and clearer ownership semantics.

## Goals / Non-Goals

**Goals:**
- Make one minimal root daemon the only privileged component for fan writes
- Let CLI write flows, CLI automatic control, and future GUI/controller clients reuse the same daemon client boundary
- Replace per-run `sudo -n` helper launch with a local daemon install/startup mechanism that works without interactive elevation at control time
- Preserve a narrow privileged API: inspect fans, acquire manual control as needed, apply target RPM, restore automatic mode, and shut down / clean up safely
- Fail safe by restoring automatic mode when a client session ends or the daemon shuts down

**Non-Goals:**
- Shipping a notarized/productized macOS helper installation flow such as SMJobBless in this change
- Moving config loading, control-loop orchestration, or fan policy decisions into the daemon
- Designing a general remote-control service, network API, or multi-machine management plane
- Solving every possible multi-user authorization problem beyond a realistic local-admin-first posture

## Decisions

### Decision: Introduce a dedicated root daemon executable plus shared unprivileged client
- **Chosen:** add a dedicated root daemon executable target and a shared runtime client that connects to it.
- **Why:** this makes the privileged component explicit and small, and it avoids treating the CLI executable itself as the helper boundary.
- **Alternative considered:** keep the `writer-service` subcommand inside `fan-control-cli` and just change how it is launched.
- **Why not:** that would preserve the current coupling between the CLI binary and the privileged path, keep install/start semantics awkward, and make future GUI reuse less clean.

### Decision: Use an explicit local `launchd` install/startup workflow
- **Chosen:** manage the daemon as a locally installed `LaunchDaemon` with an explicit install/update/remove workflow, using a stable root-owned binary path and launchd-managed startup.
- **Why:** for a local macOS tool, `launchd` is the simplest realistic way to keep a root service available without shelling out to `sudo -n` every time a client wants to write fans.
- **Alternative considered:** keep spawning a helper subprocess via `sudo -n`, or jump directly to Apple’s productized helper/XPC workflows.
- **Why not:** `sudo -n` is exactly the fragile path we are replacing, while productized helper workflows add signing/distribution complexity that the repo explicitly does not want to take on yet.

### Decision: Use local IPC that stays close to the current JSON-line protocol
- **Chosen:** keep the daemon boundary as a local IPC connection with newline-delimited request/response messages modeled on the existing `WriterRequest` / `WriterResponse` types, carried over a daemon socket rather than a parent-child stdio pipe.
- **Why:** this keeps the protocol grounded in code that already exists while removing the requirement that the privileged process be a subprocess of the controller.
- **Alternative considered:** parent-child stdio only, or a full NSXPC service.
- **Why not:** stdio does not work once the helper becomes a shared long-lived daemon, while NSXPC would pull the project toward a more Apple-productized service model than is justified right now.

### Decision: Track manual fan ownership per client session and reject conflicts
- **Chosen:** the daemon should treat each client connection as a session, remember which fans that session has moved into manual control, and restore those fans when the session ends. If another client tries to take over a fan already owned by a live session, the daemon returns a busy/conflict error instead of silently stealing ownership.
- **Why:** this is the smallest design that still gives safe cleanup and predictable behavior once more than one client surface exists.
- **Alternative considered:** global singleton control for the whole daemon, or last-write-wins across clients.
- **Why not:** a global singleton is unnecessarily restrictive for read-only inspection, while last-write-wins creates controller fights and makes cleanup ambiguous.

### Decision: Keep the daemon boundary intentionally narrow
- **Chosen:** the daemon only exposes fan inspection, write-focused session operations, restoration, and shutdown/cleanup; configuration loading, telemetry polling, automatic-control cadence, smoothing, hysteresis, and UI/application lifecycle remain in unprivileged clients and shared runtime code.
- **Why:** this preserves the current architecture direction in `shared-runtime-architecture` and `fan-control-service`, and it keeps the privileged component auditable.
- **Alternative considered:** move automatic-control orchestration or config handling into the daemon so clients become thinner.
- **Why not:** that would enlarge the privileged boundary without solving the current problem, and it would entangle policy logic with root-only code.

### Decision: Safety comes from both explicit restore calls and daemon-side cleanup
- **Chosen:** orderly clients still call restore/shutdown explicitly, but the daemon also restores any session-owned fans when a client disconnects unexpectedly, the daemon handles termination, or daemon shutdown is requested.
- **Why:** the current helper already relies on deferred cleanup inside the privileged process; keeping that property is important because client crashes are exactly when cleanup matters most.
- **Alternative considered:** rely only on well-behaved clients to restore fans before exit.
- **Why not:** that would regress the fail-safe posture and turn unexpected client exits into orphaned manual fan state.

## Risks / Trade-offs

- **Local socket access is not a complete authorization model** → limit the daemon to local IPC, install it as a root-owned launchd service, use restrictive socket permissions suitable for local-admin use, and document that this design is intentionally local-first rather than distribution-grade.
- **A launchd-installed daemon adds operational state outside the repo checkout** → provide explicit install/status/remove commands or scripts, and keep the daemon binary path stable so upgrades are deliberate rather than implicit.
- **Concurrent clients can now conflict over fan ownership** → make conflict handling explicit and fail closed with a clear error instead of allowing silent takeover.
- **A daemon crash can still leave the machine in a bad state if cleanup cannot complete** → restore on handled termination paths, keep the command surface tiny, and treat crash recovery / daemon status visibility as part of the operator workflow.
- **Replacing the MVP path may temporarily disrupt existing local scripts** → mark the `writer-service` subprocess flow as breaking, keep migration steps simple, and update CLI/help text alongside implementation.

## Migration Plan

1. Add the dedicated root daemon target, shared IPC request/response model, and unprivileged daemon client in `FanControlRuntime`.
2. Add local daemon install/manage support for a root-owned launchd service and stable socket/binary locations.
3. Update CLI automatic control and CLI manual write flows to connect through the daemon client instead of `sudo -n` subprocess launch or direct root SMC writes.
4. Remove the temporary `writer-service` launch path and any help text that still describes the old helper-backed workflow.
5. Verify handled shutdown, disconnect cleanup, conflict behavior, and daemon-unavailable failure paths with focused tests/manual validation.

## Open Questions

- Should the install/manage UX live as new CLI subcommands, a repo script, or both?
- Do we want daemon startup to be always-on after install, on-demand via launchd socket activation, or simply launch-at-boot/login for the first version?
- How much client identity/ownership detail should appear in daemon error messages and status output for debugging session conflicts?
