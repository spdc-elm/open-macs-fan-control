## 1. Swift validation scaffold

- [x] 1.1 Create the minimal Swift project structure for the MVP validation tool
- [x] 1.2 Add a terminal-facing entry path for running hardware validation commands

## 2. Read-path validation

- [x] 2.1 Implement temperature sensor probing that prints readable terminal output
- [x] 2.2 Implement fan RPM readback that prints current fan speeds
- [x] 2.3 Compare reported temperatures and RPM values against an external reference on the target machine

## 3. Write-path validation and safety

- [x] 3.1 Define the MVP privileged write validation path as a sudo-driven, helper-like precursor to the future dedicated helper
- [x] 3.2 Implement a manual fan speed write path for operator-driven testing
- [x] 3.3 Implement recovery behavior that attempts to restore automatic fan control on handled exit and handled error paths
- [x] 3.4 Verify that the requested write produces an observable RPM change on the target machine
- [x] 3.5 Verify that handled shutdown and handled error paths return fan control to the default automatic mode
- [x] 3.6 Document the validation results and any blockers discovered in the hardware access path
