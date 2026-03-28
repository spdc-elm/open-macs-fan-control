# macs-fan-control

Terminal-first Swift prototype for exploring fan control and thermal sensor behavior on macOS, with a current focus on Apple Silicon temperature sources and multi-provider modeling.

## Current temperature model

- IOHID temperature services are read as one provider.
- SMC temperature keys are read as another provider.
- Aggregate sensors such as CPU/GPU averages are computed on top of the unified readings.
- Disk remains a reserved provider slot for later SMART/NVMe work.

## Reference work

This project's Apple Silicon SMC temperature-key family tables were adapted with reference to:

- [dkorunic/iSMC](https://github.com/dkorunic/iSMC)

In particular, the current Swift implementation borrows from iSMC's documented `src/temp.txt` Apple Silicon key mapping approach and its model-family grouping strategy.
