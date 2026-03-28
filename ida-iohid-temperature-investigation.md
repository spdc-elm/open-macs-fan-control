# IDA 逆向汇报：Apple Silicon 温度命名与聚合路径

## 本次目标

- 解释为什么我们当前从 IOHID 读到了很多 `PMU tdie*` / `PMU tdev*` 之类的原始名字。
- 确认 Macs Fan Control 里那些更像人类可读字段名的温度项（例如 `CPU Core Average`、`GPU Cluster Average`、`Airport Proximity`）是怎么来的。
- 判断当前项目下一步应优先补哪一层：原始 probe、命名映射、还是聚合逻辑。

## 已确认的关键结论

### 1. IOHID 读温度路径确实存在，而且与当前 MVP 方向一致

在 `TemperatureSensorIOKit::loadAvailableSensors` 中确认到：

- 使用 `PrimaryUsagePage = 0xFF00`
- 使用 `PrimaryUsage = 5`
- `IOHIDEventSystemClientCreate`
- `IOHIDEventSystemClientSetMatching`
- `IOHIDEventSystemClientCopyServices`
- `IOHIDServiceClientCopyProperty(..., "Product")`
- `IOHIDServiceClientCopyEvent(..., 15, ...)`
- `IOHIDEventGetFloatValue(..., 983040)`
- 对 `<= 0` 的温度直接过滤

这和我们当前在 Swift MVP 中接入的 IOHID 路径是同一条主思路，不是偏题探索。

### 2. MFC 的“友好传感器名”不是直接把 IOHID `Product` 原样显示

`TemperatureSensorIOKit::loadAvailableSensors` 的关键流程不是：

- 读出 `Product`
- 直接显示给用户

而是：

- 读出 `Product`
- 调 `SensorsFromXML::sensorByKey(...)`
- 只有命中 XML 元数据的条目，才构造最终的传感器对象

这意味着：

- 我们当前看到的 `PMU tdie6` / `PMU tdev1` 是 **原始 key / 原始 product 名**
- MFC 里看到的 `Airport Proximity` / `CPU Core Average` / `GPU Cluster Average` 不等于 IOHID 原生直接给出的最终显示名

### 3. MFC 存在一层内置 XML 传感器元数据

确认到了这些函数：

- `SensorsFromXML::loadOnce`
- `SensorsFromXML::loadSensorsForMatchedModel`
- `SensorsFromXML::sensorByKey`
- `SensorsFromXML::removeSensorByKey`

`SensorsFromXML::loadOnce` 会：

- 从 Qt resource 中提取一份内置资源
- 解压
- 用 tinyxml2 解析
- 按 `modelMatch` 过滤到当前机型对应的配置

`loadSensorsForMatchedModel` 里还能看到 XML 支持这些字段 / 概念：

- `modelMatch`
- `group`
- `name`
- `key`
- `hideSensors`
- `exclude`
- `add_no_fail`
- `type`

其中 `type` 明确支持这些类别：

- `cpu`
- `gpu`
- `odd`
- `psu`
- `airport`
- `ssd`

这说明 MFC 的传感器展示层不是“直接枚举底层源然后原样显示”，而是：

- 底层 raw sensor
- 机型匹配的 XML 元数据
- 类别与显示名
- 可选隐藏/排除
- 上层聚合

### 4. `Average` 类传感器是后加工出来的，不是底层单点传感器原名

确认到 `TemperatureSensorProvider::addAverageSensors`。

这个函数会：

- 把多个底层传感器按 group 收集起来
- 生成新的 aggregate sensor 对象

因此下面这些更像是**聚合结果**，而不是 raw IOHID name：

- `CPU Core Average`
- `GPU Cluster Average`
- `Power Manager Die Average`

这点非常重要，因为它说明：

- 就算我们拿到了所有 raw IOHID 名，也不能自动推出所有 UI 里显示的 average sensor
- `Average` / `Cluster` / `Proximity` 里至少有一部分是 MFC 自己加工出来的

## 两条路径分别是什么

### 路径 A：原始温度读取路径（IOHID read path）

作用：从 Apple Silicon 设备上读出可用的原始温度数值。

流程：

