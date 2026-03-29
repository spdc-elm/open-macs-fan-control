## Context

The repo currently treats one SwiftPM executable target as both product shell and implementation home. Hardware reads, telemetry aggregation, validation commands, automatic-control code, and future-facing runtime concerns all live under the current MVP/CLI package surface. That structure was acceptable while the project was proving hardware viability, but it becomes a liability now that the repo intends to support more than one operator surface.

The menu bar direction makes this architectural gap concrete. A GUI shell should not invoke the CLI and scrape text output, and the CLI itself should not remain the de facto module boundary forever. The project needs a reusable runtime/core layer that owns hardware- and control-facing APIs, with thin clients above it: a CLI today and a GUI/menu bar app later.

## Goals / Non-Goals

**Goals:**
- Separate reusable runtime logic from CLI-specific argument parsing and terminal formatting
- Rename the existing MVP-facing executable into a stable CLI identity
- Establish a package structure that can support both CLI and GUI clients over the same Swift APIs
- Update repo-level truth so future work stops assuming the current terminal-only MVP layout is intentional end state

**Non-Goals:**
- Implementing the GUI/menu bar app itself in this change
- Redesigning fan-control algorithms or sensor models beyond what is necessary to extract shared APIs
- Finalizing helper installation/signing/distribution workflows
- Guaranteeing zero file moves or public-symbol churn; some structural breakage is intentional here

## Decisions

### Decision: Introduce a dedicated shared runtime module
- **Chosen:** move reusable sensor, telemetry, configuration, and control-support code into a dedicated Swift module that is not itself an executable entrypoint.
- **Why:** this creates an actual dependency boundary that both CLI and future GUI targets can consume directly.
- **Alternative considered:** leave code where it is and have future clients call the CLI as a subprocess.
- **Why not:** that would turn presentation text into an integration contract, which is brittle and wrong for a long-lived product.

### Decision: Keep CLI and future GUI as thin shells over the runtime
- **Chosen:** the CLI should own command parsing and terminal output only, while the future GUI should own app lifecycle and view concerns only.
- **Why:** thin shells reduce duplication and keep business logic testable without binding it to one UX surface.
- **Alternative considered:** let each client keep its own copy of hardware-access and telemetry-assembly logic.
- **Why not:** duplicated hardware logic would drift quickly and make debugging much harder.

### Decision: Rename the current MVP naming to stable CLI naming during extraction
- **Chosen:** replace MVP-centric names with CLI-centric names as part of the split rather than preserving the old naming and deferring cleanup.
- **Why:** once a shared runtime exists, the old `MVP` naming becomes actively misleading because the executable is no longer the whole product nor just a temporary prototype.
- **Alternative considered:** first extract the module boundary, then rename CLI targets later.
- **Why not:** that would drag misleading terminology into the new structure and create two migration waves instead of one.

### Decision: Treat repo-level docs/specs as part of the migration, not follow-up polish
- **Chosen:** update AGENT/context wording and the service-shape spec in the same change.
- **Why:** the old “terminal-first only” framing will otherwise keep steering future decisions in the wrong direction even if the code structure changes.
- **Alternative considered:** only change code now and leave docs/spec cleanup for later.
- **Why not:** stale architecture docs would create immediate confusion, especially with multiple active changes.

## Risks / Trade-offs

- **Renaming and moving targets may break local scripts or muscle memory** → document the new CLI naming and keep behavior-compatible commands where practical
- **A rushed extraction can produce a fake shared module that still leaks CLI assumptions** → explicitly move argument parsing and terminal formatting out of the runtime boundary
- **Active changes like menu bar work depend on the new structure settling first** → treat this refactor as an architectural prerequisite and sequence future implementation accordingly
- **Large file moves can make history and review noisier** → prefer small, boundary-driven steps and keep behavior changes separate from pure relocation when possible
- **Specs may lag behind if only code changes are made** → update the relevant repo-level spec and AGENT context in this same change

## Migration Plan

1. Define the target/module split: shared runtime module plus renamed CLI executable.
2. Move reusable hardware and telemetry APIs behind the shared runtime boundary.
3. Update the CLI to depend on the shared runtime rather than owning that logic directly.
4. Rename package/target/source paths from MVP-centric naming to CLI-centric naming.
5. Update AGENT/spec wording and verify the repo still builds/tests under the new structure.

## Open Questions

- Should the future GUI live in the same SwiftPM workspace, a sibling Xcode project, or both with shared package dependencies?
- How much of automatic-control orchestration belongs in the shared runtime versus a future daemon/client shell?
- Is it worth preserving a compatibility alias for the old executable name during the transition, or is a clean break preferable now?
