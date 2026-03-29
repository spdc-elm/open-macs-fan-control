## 1. Module boundary extraction

- [x] 1.1 Define the new shared runtime target/module in `Package.swift`
- [x] 1.2 Move reusable hardware, telemetry, configuration, and control-support code out of the current CLI executable target into the shared runtime module
- [x] 1.3 Ensure the shared runtime API boundary does not depend on CLI argument parsing or terminal formatting

## 2. CLI shell migration

- [x] 2.1 Rename MVP-centric package/target/source naming to stable CLI naming
- [x] 2.2 Update the CLI executable to depend on the shared runtime module for temperature, fan, and automatic-control behaviors
- [x] 2.3 Preserve current CLI-facing workflows while adjusting imports, entrypoints, and tests to the new structure

## 3. Repo truth and verification

- [x] 3.1 Update `AGENT.md` and any other repo-level architecture notes to describe the shared-runtime + CLI + future GUI design
- [x] 3.2 Update any affected documentation that still describes the executable as the whole product architecture
- [x] 3.3 Run the relevant build/tests to verify the refactor still works after target moves and renames
- [x] 3.4 Note any migration details needed by the active menu bar change so future implementation work targets the new shared runtime boundary
