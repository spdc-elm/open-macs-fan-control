## 1. Aggregate Sensor

- [x] 1.1 Add `memoryAverage` case to `AggregateRule` in `TemperatureProviders.swift` — rawName `memory_average`, group `Memory`, type `memory`, filter `type == "memory"`, compute arithmetic mean

## 2. Config & Control Logic

- [x] 2.1 Add optional `memoryDomain: ThermalDomainConfig?` to `AutomaticControlConfig` and `ResolvedAutomaticControlConfig`
- [x] 2.2 Update `AutomaticControlBootstrap.resolve()` — validate `memoryDomain` if present, check sensor exists in inventory
- [x] 2.3 Update `DomainSnapshot` with optional `memoryTemperatureCelsius: Double?`
- [x] 2.4 Update `AutomaticControlResolver.resolveSnapshot()` — resolve memory reading when `memoryDomain` is configured
- [x] 2.5 Update `FanDemandPlan` with optional `memoryDemandRPM: Int?`; update `demandPlan()` to compute `max(cpu, gpu, memory?)` for `requestedTargetRPM`

## 3. Telemetry & Display

- [x] 3.1 Add `memoryAverageCelsius: TelemetryValue<Double>` to `TelemetrySnapshot`; update `TelemetrySnapshotBuilder.build()` to resolve `memory_average`
- [x] 3.2 Add `Mem` column to `StatusItemLabelContent` in `StatusItemLabelView.swift`
- [x] 3.3 Update expanded menu bar panel to show memory average temperature
- [x] 3.4 Update `AutomaticControlCommand` CLI print to show `memoryDomain` when present

## 4. Config Files

- [x] 4.1 Add `memoryDomain` to `config.json` and `config.json.example` with `sensor: "memory_average"` and reasonable thresholds

## 5. Tests

- [x] 5.1 Update `TelemetrySnapshotTests` — add memory reading to test data, assert `memoryAverageCelsius` is resolved
- [x] 5.2 Update `AutomaticControlTests` — test with and without `memoryDomain`, verify `max()` includes memory when present
- [x] 5.3 Update `AutomaticControlControllerTests` — include `memoryDomain` in config harness
