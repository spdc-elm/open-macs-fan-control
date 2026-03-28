# Max Fan Control（Apple Silicon）温度传感器读取逻辑还原

## 目标

这份文档只回答一件事：**Max Fan Control 在 Apple Silicon 上是怎么读单个温度传感器的**，并把它整理成一份可以直接照着实现的说明。

我这里说的“单个温度传感器”，指的是一次从一个 `IOHIDServiceClient` 读出一个温度值的最小读取单元；不是 UI 里的 average / cluster / proximity 聚合项。

---

## 结论先行

在 Apple Silicon 路径上，Max Fan Control 读温度的主逻辑不是“遍历一堆 SMC 温度 key”，而是：

1. 创建 `IOHIDEventSystemClient`
2. 用下面这组 matching 过滤热传感器类 service：
   - `PrimaryUsagePage = 0xFF00`
   - `PrimaryUsage = 5`
3. 枚举所有命中的 `IOHIDServiceClient`
4. 读取每个 service 的 `Product` 属性，作为原始名字 / 匹配 key
5. 调 `IOHIDServiceClientCopyEvent(service, 15, 0, 0)`
6. 调 `IOHIDEventGetFloatValue(event, 983040)` 取出摄氏温度
7. 过滤 `<= 0` 的值
8. 再把 `Product` 丢给内置 XML 映射层，决定它是不是 UI 里要展示的传感器

所以：

- **底层单点温度读取 API 是 IOHID，不是 SMC key。**
- **MFC 的友好名称不是 IOHID 直接返回的，而是后面又过了一层 XML 映射。**

---

## 逆向证据

### 1) 枚举 IOKit/IOHID 温度传感器

函数：`TemperatureSensorIOKit::loadAvailableSensors`

- 地址：`0x10006b88c`
- 关键字符串：
  - `PrimaryUsagePage`
  - `PrimaryUsage`
  - `Product`
  - `Sensors/TempSensorIOKit.mm`
  - `IOKit sensor: {}, {} C`
  - `Skipped incorrect temperature [{}]`

确认到的调用链：

- `IOHIDEventSystemClientCreate`
- `IOHIDEventSystemClientSetMatching`
- `IOHIDEventSystemClientCopyServices`
- `IOHIDServiceClientCopyProperty(service, CFSTR("Product"))`
- `IOHIDServiceClientCopyEvent(service, 15, 0, 0)`
- `IOHIDEventGetFloatValue(event, 983040)`

### 2) 单个传感器的实时刷新

函数：`TemperatureSensorIOKit::UpdateValue`

- 地址：`0x10006b820`

反编译核心逻辑：

```cpp
event = IOHIDServiceClientCopyEvent(service, 15, 0, 0);
if (event) {
    value = IOHIDEventGetFloatValue(event, 983040);
    CFRelease(event);
} else {
    value = 0;
}
atomic_store(value, this->currentTemperature);
```

这就是单个传感器最核心的读取逻辑。

### 3) 上层总入口

函数：`TemperatureSensorProvider::load`

- 地址：`0x100043460`

它会同时加载：

- `TemperatureSensorSMC`
- `TemperatureSensorIOKit`
- `TemperatureSensorGPU`
- `TempSensorDisk`

其中 Apple Silicon 温度这条线，重点就是 `TemperatureSensorIOKit::loadAvailableSensors`。

### 4) 后续周期刷新

函数：`QFanControl::updateThread`

- 地址：`0x10002f34c`

这个线程会：

1. 从 `TemperatureSensorProvider::getAllSensorsSorted` 取出所有传感器对象
2. 对每个对象调用虚函数 `UpdateValue`
3. 从对象里读出：
   - 传感器 id（offset `+8`）
   - 当前温度（offset `+16`，atomic double）
4. 发出 `QFanControl::sensor_update(id, value)` 更新 UI

所以 Max Fan Control 不是每次都重新枚举 IOHID service；**枚举一次，持有 service，后面循环读 event 值。**

---

## 它实际怎么筛出“热传感器 service”

`TemperatureSensorIOKit::loadAvailableSensors` 里构造的 matching dictionary 逻辑已经确认：

```text
PrimaryUsagePage = 0xFF00
PrimaryUsage     = 5
```

对应实现形态大致是：

```cpp
CFStringRef key1 = CFStringCreateWithCString(NULL, "PrimaryUsagePage", 0);
CFStringRef key2 = CFStringCreateWithCString(NULL, "PrimaryUsage", 0);

int usagePage = 0xFF00;
int usage = 5;

CFNumberRef value1 = CFNumberCreate(NULL, kCFNumberSInt32Type, &usagePage);
CFNumberRef value2 = CFNumberCreate(NULL, kCFNumberSInt32Type, &usage);

CFDictionaryRef matching = CFDictionaryCreate(
    NULL,
    [key1, key2],
    [value1, value2],
    2,
    &kCFTypeDictionaryKeyCallBacks,
    &kCFTypeDictionaryValueCallBacks
);

IOHIDEventSystemClientSetMatching(client, matching);
```

