## Context

当前菜单栏 app 使用 SwiftUI `MenuBarExtra` 作为入口。`MenuBarExtra` 的 label 只支持单行 `Text` 或模板 `Image`，系统会对 label 内容做模板化处理（强制单色），导致：

- 无法实现多行布局（如上行温度、下行风扇）
- `Text.foregroundColor` 在 label 中被忽略，状态指示点无法显示颜色
- 标签空间有限，单字母缩写 `C` `G` `F` 不够直观

现有文件：
- `FanControlMenuBarApp.swift` — `@main` 入口，使用 `MenuBarExtra` + `.menuBarExtraStyle(.window)`
- `AppState.swift` — 包含 `MenuBarTelemetryStore`、`MenuBarControllerStore`（数据层），`MenuBarExtraLabel`（label view），`MenuBarPanel`（展开面板 view）

数据层（两个 Store）和 `MenuBarPanel` 的逻辑与 `MenuBarExtra` 无耦合，可以直接复用。

## Goals / Non-Goals

**Goals:**
- 将菜单栏 label 迁移到 `NSStatusItem` + 自定义 `NSView`，获得完全绘制控制权
- 实现双行布局：上行 CPU/GPU 温度，下行风扇 RPM + 彩色状态指示器
- 标签使用可读缩写（`CPU` `GPU` `Fan`）替代单字母
- 状态指示器正确渲染颜色（green/orange/red/gray）
- 保持现有 `MenuBarPanel` 的全部功能
- 保持现有数据层（`MenuBarTelemetryStore`、`MenuBarControllerStore`）不变

**Non-Goals:**
- 不重构数据层或 telemetry 读取逻辑
- 不改变 panel 内的 UI 布局或功能
- 不引入新的外部依赖
- 不做 menu bar icon/图标设计（纯文本 + 指示点）

## Decisions

### 1. 使用 NSStatusItem + 自定义 NSView 替代 MenuBarExtra

**选择**: `NSStatusItem` 配合自定义 `StatusItemView`（`NSView` 子类），通过 Core Graphics / `NSAttributedString` 绘制 label 内容。

**理由**: `MenuBarExtra` 的 label 受系统模板化约束，无法实现多行布局和彩色渲染。`NSStatusItem` 是 iStat Menus、Stats.app 等工具的标准做法，对 status bar 区域有完全控制权。

**替代方案**: 继续用 `MenuBarExtra` 但用 `Image` label 渲染离屏 bitmap — 可行但 hack 感强，且需要手动处理 dark/light mode 切换和 DPI 适配。

### 2. App 入口从 SwiftUI App 改为 NSApplicationDelegate

**选择**: 移除 `@main struct FanControlMenuBarApp: App`，改用 `@main class AppDelegate: NSObject, NSApplicationDelegate`，在 `applicationDidFinishLaunching` 中创建 `NSStatusItem`。

**理由**: `NSStatusItem` 的创建和管理需要 `NSStatusBar.system`，这在 `NSApplicationDelegate` 生命周期中最自然。SwiftUI `App` 协议没有直接暴露 `NSStatusItem` API。

**替代方案**: 在 SwiftUI `App` 的 `init` 或 `onAppear` 中通过 `NSStatusBar.system` 创建 — 可行但生命周期管理不够清晰，且仍需要一个空的 `WindowGroup` 或 `Settings` scene 来保持 app 运行。

### 3. Panel 弹出使用 NSPopover

**选择**: 点击 status item 时弹出 `NSPopover`，内部用 `NSHostingView` 承载现有的 `MenuBarPanel` SwiftUI view。

**理由**: `NSPopover` 自动处理箭头指向、点击外部关闭、动画等行为，与 `MenuBarExtra(.window)` 的体验最接近。`MenuBarPanel` 作为 SwiftUI view 可以直接通过 `NSHostingView` 嵌入。

**替代方案**: `NSPanel` — 更灵活但需要手动管理定位、关闭行为、窗口层级，对于当前需求过度复杂。

### 4. Label 布局方案

**选择**: 双行布局，使用 `NSAttributedString` + `NSTextField`（或直接 `draw(_:)` 绘制）：

```
CPU 42°  GPU 46°
Fan 1.2k  ●
```

上行：CPU 和 GPU 温度，使用完整缩写标签
下行：风扇平均 RPM + 彩色状态指示点

**字体**: `.systemFont(ofSize: 9)` 或 `.monospacedDigitSystemFont(ofSize: 9)`，macOS 菜单栏标准小字体。双行在标准 22pt 菜单栏高度内可以容纳。

**颜色指示器**: 使用 `NSImage` 绘制一个小圆点（直径 6-8pt），填充对应状态颜色。这样不受模板化影响。

### 5. 数据绑定方式

**选择**: `StatusItemView` 持有对两个 Store 的引用，通过 Combine `sink` 订阅 `@Published` 属性变化，在回调中调用 `setNeedsDisplay()` 触发重绘。

**理由**: 两个 Store 已经是 `ObservableObject`，Combine 订阅是最直接的桥接方式，不需要改动 Store 的实现。

## Risks / Trade-offs

- [菜单栏高度变化] macOS 未来版本可能改变菜单栏高度 → 使用 `statusItem.button?.frame.height` 动态适配而非硬编码
- [Dark/Light mode] 自定义绘制需要手动处理外观切换 → 监听 `NSApp.effectiveAppearance` 变化，使用 `NSColor.labelColor` 等语义色
- [代码量增加] 从声明式 SwiftUI label 变为命令式 NSView 绘制 → 但 label 逻辑本身不复杂，增量可控
- [Popover 定位] NSPopover 在多显示器场景下偶尔有定位问题 → 这是已知的 macOS 行为，可接受
