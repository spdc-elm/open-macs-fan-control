## Context

The repo already has the essential MVP hardware pieces in place: a terminal-first Swift entrypoint, unified temperature inventory loading across multiple providers, aggregate CPU/GPU readings, fan RPM readback, and a sudo-driven manual write path that restores automatic mode on handled exit. What is still missing is the first real closed-loop product slice: a long-running controller that reads thermal state, converts it into fan demand, and pushes writes through a narrow privileged boundary instead of keeping the whole control process elevated.

The current code also gives us a useful implementation constraint. `TemperatureInventory.refreshAll()` already produces aggregate readings, while `FanWriteCommand` shows the write primitives and safe restore behavior. That means this change does not need to rediscover hardware access; it needs to assemble those pieces into a control architecture that is config-driven, conservative, and shaped like the future CLI/controller/helper split.

## Goals / Non-Goals

**Goals:**
- Define the first automatic-control architecture for the project's MVP
- Support dual-domain control using CPU and GPU thermal demand together
- Drive thresholds and fan policy from a configuration file instead of hard-coded values
- Keep sensor reading and policy logic outside root while isolating low-level writes behind a minimal privileged writer boundary
- Preserve safe behavior when sensors are stale, config is invalid, helper communication fails, or the controller shuts down

**Non-Goals:**
- Full GUI product shape or profile editor
- Model-specific default tuning for every Mac variant
- Reproducing the reverse-engineered reference algorithm 1:1, including every tendency-state nuance
- Final SMJobBless installation and packaging UX; this change only needs an architecture and MVP-compatible runtime boundary
- Expanding disk-temperature support or other non-CPU/GPU policy inputs in this phase

## Decisions

### Decision: Use a three-part runtime shape (CLI + controller + privileged writer)
- **Chosen:** structure the first automatic version around a user-facing CLI, an unprivileged controller process, and a narrow privileged writer component.
- **Why:** this matches the repo's existing long-term direction and keeps the high-risk root boundary as small as possible.
- **Alternative considered:** run the full controller as root.
- **Why not:** it would be faster short-term but it would collapse the privilege boundary and make later hardening harder, not easier.

### Decision: Make the control loop config-driven and domain-oriented
- **Chosen:** load one config file that defines polling interval, per-domain sensor selection, per-domain start/max thresholds, and per-fan policy.
- **Why:** thresholds are the user-controlled part of the MVP, and a file-backed model makes the first version reproducible and easy to iterate without recompiling.
- **Alternative considered:** hard-code CPU/GPU thresholds in Swift for the first automatic version.
- **Why not:** that would speed up the first demo but would immediately block real tuning and make the MVP less useful than the current manual validation path.

### Decision: Compute one demand per domain, then take the conservative max
- **Chosen:** evaluate CPU demand and GPU demand independently, map each domain temperature into a target RPM range using start/max thresholds, then use `max(cpuDemand, gpuDemand)` as the fan target before smoothing.
- **Why:** this matches the existing project intent and is the safest first policy because either hot domain can pull the fan upward.
- **Alternative considered:** weighted blending or independent per-fan domain mixes.
- **Why not:** those are valuable later, but they add tuning complexity before the simpler conservative policy is proven.

### Decision: Reuse the reference algorithm's shape, not its exact internals
- **Chosen:** keep the same broad behavior as the reverse-engineered reference: linear threshold mapping, gradual movement toward the target, hysteresis against tiny oscillations, and throttled writes.
- **Why:** the reference notes strongly suggest that good control behavior depends on smoothing and anti-chatter, but this repo does not need a byte-for-byte clone to reach a strong first version.
- **Alternative considered:** write the exact target RPM on every poll.
- **Why not:** that would be simpler but would create unnecessary fan hunting and excessive low-level writes.

### Decision: Treat the privileged writer as a narrow command surface
- **Chosen:** the privileged component only needs to support: inspect current fan limits/state, set manual mode, set target RPM, and restore automatic mode.
- **Why:** this keeps the trust boundary small and maps directly onto the already validated hardware operations.
- **Alternative considered:** let the helper own sensor reads, policy logic, and config parsing too.
- **Why not:** that would move too much complexity into the privileged side and undermine the isolation goal.

### Decision: Fail safe toward automatic control
- **Chosen:** if the controller loses required sensor input, cannot validate config, cannot reach the writer, or receives a handled shutdown, it should stop issuing manual targets and request restore-to-auto for managed fans.
- **Why:** the system must prefer relinquishing control over holding a stale manual override.
- **Alternative considered:** keep the last successful manual target until an operator intervenes.
- **Why not:** that is riskier for thermals and makes failure modes much harder to reason about.

## Risks / Trade-offs

- **GPU temperature visibility may still be inconsistent on some Apple Silicon machines** → allow explicit domain sensor selection and fail closed to auto if the configured GPU domain cannot be refreshed reliably
- **The MVP helper boundary may start with a simpler runtime model than the final blessed helper** → keep the command surface stable so packaging can evolve later without changing controller semantics
- **A simplified smoothing algorithm may not feel as polished as the reference app at first** → encode thresholds, hysteresis, and write throttling explicitly so tuning can improve without reworking the full architecture
- **Config flexibility can become a footgun if invalid sensor names or unsafe thresholds are accepted** → validate config on load and refuse to start automatic control when required values are missing or nonsensical
- **Restore-to-auto is not absolutely guaranteed on unhandled termination or system crash** → guarantee restore attempts on handled exits and helper/controller error paths, and document the remaining boundary honestly

## Migration Plan

1. Keep the existing validation commands (`temps`, `fans`, `write`) intact as bring-up and fallback tools.
2. Add config parsing and a dry initialization path that validates domain selection and fan capabilities before any automatic writes occur.
3. Introduce the controller loop behind a new automatic-control command or service mode while preserving the manual write path for debugging.
4. Swap direct root-only write calls in the automatic path to the privileged writer boundary.
5. Validate startup, steady-state control, helper failure, and handled shutdown restore behavior on target hardware before treating the MVP as the default workflow.

## Open Questions

- Should the first config version let domains reference arbitrary sensor lists, or only named aggregate readings already emitted by the inventory layer?
- Does the first privileged writer ship as a separately invoked helper executable, or as a launchd-managed service with a thin local client?
- Do we want one shared policy for all fans in v1, or per-fan policy blocks from the start even if most machines will use identical settings?