如果你要复现 MFC 的 Apple Silicon 温度路径，这两个常量必须先对上。

---

## 单个传感器读取的可复现版本

下面这段 Swift 逻辑，是按已确认的 MFC 读取路径整理出来的“最小可用版本”。

```swift
import Foundation
import IOKit.hidsystem

private let primaryUsagePage = 0xFF00
private let primaryUsage = 5
private let temperatureEventType: Int64 = 15
private let temperatureField: Int32 = Int32(15 << 16) // 983040

struct IOHIDTemperatureReading {
    let product: String
    let valueCelsius: Double
}

func readAppleSiliconTemperatures() -> [IOHIDTemperatureReading] {
    guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
        return []
    }

    let matching: CFDictionary = [
        kIOHIDPrimaryUsagePageKey: primaryUsagePage,
        kIOHIDPrimaryUsageKey: primaryUsage
    ] as CFDictionary

    _ = IOHIDEventSystemClientSetMatching(client, matching)

    guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
        return []
    }

    return services.compactMap { service in
        guard let event = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0)?.takeRetainedValue() else {
            return nil
        }

        let value = IOHIDEventGetFloatValue(event, temperatureField)
        guard value > 0 else {
            return nil
        }

        let product = (IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String)
            ?? "Unnamed IOHID sensor"

        return IOHIDTemperatureReading(product: product, valueCelsius: value)
    }
}

private typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClient,
    _ eventType: Int64,
    _ options: Int32,
    _ timestamp: Int64
) -> Unmanaged<IOHIDEventRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double
```

这段代码对应的是 **“把底层原始 IOHID 温度全部读出来”**，不是“复刻 MFC 全部 UI 命名逻辑”。

---

## MFC 的命名层是怎么接上的

MFC 不是直接把 `Product` 显示给用户。

它后面还有一层 `SensorsFromXML`：

- `SensorsFromXML::loadOnce` @ `0x10003e42c`
- `SensorsFromXML::loadSensorsForMatchedModel` @ `0x10003d62c`
- `SensorsFromXML::sensorByKey` @ `0x10003e814`

资源路径在 `InitFunc_21` @ `0x10006cba8` 里已经确认：

```text
:/Resources/xml/IOKitSensors.xml.gz
```

逻辑是：

1. 从 Qt resource 读取 `IOKitSensors.xml.gz`
2. 解压并用 tinyxml2 解析
3. 按当前机型命中 `modelMatch`
4. 用 `Product` 去查 XML 里的传感器定义
5. 命中才创建最终 `TemperatureSensorIOKit` 对象

因此：

- 你自己工具里直接读出来的名字，多半是 `PMU tdie*` / `PMU tdev*` 这种原始名字
- MFC UI 里更像人话的名字，来自 XML 映射，不是底层 API 直接给的

---

## MFC 对单点温度值做了哪些过滤

目前已经确认到两条：

### 1. 枚举阶段过滤

在 `TemperatureSensorIOKit::loadAvailableSensors` 中：

- 先读一次温度
- 如果 `value <= 0`，直接跳过
- 对应日志字符串：`Skipped incorrect temperature [{}]`

### 2. 刷新阶段

在 `TemperatureSensorIOKit::UpdateValue` 中：

- 如果 `IOHIDServiceClientCopyEvent(...)` 失败，则写入 `0`
- 上层 UI 更新时继续按自己的逻辑处理

所以如果你要做一个“行为尽量接近 MFC”的实现，最起码要：

- 枚举阶段过滤 `<= 0`
- 刷新阶段允许 event 缺失并返回 `0` / 无值

---

## 为什么你会看到重复名字

MFC 的底层 key 是 `Product`。但同一个 `Product` 可能对应多个 service。

所以现实里会出现：

- `PMU tdie1 #1`
- `PMU tdie1 #2`
- `PMU tdie1 #3`

这不是你读错了，而是：

- **多个 service 共享同一个 `Product` 字符串**
- `Product` 本身不能保证唯一

MFC 的做法不是在底层消灭这种重复，而是后面再靠 XML / group / hide 规则继续整理。

---

## 如果你只想复刻“单个传感器温度读取”

那就只做下面这些：

