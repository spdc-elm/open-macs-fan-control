## 1. App 入口迁移

- [x] 1.1 创建 `AppDelegate.swift`：`@main class AppDelegate: NSObject, NSApplicationDelegate`，在 `applicationDidFinishLaunching` 中初始化 `NSStatusItem`、两个 Store、以及 popover
- [x] 1.2 移除 `FanControlMenuBarApp.swift` 中的 `@main struct FanControlMenuBarApp: App` 及其 `MenuBarExtra` 用法

## 2. 自定义 Status Item Label View

- [x] 2.1 创建 `StatusItemLabelView.swift`（`NSView` 子类），实现双行绘制逻辑：上行 `CPU xx° GPU xx°`，下行 `Fan xxxrpm ●`，使用 `NSAttributedString` + `draw(in:)` 或 `NSTextField` 子视图
- [x] 2.2 实现彩色状态指示点绘制：使用 Core Graphics 绘制 6-8pt 圆形，根据 controller phase 填充 green/orange/red/gray
- [x] 2.3 处理 dark/light mode 适配：使用 `NSColor.labelColor` 等语义色，监听外观变化触发重绘
- [x] 2.4 处理 unavailable 占位符：当温度或风扇数据不可用时显示 `--`

## 3. 数据绑定与刷新

- [x] 3.1 在 `StatusItemLabelView` 中通过 Combine `sink` 订阅 `MenuBarTelemetryStore.$snapshot` 和 `MenuBarControllerStore.$status`，变化时调用 `needsDisplay = true`
- [x] 3.2 确保 `NSStatusItem.button` 的 frame 宽度随内容动态调整（`invalidateIntrinsicContentSize` + `intrinsicContentSize` override）

## 4. Popover 集成

- [x] 4.1 创建 `NSPopover` 实例，`contentViewController` 使用 `NSHostingController` 承载现有 `MenuBarPanel` SwiftUI view
- [x] 4.2 实现点击 status item button 时 toggle popover 的逻辑（show/close）
- [x] 4.3 确保 popover 在点击外部时自动关闭（`.transient` behavior）

## 5. 清理与验证

- [x] 5.1 移除 `MenuBarExtraLabel` struct（已被 `StatusItemLabelView` 替代）
- [x] 5.2 确认 `MenuBarPanel`、`MenuBarTelemetryStore`、`MenuBarControllerStore` 无需修改即可在新架构下工作
- [x] 5.3 验证构建通过（`swift build`），确认无编译错误
