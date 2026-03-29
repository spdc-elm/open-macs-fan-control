## Why

Menu bar popover 的 "Automatic control" 区域目前只显示运行状态、配置文件路径和 writer 连接状态，信息量很低。用户无法直观看到当前生效的控制规则——每个热域（CPU / GPU / Memory）的温度区间和对应的 RPM 范围。把这些信息直接展示在 popover 里，可以让用户不打开 config.json 就能确认当前控制策略是否符合预期。

## What Changes

- 在 menu bar popover 的 controller 状态区域下方新增一个 "Control rules" 小节，解析并展示当前活跃配置的控制规则。
- 每个热域显示：域名称、传感器名、起始温度、最高温度、对应的 fan RPM 范围。
- 当 controller 未运行或无活跃配置时，该区域不显示或显示占位提示。
- 控制规则数据通过读取 controller 已知的 config 文件路径获取，在 menu bar 端解析 JSON。

## Capabilities

### New Capabilities
- `config-rule-display`: 在 menu bar popover 中解析并展示当前活跃配置的各热域控制规则摘要（温度区间 + RPM 区间）。

### Modified Capabilities
- `menu-bar-telemetry`: popover 面板新增 control rules 展示区域，扩展 MenuBarPanel 的 UI 布局。

## Impact

- `src/FanControlMenuBar/AppState.swift` — MenuBarPanel view 新增 control rules section；可能需要新增一个轻量的 config 解析 store 或直接在 controllerStore 中读取。
- `src/FanControlRuntime/AutomaticControl.swift` — `AutomaticControlConfig` 和 `ThermalDomainConfig` 已有 `Codable` 支持，可直接复用，无需修改。
- 不涉及 IPC 协议变更；config 文件路径已通过 `AutomaticControlStatusSnapshot.activeConfigPath` 暴露给 menu bar 端。