1. `IOHIDEventSystemClientCreate`
2. matching：`0xFF00 / 5`
3. `IOHIDEventSystemClientCopyServices`
4. 对每个 service：
   - `IOHIDServiceClientCopyProperty(..., Product)`
   - `IOHIDServiceClientCopyEvent(..., 15, 0, 0)`
   - `IOHIDEventGetFloatValue(..., 983040)`
   - `value > 0` 才保留

这就已经是 MFC 在 Apple Silicon 上的真实底层读法了。

---

## 如果你想进一步复刻到“接近 MFC UI”

还差两层：

1. **XML 命名 / 分类层**
   - `:/Resources/xml/IOKitSensors.xml.gz`
   - `modelMatch`
   - `key/name/type/group/hide/exclude/add_no_fail`

2. **Provider 聚合层**
   - `TemperatureSensorProvider::addAverageSensors`
   - 负责生成 `Average` / `Greatest` 这类上层传感器

如果不做这两层，你拿到的是“真实原始温度值”；如果做了，才会逐渐接近 MFC 的最终展示。

---

## 现在能不能把名字做得对人类友好一些？

现在可以更明确地回答：**可以，而且我已经把 MFC 内置的 `IOKitSensors.xml.gz` 提出来了。**

提取结果：

- `extracted-IOKitSensors.xml.gz`
- `extracted-IOKitSensors.xml`

也就是说，Apple Silicon 这条 IOKit 温度路径里，MFC 的友好命名不是猜的，而是来自一份已经落地的内置 XML 映射。

但也要先说清边界：

- **能对上一部分传感器的人类友好名字**：可以
- **能给所有 raw 名字都补成非常准确的硬件归属**：还不行

原因很简单：XML 本身只覆盖了其中一部分 IOKit 传感器。

### 已提取到的 XML 内容

`extracted-IOKitSensors.xml` 的内容非常短，只有一个：

```xml
<modelMatch models="all">
```

说明这份映射不是按具体机型细分，而是一个通用 Apple Silicon IOKit 名字表。

里面确认到的友好映射包括：

| Raw `Product` | MFC 友好名 | 备注 |
|---|---|---|
| `gas gauge battery` | `Battery Gas Gauge` | 电池气量计 |
| `NAND CH0 temp` | `SSD` | 标了 `type="ssd"` |
| `SOC MTR Temp Sensor0` | `M1 SOC Sensor 1` | SoC 传感器 |
| `SOC MTR Temp Sensor1` | `M1 SOC Sensor 2` | SoC 传感器 |
| `SOC MTR Temp Sensor2` | `M1 SOC Sensor 3` | SoC 传感器 |
| `GPU MTR Temp Sensor1` | `GPU Sensor 1` | 在组 `GPU Proximity` 下 |
| `GPU MTR Temp Sensor4` | `GPU Sensor 2` | 在组 `GPU Proximity` 下 |
| `eACC MTR Temp Sensor0` | `CPU Efficiency Cores Package 1` | 在组 `CPU Efficiency Cores Average` 下 |
| `eACC MTR Temp Sensor3` | `CPU Efficiency Cores Package 2` | 在组 `CPU Efficiency Cores Average` 下 |
| `pACC MTR Temp Sensor2` | `CPU Performance Cores Package 1` | 在组 `CPU Performance Cores Average` 下 |
| `pACC MTR Temp Sensor3` | `CPU Performance Cores Package 2` | 同上 |
| `pACC MTR Temp Sensor4` | `CPU Performance Cores Package 3` | 同上 |
| `pACC MTR Temp Sensor5` | `CPU Performance Cores Package 4` | 同上 |
| `pACC MTR Temp Sensor7` | `CPU Performance Cores Package 5` | 同上 |
| `pACC MTR Temp Sensor8` | `CPU Performance Cores Package 6` | 同上 |
| `pACC MTR Temp Sensor9` | `CPU Performance Cores Package 7` | 同上 |
| `ANE MTR Temp Sensor1` | `M1 Neural Engine` | ANE |
| `ISP MTR Temp Sensor5` | `M1 Image Signal Processor` | ISP |
| `PMGR SOC Die Temp Sensor0` | `Power Manager SOC Die 1` | 在组 `Power Manager SOC Die Average` 下 |
| `PMGR SOC Die Temp Sensor1` | `Power Manager SOC Die 2` | 同上 |
| `PMGR SOC Die Temp Sensor2` | `Power Manager SOC Die 3` | 同上 |
| `PMU tdie1` | `Power Manager Die 1` | 在组 `Power Manager Die Average` 下 |
| `PMU tdie2` | `Power Manager Die 2` | 同上 |
| `PMU tdie4` | `Power Manager Die 4` | 同上 |
| `PMU tdie5` | `Power Manager Die 5` | 同上 |
| `PMU tdie6` | `Power Manager Die 6` | 同上 |
| `PMU tdie7` | `Power Manager Die 7` | 同上 |
| `PMU tdie8` | `Power Manager Die 8` | 同上 |

