## 1. Privileged daemon boundary

- [x] 1.1 Add a dedicated root writer daemon target and move the privileged write entrypoint out of the CLI subprocess-only `writer-service` path
- [x] 1.2 Refactor `FanWriter.swift` request/response handling into a shared daemon protocol plus an unprivileged client that connects over local IPC
- [x] 1.3 Implement daemon-side session tracking for inspected/managed fans, manual-mode acquisition, target RPM writes, restore requests, and shutdown cleanup
- [x] 1.4 Implement conflict and unavailable-daemon errors so clients fail clearly instead of silently falling back to direct/root writes

## 2. Local install/startup workflow

- [x] 2.1 Add a local-first install/update/remove workflow for the root daemon using a stable root-owned path and launchd-managed startup
- [x] 2.2 Add operator-visible status/debug output for daemon availability, socket path/connection failures, and migration away from `sudo -n <cli> writer-service`

## 3. Client migration

- [x] 3.1 Update CLI automatic control to connect through the daemon client and preserve safe restore behavior on handled exit and error paths
- [x] 3.2 Update the CLI manual fan write flow to use the daemon instead of direct privileged `SMCConnection` access
- [x] 3.3 Ensure future client surfaces can reuse the same runtime client boundary without pulling config, policy, or UI logic into the daemon

## 4. Verification and repo truth

- [x] 4.1 Add or update tests for daemon protocol handling, session cleanup, conflict behavior, and automatic-control failure semantics
- [x] 4.2 Run the relevant build/tests plus local validation of install/start/connect/write/restore flows
- [x] 4.3 Update help text, docs, and spec references that still describe the sudo-launched helper MVP path
