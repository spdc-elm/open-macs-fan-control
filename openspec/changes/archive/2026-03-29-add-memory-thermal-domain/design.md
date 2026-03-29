## Context

当前自动控制架构是双域模型：CPU domain + GPU domain → `max(cpu_demand, gpu_demand)` → fan target。所有结构体（`AutomaticControlConfig`、`DomainSnapshot`、`FanDemandPlan`）都硬编码了两个域。

SMC 已经暴露了 `Tm0p` / `Tm1p`（Memory 1 / Memory 2, `type=memory`, `group=Memory`），但没有对应的聚合指标，也没有参与控制或展示。

## Goals / Non-Goals

**Goals:**
- 新增 `memory_average` 聚合传感器
- 在自动控制中引入可选的 memory domain，参与 `max()` 决策
- 在 menu bar 和 telemetry snapshot 中展示内存温度
- 保持向后兼容：`memoryDomain` 缺失时行为不变

**Non-Goals:**
- 不重构为通用 N-domain 架构（当前三域足够，过度抽象无收益）
- 不引入 per-domain 权重或优先级机制
- 不修改 SMC sensor discovery 逻辑（已有的 `Tm0p`/`Tm1p` 候选项已经在 `SMCTemperatureProvider` 中）

## Decisions

### 1. `memoryDomain` 为 optional（`ThermalDomainConfig?`）

**选择**: config 中 `memoryDomain` 字段可选，缺失时不参与控制。

**理由**: 不是所有 Mac 都暴露内存温度传感器。强制要求会导致无内存传感器的机器无法启动自动控制。同时保持现有 config 文件无需修改即可继续工作。

**替代方案**: 设为必填但提供 "disabled" sentinel → 增加配置复杂度，无实际收益。

### 2. 聚合规则使用 `type=memory` 过滤

**选择**: `AggregateRule.memoryAverage` 对所有 `type == "memory"` 的读数取平均。

**理由**: 与 `cpuCoreAverage`（过滤 `type.hasPrefix("cpu")`）和 `gpuClusterAverage`（过滤 `type == "gpu"`）保持一致的模式。当前机器上 `type=memory` 的传感器恰好是 `Tm0p` 和 `Tm1p`。

### 3. demand 计算：`max(cpu, gpu, memory?)`

**选择**: memory domain 存在时，fan target = `max(cpuDemand, gpuDemand, memoryDemand)`。

**理由**: 与现有 conservative policy 一致——取最激进的域。内存过热同样需要风扇响应。

### 4. Menu bar label 增加 Mem 列

**选择**: 在 CPU / GPU / Fan 之间插入 Mem 列，四列布局。

**理由**: 内存温度是用户关心的信号，且 menu bar 空间足够容纳一个额外的窄列。当 `memoryAverageCelsius` 不可用时显示 `--`，与现有 unavailable 处理一致。

## Risks / Trade-offs

- **Menu bar 宽度增加** → 多一列约 30pt，在大多数屏幕上可接受。如果用户觉得太宽，后续可做成可配置显示列。
- **无内存传感器的机器** → `memory_average` 聚合不会产出（`computeValue` 返回 nil），`memoryDomain` 为 nil，menu bar 显示 `--`。不会报错。
- **`DomainSnapshot` / `FanDemandPlan` 增加 optional 字段** → 所有消费方需要处理 nil，但改动量小且类型安全。
