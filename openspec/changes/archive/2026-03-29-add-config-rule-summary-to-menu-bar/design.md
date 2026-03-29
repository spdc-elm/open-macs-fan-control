## Context

Menu bar popover（`MenuBarPanel`）当前展示三个区域：温度/风扇遥测、controller 状态、风扇详情。Controller 状态区域只显示 phase、config path、writer connectivity，用户无法直观看到当前控制规则的温度区间和 RPM 映射。

`AutomaticControlStatusSnapshot` 已经通过 `activeConfigPath` 暴露了当前活跃配置文件的路径。`AutomaticControlConfig` 和 `ThermalDomainConfig` 已有完整的 `Codable` 支持，可以直接在 menu bar 端解析。

## Goals / Non-Goals

**Goals:**
- 在 popover 的 controller 状态区域下方展示当前活跃配置的控制规则摘要
- 每个热域（CPU / GPU / Memory）显示传感器名、温度区间、RPM 区间
- controller 未运行或无活跃配置时优雅降级

**Non-Goals:**
- 不在 menu bar 端编辑配置（只读展示）
- 不通过 IPC 协议传输配置内容（直接读文件）
- 不展示 smoothingStepRPM、hysteresisRPM 等高级参数

## Decisions

### 1. Config 读取方式：menu bar 端直接读文件

Menu bar 进程通过 `activeConfigPath` 拿到路径后，直接用 `JSONDecoder` 解析 `AutomaticControlConfig`。

替代方案：扩展 IPC 协议让 controller 返回 config 内容。
不选的原因：config 文件是本地 JSON，menu bar 进程有读权限，增加 IPC 字段是不必要的复杂度。

### 2. 解析时机：controller 状态刷新时一并读取

在 `MenuBarControllerStore.refresh()` 中，当 `activeConfigPath` 存在且与上次不同（或首次获取）时，读取并解析 config。解析结果缓存在 store 中，路径不变则不重复读取。`reloadActiveConfig()` 成功后也触发重新解析。

替代方案：独立 timer 定期读取 config 文件。
不选的原因：config 变更只在 controller start/reload 时发生，跟随 controller 状态刷新即可。

### 3. UI 布局：在 controller 状态区域和 Fans 区域之间插入

新增一个 "Control rules" section，用 `Divider` 与上下区域分隔。每个域一行，格式类似：
```
CPU  cpu_core_average  65–80 °C → 1000–4900 rpm
GPU  gpu_cluster_average  65–80 °C → 1000–4900 rpm
Mem  memory_average  55–75 °C → 1000–4900 rpm
```

使用 monospaced digit font 保持对齐。

### 4. 复用 Runtime 类型

直接 `import FanControlRuntime` 使用 `AutomaticControlConfig`、`ThermalDomainConfig`、`FanPolicyConfig`。这些类型已经是 `package` 可见且 `Codable`，无需新增任何 runtime 代码。

## Risks / Trade-offs

- [Config 文件被外部修改但 controller 未 reload] → 展示的规则可能与实际运行的不一致。缓解：在 UI 中展示的是"配置文件中的规则"，不是"controller 内存中的规则"，语义上是准确的。且用户可以点 "Reload control" 使两者同步。
- [Config 文件不可读或格式错误] → 解析失败时不展示 control rules section，不影响其他功能。
- [多 fan 配置] → 每个域的 RPM 范围取自 fans 数组。当前只有一个 fan，直接取 `fans[0]`。如果未来有多 fan，可以展示每个 fan 的映射或取 min/max 范围。当前先按单 fan 处理，多 fan 时显示所有 fan 的范围。
