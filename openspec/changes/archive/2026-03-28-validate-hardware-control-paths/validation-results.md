# MVP validation results

## What was implemented

- Added a minimal Swift Package Manager executable scaffold in `Package.swift`
- Added `src/FanControlMVP/` with a terminal-first CLI:
  - `fancontrol-mvp temps`
  - `fancontrol-mvp fans`
  - `sudo fancontrol-mvp write --fan <index> --rpm <target>`
- Added direct AppleSMC read/write plumbing for fan RPM readback, manual fan override, and handled auto-restore attempts
- Added an IOHID-backed Apple Silicon temperature probing path, with provisional SMC fallback kept only as bring-up backup
- Added a `temps --friendly` CLI mode that applies the extracted IOKit XML aliases where available so raw IOHID names can be compared more directly against reference tools
- Scoped the write path as a sudo-driven MVP precursor to a future dedicated helper boundary

## Current observed status

- `swift build` succeeds.
- `swift run fancontrol-mvp fans` now returns plausible fan values on the current machine (for example, `current=1000rpm min=1000rpm max=4900rpm`).
- `swift run fancontrol-mvp temps` now uses the IOHID path as the primary Apple Silicon temperature source and prints plausible raw readings such as `PMU tdie*`, `PMU tdev*`, and `NAND CH0 temp`.
- `swift run fancontrol-mvp temps --friendly` now overlays extracted XML-friendly aliases such as `Power Manager Die 6` and `SSD`, while still showing raw keys and available group/type metadata for comparison.
- The current temperature output should be treated as raw sensor-key validation rather than final MFC-style naming, because the friendlier labels and aggregate sensors come from a separate metadata / grouping layer that is not implemented in this MVP.
- The fan write path and handled restore path exist in code but still require target-machine operator validation before they can be treated as complete.

## Current blockers / limits

- The repo environment can compile the MVP, but it cannot complete target-machine validation against an external reference by itself.
- Temperature probing on Apple Silicon is now evidence-backed by IOHID raw sensor reads, but external comparison is still required before task 2.3 can be closed.
- The current CLI can now surface XML-backed friendly aliases, but it still does not replicate Macs Fan Control's hide/exclude rules or provider-layer average/group sensor synthesis.
- Fan write verification and automatic-mode restoration still require operator execution on the intended machine, because they depend on sudo access and observable hardware behavior.
- More blind expansion of guessed SMC temperature keys is no longer the recommended next step for Apple Silicon.

## Manual validation checklist

1. Build with `swift build`.
2. Treat `swift run fancontrol-mvp fans` as the current read-path baseline and compare the reported RPM values with an external reference.
3. Run `swift run fancontrol-mvp temps --friendly` and compare the XML-backed friendly output against an external reference on the same machine; if needed, fall back to raw output with `swift run fancontrol-mvp temps --raw`.
4. Run `sudo swift run fancontrol-mvp write --fan 0 --rpm <target>` and confirm:
    - the requested RPM produces an observable change,
    - the command prints readback during the hold window,
    - handled exit or Ctrl-C returns the fan to automatic mode.

## Next phase goal

- Use the current IOHID-backed temperature probe as the primary path for task 2.3 external comparison, then decide whether a later change should add friendly naming and aggregation.

## Status

- Scaffold and core AppleSMC fan read/write implementation tasks are in place.
- Temperature-read feasibility is materially de-risked at the raw IOHID path level, but external comparison and naming-layer work remain separate follow-up concerns.
- Empirical hardware verification tasks remain pending until they are run on the target machine.
