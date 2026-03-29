# Project context

- This repo is about building a macOS fan-control tool, informed by reverse-engineering notes from an existing reference implementation.
- Current direction: a **shared-runtime** architecture with multiple client surfaces, starting with a CLI and likely expanding to a menu bar / GUI app, plus a privileged helper boundary for low-level writes.
- Current control idea: aggregate thermal input from **CPU** and **GPU** domains, then use a conservative policy such as `max(cpu_demand, gpu_demand)`.

# Where to look

- `openspec/specs/`
  - repo-level capability map and long-lived behavior
  - check here first when you need overall project understanding
- `openspec/changes/<change>/`
  - local truth for one active change
- `openspec/changes/archive/YYYY-MM-DD-<change>/`
  - historical decisions; read only when the current task clearly depends on prior choices
- `reverse-engineering-notes.md`
  - current high-signal notes about the existing binary and likely target architecture
- `ida-headless` MCP
  - use this directly when binary-level verification is needed; do not rely only on notes if the task depends on exact behavior

# Working stance

- Do **not** read the full archive by default.
- Do **not** start every new conversation from blank-slate explore if repo-level specs already exist.
- Prefer this context-loading order:
  1. relevant `openspec/specs/`
  2. `reverse-engineering-notes.md` when architecture / reverse-engineering context matters
  3. active change artifacts
  4. archived changes only if needed
  5. `ida-headless` MCP when verification against the binary is needed

# OpenSpec complement

OpenSpec is strong at **change-level structure**. The missing piece is often **repo-level continuity**.

So in this repo:

- treat `openspec/specs/` as the closest thing to project-wide truth
- treat change artifacts as change-local truth
- treat archives as selective reference, not default context
- if repo-level specs are missing or thin, say so explicitly instead of pretending the project is well-specified

# Current project understanding

From the current notes and current exploration decisions:

- the reference implementation uses **main process reads + privileged helper writes**
- helper installation uses **Authorization + SMJobBless + launchd**
- aggregate / average sensors already exist in the original product
- the main limitation appears to be the control model being tied to **one sensor key per fan mode**
- the likely path here is a shared runtime used by multiple shells rather than treating one executable as the whole product

# Current project baseline

- Primary implementation language: **Swift**
- Product shape: **shared runtime + CLI + future GUI/app surfaces**, with a likely split between user-facing clients, possible user-session daemon behavior, and a minimal privileged helper
- Startup model for the near-term product: **start on user login**, not system boot
- Privilege model: keep sensor reading and control logic outside root when possible; isolate low-level fan write operations behind a **minimal privileged helper**
- Near-term priority: preserve the validated CLI path while extracting a reusable shared runtime for future product surfaces

## Current module layout

- `src/FanControlRuntime/`
  - reusable hardware, telemetry, config, and control-support logic
- `src/FanControlCLI/`
  - CLI parsing, terminal-facing command flow, and executable entrypoint
- `Package.swift`
  - package name: `MacsFanControl`
  - shared runtime target: `FanControlRuntime`
  - CLI executable target/product: `FanControlCLI` / `fan-control-cli`

## Current architecture direction

- Do **not** assume the current MVP executable layout is the intended end-state architecture.
- Prefer a boundary of: **shared runtime/core** → thin CLI shell → future GUI/menu bar shell.
- GUI clients should reuse shared Swift APIs directly; they should **not** shell out to the CLI and parse terminal output.
- CLI remains a first-class operator/debugging surface, not a disposable prototype.

# Current MVP validation scope

The first proof-of-viability should answer only the highest-risk hardware questions:

- can a Swift-based tool read the relevant temperature sensors on the target machine?
- can it read the current fan RPM values?
- can it successfully write fan RPM changes through the intended privilege path?

For this MVP, simple terminal output is sufficient:

- sensor reads can be compared against an external reference tool
- fan RPM reads/writes can be confirmed by observing visible RPM changes

## Local build / sudo caveat

- Avoid using `sudo swift build` or `sudo swift run` unless root is strictly required for the command being tested.
- If root-owned artifacts end up inside `.build/` after a sudo run, later non-sudo builds may fail with `Operation not permitted` when SwiftPM tries to overwrite them.
- In that case, prefer removing the specific root-owned build artifacts (or cleaning `.build/`) before rebuilding as the normal user.

## OpenSpec single-change shortcut

- For `opsx apply` and `opsx archive`: if exactly one active change exists, do not ask the user to choose; use that single active change directly.
