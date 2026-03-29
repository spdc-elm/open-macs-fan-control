## 1. Config 解析与缓存

- [x] 1.1 在 `MenuBarControllerStore` 中新增 `@Published` 属性 `activeConfig: AutomaticControlConfig?`，用于缓存当前活跃配置的解析结果
- [x] 1.2 在 `MenuBarControllerStore.refresh()` 中，当 `activeConfigPath` 存在时读取并解析 config JSON；路径不变且已缓存则跳过；路径变化或首次获取时重新解析；解析失败时置为 `nil`
- [x] 1.3 在 `reloadActiveConfig()` 成功后清除缓存，使下次 refresh 重新解析

## 2. Control Rules UI

- [x] 2.1 在 `MenuBarPanel` 中新增 `controlRulesSection` view，在 controller 状态区域和 Fans 区域之间，用 `Divider` 分隔
- [x] 2.2 `controlRulesSection` 仅在 controller phase 为 `running` 且 `activeConfig` 非 nil 时显示
- [x] 2.3 每个热域（CPU / GPU / Memory）显示一行，格式：域标签、传感器名、温度区间（start–max °C）、RPM 区间（min–max rpm）；Memory 域仅在 config 中存在 `memoryDomain` 时显示
- [x] 2.4 多 fan 场景：当 `fans.count > 1` 时，每个域下按 fan index 分行显示各自的 RPM 范围

## 3. 验证

- [x] 3.1 构建 menu bar app（`swift build --product fan-control-menu-bar`），确认编译通过
- [x] 3.2 打包并运行（`bash scripts/package-menu-bar-app.sh && open dist/MacsFanControlMenuBar.app`），在 controller running 状态下确认 control rules section 正确显示