此外还确认到了这些 group 名：

- `GPU Proximity`
- `CPU Efficiency Cores Average`
- `CPU Performance Cores Average`
- `Power Manager SOC Die Average`
- `Power Manager Die Average`

这说明两件事：

1. **现在已经可以把一部分 raw 传感器名替换成 MFC 自己使用的友好名称。**
2. **group 信息也已经拿到了，后面如果要做 average sensor，信息也够。**

### 等级 1：可立即做到的友好化

这一级不用继续深挖 binary，也已经够实用：

- 保留 raw `Product`
- 对重复项加序号
- 再按模式做粗分类

例如：

- `PMU tdie1 #1` → `PMU Die Sensor 1 #1`
- `PMU tdev4 #2` → `PMU Device Sensor 4 #2`
- `gas gauge battery` → `Battery Sensor`

这一层的优点：

- 立刻能用
- 不会假装自己知道更多
- 不容易把名字标错

这一层的缺点：

- 仍然不等于 MFC 的最终 UI 命名
- 不能可靠说出“这是 CPU P-core 3”这种物理归属

### 等级 2：接近 MFC 的友好命名

这一级现在已经从“理论上能做”推进到“已经拿到关键映射表”。

因为我已经确认并提取了：

- `TemperatureSensorIOKit::loadAvailableSensors` 的 XML 依赖
- 资源路径 `:/Resources/xml/IOKitSensors.xml.gz`
- 解压后的实际映射内容

所以现在可用的命名策略应该改成：

1. 先按 XML 做精确映射
2. 如果 XML 没命中，再退回 raw 名字
3. 对重复 raw 名补 `#1/#2/#3`

### 当前最诚实的结论

如果你的标准是：

- “别再是纯 `PMU tdie6` 这种难看原名”

那么现在已经足够进入实现阶段，而且可以直接用提取出来的 XML 表。

如果你的标准是：

- “尽量跟 MFC UI 一样，出现 `CPU Core Average`、`Airport Proximity`、`Power Manager Die Average` 这类名字”

那么要更细一点：

- **单点传感器的友好名**：现在已经能做
- **聚合项最终展示名**：group 已经有了，但还需要你自己的 provider 层把这些单点聚合出来

### 实用建议

当前阶段最稳的做法是两层输出：

1. `displayName`：温和友好化后的名字
2. `rawName`：保留原始 `Product`

例如：

```text
CPU/PMU Die Sensor 1 #1   (raw: PMU tdie1)
CPU/PMU Device Sensor 4 #2 (raw: PMU tdev4)
Battery Sensor             (raw: gas gauge battery)
```

现在建议把策略升级成三层：

1. `displayNameFromXML`：若 XML 命中，用 MFC 的友好名
2. `groupName`：若 XML 带 group，保留下来
3. `rawName`：永远保留原始 `Product`

例如：

```text
Power Manager Die 6      (raw: PMU tdie6, group: Power Manager Die Average)
CPU Performance Cores Package 4 (raw: pACC MTR Temp Sensor5, group: CPU Performance Cores Average)
Battery Gas Gauge        (raw: gas gauge battery)
```

这样做的好处是：

- 对人类已经友好很多
- 出问题时还能回到 raw 名字排查
- 已经最大程度贴近了 MFC 的单点命名逻辑
- 后面如果要做 average sensor，可以直接利用现成 `group` 信息

---

## 当前已知、未知边界

### 已知

- Apple Silicon 温度主读路径是 IOHID
- 匹配常量是 `PrimaryUsagePage=0xFF00`、`PrimaryUsage=5`
- 单点读值参数是 `eventType=15`、`field=983040`
- `Product` 是原始命名 key
- `<= 0` 会被过滤

### 还没在这份文档里展开的

- `IOKitSensors.xml.gz` 里每个机型的精确 friendly name 映射
- `CPU Core Average` / `GPU Cluster Average` 等聚合项的完整生成细节
- 某个具体 `PMU tdieN` 对应哪颗核/哪块物理区域

这些不是没做，而是它们已经超出“单个温度传感器读取逻辑”的范围了。

---

## 最短实现摘要

如果你只想记住一句话：

> **在 Apple Silicon 上，Max Fan Control 是通过 `IOHIDEventSystemClient` 枚举 `PrimaryUsagePage=0xFF00, PrimaryUsage=5` 的 HID service，然后对每个 service 调 `IOHIDServiceClientCopyEvent(..., 15, 0, 0)` 和 `IOHIDEventGetFloatValue(..., 983040)` 读取温度。**

这句就是底层真相。