1. `IOHIDEventSystemClientCreate`
2. matching:
   - `PrimaryUsagePage = 0xFF00`
   - `PrimaryUsage = 5`
3. `IOHIDEventSystemClientCopyServices`
4. 对每个 service：
   - `IOHIDServiceClientCopyProperty(..., "Product")`
   - `IOHIDServiceClientCopyEvent(..., 15, ...)`
   - `IOHIDEventGetFloatValue(..., 983040)`
5. 过滤 `<= 0`

这条路径解决的是：

- “能不能在 Apple Silicon 上读到可信温度值？”

它不直接解决：

- “这些值应该怎样命名得像 MFC 一样？”

### 路径 B：命名 / 分类 / 聚合路径（XML + provider layer）

作用：把底层传感器变成对用户更友好的展示项。

流程：

1. `SensorsFromXML::loadOnce`
   - 读取内置 XML resource
   - 解压并解析
   - 按 `modelMatch` 选当前机型配置
2. `TemperatureSensorIOKit::loadAvailableSensors`
   - 用 IOHID `Product` 作为 key 去查 `SensorsFromXML::sensorByKey`
   - 命中后创建传感器对象
3. `TemperatureSensorProvider::addAverageSensors`
   - 按 group 生成 `Average` / 其他聚合类传感器

这条路径解决的是：

- “为什么 MFC 有更像人话的名字？”
- “为什么 MFC 有 average / cluster / proximity 这类上层概念？”

## 目前能说到什么程度，不能说到什么程度

### 高置信度

- 我们当前 Swift 里读到的 `PMU tdie*` / `PMU tdev*` 是原始 IOHID 层名字
- MFC 的友好名字来自其内部 XML 元数据层，不是简单的 IOHID 原样显示
- `CPU Core Average` / `GPU Cluster Average` / `Power Manager Die Average` 这类名字至少部分来自 provider 层聚合，而不是单点 raw key

### 中等置信度

- `NAND CH0 temp` 这类名字很可能会落在 `ssd` 类别
- `Airport Proximity` / `Power Supply Proximity` 这类名字很可能来自 `airport` / `psu` 类型配置，而不是从 `Product` 直接原样出现

### 当前还不能诚实断言的事

- 不能仅凭现有证据，就把某个具体 `PMU tdie6` 精确断言成 `CPU Performance Core 3`
- 不能仅凭当前 raw dump，就一一恢复 MFC UI 中每个条目的最终命名
- 不能确认 `#1/#2/#3` 这些重复 `Product` 名分别对应哪一组 UI 逻辑核/性能核/GPU cluster 序号

## 为什么我们现在会看到很多重复名字

在当前 MVP 运行里，同一个 `Product` 名可能出现多次，例如：

- `PMU tdie1 #1/#2/#3`
- `PMU tdev4 #1/#2/#3`

这说明：

- 底层存在多个 service，它们共享同一个 `Product` 字符串
- 所以仅靠 `Product` 不能唯一标识最终 UI 传感器项
- MFC 很可能还结合了 XML 配置和 group 逻辑，决定哪些展示、哪些隐藏、哪些合并

## 对当前项目的直接启发

### 短期应该做的

- 保留当前 IOHID path 作为 Apple Silicon 温度主读路径
- 不要继续盲猜大量 SMC 温度 key
- 不要假装 raw IOHID 名就等于最终用户展示名

### 更合理的命名改进顺序

1. 先把 raw IOHID 值稳定读出来
2. 再做一层“友好别名 / 类别名”
3. 如果需要追求接近 MFC 的展示，再继续提取其 XML 资源与机型映射
4. 最后才考虑做平均值 / domain 聚合

## 建议的下一步调研

如果要继续逼近 MFC 的命名层，最值得做的是：

1. 从样本 binary / Qt resource 中提取 `SensorsFromXML` 使用的那份 XML
2. 找当前机型命中的 `modelMatch`
3. 抽出该机型下：
   - raw key
   - friendly name
   - type
   - group
   - hide/exclude 规则
4. 再决定是否把这层映射部分借鉴到当前 CLI

## 本次操作状态

- 已完成相关 IDA 会话观察
- IDA session `9e47cd68` 已关闭
