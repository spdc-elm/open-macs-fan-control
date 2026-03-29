## Why

当前菜单栏 label 使用 SwiftUI `MenuBarExtra` 渲染，受限于系统对 label 的单行纯文本/模板图像约束，导致两个实际问题：

1. `C` `G` `F` 单字母缩写不直观，用户无法一眼识别各指标含义
2. 状态指示点 `●` 的 `foregroundColor` 在菜单栏模板渲染模式下被系统忽略，实际显示为单色，失去了 idle/running/failed 的颜色区分能力

要实现类似 iStat Menus 那种上下分行、带颜色指示器的紧凑布局，需要迁移到 `NSStatusItem` + 自定义 `NSView`，获得对菜单栏 label 区域的完全绘制控制权。

## What Changes

- 将菜单栏 label 从 `MenuBarExtra` label 迁移到 `NSStatusItem` + 自定义 `NSView`
- 新的 label 布局：上行显示温度（CPU / GPU），下行显示风扇 RPM 和彩色状态指示器
- 标签从单字母缩写改为可读缩写（`CPU` `GPU` `Fan`）
- 状态指示点使用 `NSImage` 或 Core Graphics 直接绘制，确保颜色正确渲染
- 点击 status item 弹出的 panel 保持现有 `MenuBarPanel` 的功能，改用 `NSPopover` 或 `NSPanel` 承载
- 移除对 `MenuBarExtra` 的依赖

## Capabilities

### New Capabilities
- `nsstatusitem-menu-bar`: 基于 NSStatusItem + 自定义 NSView 的菜单栏 label 渲染，支持多行布局和彩色指示器

### Modified Capabilities
- `menu-bar-telemetry`: 行为要求不变，但 label 的视觉呈现方式从单行文本变为双行自定义绘制布局；panel 的弹出机制从 MenuBarExtra window 变为 NSPopover/NSPanel

## Impact

- `src/FanControlMenuBar/AppState.swift` — `MenuBarExtraLabel` 将被替换为新的 `NSView` 子类
- `src/FanControlMenuBar/FanControlMenuBarApp.swift` — 入口从 `MenuBarExtra` 改为 `NSApplicationDelegate` + `NSStatusItem` 设置
- `MenuBarPanel` SwiftUI view 保留，但需要嵌入 `NSHostingView` 用于 popover 内容
- 无 API 或依赖变更，纯 UI 层重构
