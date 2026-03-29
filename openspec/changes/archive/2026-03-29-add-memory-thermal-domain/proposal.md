## Why

当前自动控制只考虑 CPU 和 GPU 两个热域。Mac mini 的 SMC 已经暴露了 `Tm0p` / `Tm1p`（Memory 1 / Memory 2）温度传感器，但这些读数既没有被聚合成统一指标，也没有参与风扇控制决策或 menu bar 展示。在高内存负载场景下（大模型推理、大量编译），内存温度可能独立于 CPU/GPU 升高，当前架构对此完全无感知。

## What Changes

- 在 `AggregateRule` 中新增 `memoryAverage` 聚合规则，对所有 `type=memory` 的 SMC 读数取平均，生成 `memory_average` 虚拟传感器。
- 在 `AutomaticControlConfig` / `ResolvedAutomaticControlConfig` 中新增可选的 `memoryDomain`（`ThermalDomainConfig?`），使其参与 `max(cpu, gpu, memory?)` 风扇目标计算。`memoryDomain` 为 `nil` 时行为与现有双域完全一致，不破坏向后兼容。
- 在 `DomainSnapshot` 中新增 `memoryTemperatureCelsius`（可选），在 `FanDemandPlan` 中新增 `memoryDemandRPM`（可选）。
- 在 `TelemetrySnapshot` 中新增 `memoryAverageCelsius`，menu bar compact label 增加 `Mem` 列展示内存温度。
- 更新 `config.json` 和 `config.json.example`，加入 `memoryDomain` 配置段。

## Capabilities

### New Capabilities

（无新增独立能力）

### Modified Capabilities

- `dual-domain-fan-control`: 从双域扩展为三域（CPU / GPU / Memory），memory domain 为可选参与。
- `menu-bar-telemetry`: compact label 和 expanded panel 增加内存温度展示。

## Impact

- `src/FanControlRuntime/TemperatureProviders.swift` — `AggregateRule` 新增 case
- `src/FanControlRuntime/AutomaticControl.swift` — config 结构、snapshot、demand plan、validation
- `src/FanControlRuntime/TelemetrySnapshot.swift` — 新增 `memoryAverageCelsius` 字段
- `src/FanControlMenuBar/StatusItemLabelView.swift` — compact label 增加 Mem 列
- `src/FanControlCLI/AutomaticControlCommand.swift` — 打印 memoryDomain 配置
- `config.json` / `config.json.example` — 新增 `memoryDomain` 段
- 测试文件需要同步更新
