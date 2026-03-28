## Context

The project has already converged on a Swift-first macOS direction because the long-term product likely needs native access to IOKit, ServiceManagement, Authorization Services, and launchd-oriented integration. The remaining uncertainty is not the high-level architecture but the hardware access path: whether a small Swift-based tool can, on the target machine, read temperatures, read current fan RPM values, and produce a visible fan RPM change through the low-level write path.

This change is intentionally a bring-up spike. It is meant to reduce technical uncertainty before building the fuller CLI / user-session daemon / privileged helper shape. For the write path, the MVP should behave like a minimal precursor to the future helper: a narrowly scoped privileged component or mode that can initially be driven with `sudo` during development rather than requiring final SMJobBless packaging up front.

## Goals / Non-Goals

**Goals:**
- Prove that Swift can be used as the implementation language for the target hardware interaction paths
- Provide terminal-visible output for temperature sensor values and current fan RPM values
- Provide a manual write validation path that can be verified against observed fan RPM changes
- Keep the validation loop simple enough to compare readings against an external reference during development

**Non-Goals:**
- Full automatic fan control logic
- Login-item packaging or launchd installation flow
- Final helper installation using SMJobBless
- Model-specific defaults, profiles, or configuration UX

## Decisions

### Decision: Build a narrow validation tool before the full service stack
- **Chosen:** use an MVP validation path that exercises the hardware interfaces directly
- **Why:** the highest-risk unknowns are hardware access and privilege boundaries, not policy logic
- **Alternative considered:** start directly with the full daemon/helper product shape
- **Why not:** that would mix architectural work with hardware bring-up and make failures harder to localize

### Decision: Use terminal output as the validation surface
- **Chosen:** print values and rely on external comparison against a trusted reference tool
- **Why:** it is the fastest path to visible verification and avoids premature UX work
- **Alternative considered:** add custom UI or structured monitoring first
- **Why not:** unnecessary for the current feasibility question

### Decision: Include fan RPM readback alongside temperature reads
- **Chosen:** validate both temperature reads and current fan RPM reads before write-path confidence is claimed
- **Why:** write verification is stronger when the tool can also observe the before/after RPM state itself
- **Alternative considered:** only validate temperature reads plus manual fan write attempts
- **Why not:** that leaves a gap in the read side of the fan control loop

### Decision: Treat the write path as a controlled manual verification step
- **Chosen:** expose a manual fan speed change operation for explicit operator-driven testing
- **Why:** this is enough to validate low-level control without committing to the final automatic policy architecture
- **Alternative considered:** jump straight to closed-loop automatic control
- **Why not:** too much surface area for the first hardware proof

### Decision: Use a sudo-driven helper-like write path for MVP bring-up
- **Chosen:** validate writes through a minimal privileged path that can be run directly with `sudo` during development while staying conceptually aligned with a future dedicated helper
- **Why:** this keeps the MVP focused on low-level feasibility without prematurely committing to final packaging and installation mechanics
- **Alternative considered:** build the full helper installation and invocation model first
- **Why not:** that adds substantial macOS integration complexity before hardware viability is proven

### Decision: Fail safe by restoring automatic fan control on handled exits
- **Chosen:** the MVP write path will attempt to return fan control to the default automatic mode on normal shutdown and on handled error paths
- **Why:** manual fan writes are inherently risky, and the MVP must minimize the chance of leaving the machine in an overridden state after operator testing
- **Alternative considered:** leave restoration as a later hardening task
- **Why not:** this safety behavior is fundamental to safe bring-up, not optional polish

### Decision: Use IOHID as the next validation path for Apple Silicon temperature reads
- **Chosen:** treat IOHID temperature probing as the next implementation target when SMC candidate-key temperature output is unstable or implausible on Apple Silicon
- **Why:** both repository notes and external reference implementations indicate that Apple Silicon temperature visibility is not reliably captured by a small guessed SMC key list alone
- **Alternative considered:** continue expanding the SMC-only candidate list first
- **Why not:** that risks spending time on brittle key guessing while the more platform-appropriate sensor path is already indicated by evidence

## Risks / Trade-offs

- **Swift can call the framework APIs but the specific low-level SMC path may still be awkward** → isolate the MVP around direct feasibility and avoid overcommitting to final packaging in this change
- **Sensor values may not line up one-to-one with the reference tool labels** → accept manual comparison by value and stability rather than exact naming parity at first
- **Manual write tests can affect machine thermals if used carelessly** → keep this change explicitly operator-driven and always attempt to restore automatic fan control on handled exit and error paths
- **Reading may succeed while writing still requires a different privilege shape than expected** → treat read success and write success as separate validation outcomes
- **Some termination modes are not interceptable, so restoration cannot be absolutely guaranteed** → specify fail-safe restoration for handled exit/error paths and document the remaining boundary explicitly
- **Apple Silicon temperature keys may appear readable while still being semantically wrong or unstable** → prefer IOHID-backed validation before claiming temperature-read success on Apple Silicon
