# Max Fan Control 温度来源总览（含 Swift 还原建议）

## 目标

这份文档回答的是：

1. Max Fan Control 的温度数据一共有几条来源路径
2. 它们在程序里是怎样被组织成一个**多来源共同工作的结构**
3. 我们在 Swift 里下一步应怎样把这些路径逐条还原出来

这不是只讲 IOHID 的文档；它是总览。

---

## 总结先行

在当前 arm64 样本里，温度不是单一路径提供的，而是一个 **provider 聚合结构**。

总入口：

- `TemperatureSensorProvider::load` @ `0x100043460`

它会同时加载 4 类来源：

1. `TemperatureSensorIOKit`
2. `TemperatureSensorSMC`
3. `TemperatureSensorGPU`
4. `TempSensorDisk`

也就是说，MFC 的结构不是：

- “找一个最好用的 API，所有温度都从那里来”

而是：

- **每种来源各自发现传感器 → 各自刷新数值 → provider 合并成统一传感器列表 → UI 统一显示**

这点对 Swift 复刻非常重要。

如果你在 Swift 层面只还原了 IOHID，一旦 IOHID 没直接给出你想要的 CPU/GPU 名称，你就会误以为“软件没有这些温度”。

其实不是。更接近真相的是：

- **你只实现了总架构里的其中一条来源。**

---

## 多来源共同结构

### 1. 加载阶段

`QFanControl::initialLoadThread` @ `0x10002de0c`

会调用：

- `TemperatureSensorProvider::load(*(this + 4), *(this + 3), *(this + 5))`

而 `TemperatureSensorProvider::load` 里明确做了这几件事：

- `TemperatureSensorIOKit::loadAvailableSensors(...)`
- `TemperatureSensorSMC::loadAvailableSensors(...)`
- `TemperatureSensorGPU::loadAvailableSensors(...)`
- `TempSensorDisk::loadAvailableSensors(...)`

然后 provider 把这些来源得到的对象分别保存起来。

### 2. 合并阶段

`TemperatureSensorProvider::getAllSensorsSorted` @ `0x100043f5c`

会把不同来源的传感器对象统一收集到一个列表里：

- IOKit 列表
- SMC 列表
- Disk 列表
- GPU 列表

再统一排序，供上层刷新线程使用。

### 3. 刷新阶段

`QFanControl::updateThread` @ `0x10002f34c`

会：

1. 从 `TemperatureSensorProvider::getAllSensorsSorted` 取所有传感器对象
2. 对每个对象调虚函数 `UpdateValue`
3. 读对象里的当前温度
4. 调 `QFanControl::sensor_update(id, value)` 更新 UI

所以在架构上，MFC 用的是典型的：

- **discover once**
- **refresh many times**

不是每轮都重新枚举所有硬件。

---

## 路径 1：IOKit / IOHID 温度路径

### 已确认函数

- `TemperatureSensorIOKit::loadAvailableSensors` @ `0x10006b88c`
- `TemperatureSensorIOKit::UpdateValue` @ `0x10006b820`

### 作用

这是当前 Apple Silicon 上最直接、最明确的温度读取路径。

### 已确认读取链

- `IOHIDEventSystemClientCreate`
- `IOHIDEventSystemClientSetMatching`
- matching:
  - `PrimaryUsagePage = 0xFF00`
  - `PrimaryUsage = 5`
- `IOHIDEventSystemClientCopyServices`
- `IOHIDServiceClientCopyProperty(service, "Product")`
- `IOHIDServiceClientCopyEvent(service, 15, 0, 0)`
- `IOHIDEventGetFloatValue(event, 983040)`

### 命名层

它不是直接把 `Product` 显示给用户，而是再查：

- `:/Resources/xml/IOKitSensors.xml.gz`

你现在已经提取到了：

- `extracted-IOKitSensors.xml`

因此 Swift 里这条已经能做到：

- 读 raw 值
- 按 XML 做 friendly 命名

### Swift 还原状态

这一条已经基本打通。

当前代码位置：

- `src/FanControlMVP/IOHID.swift`
- `src/FanControlMVP/IOHIDMetadata.swift`

---

## 路径 2：SMC 温度路径

### 已确认函数

- `TemperatureSensorSMC::loadAvailableSensors` @ `0x100047bb0`
- `TemperatureSensorSMC::loadSmcSensors` @ `0x10004788c`
- `TemperatureSensorSMC::UpdateValue` @ `0x100047370`
- `SMC::Service::getTemperatureKeys` @ `0x10004d370`
- `SMC::Service::getTemperature` @ `0x10004e294`
- `SMC::PlatformMac::readKey` @ `0x10006e2c0`

### 作用

这条是传统 SMC 温度路径。

在当前样本里，它不是“手写少数几个 key”，而是：

1. 先通过 `SMC::Service::getTemperatureKeys(...)` 找出温度相关 key
2. 把 key 转成 `QString`
3. 结合 XML 元数据过滤 / 命名
4. 为每个支持的 key 创建 `TemperatureSensorSMC` 对象

### `UpdateValue` 的实际逻辑

`TemperatureSensorSMC::UpdateValue` 做的事非常直白：

1. 取对象保存的 SMC key
2. 转成 UTF-8 C 字符串
3. 调 `SMC::Service::getTemperature(service, key, &value, 0)`
4. 对某些 core sensor 再调 `fixLowValueForCoreSensor2023(...)`
5. 只在 `value >= 10.0` 时更新当前值

### `SMC::Service::getTemperature` 的实际逻辑

这一步已经看到细节：

- 底层会走平台层 `readKey`
- 按返回类型做转换
  - `type == 2`：按整数 + 1/256 小数位处理
  - `type == 4`：直接当 float
- 过滤异常值：
  - `<= 0`
  - `>= 127`

### `SMC::PlatformMac::readKey` 的实际逻辑

当前 arm64 样本里，平台层会：

- 持有 `AppleSMC` 连接
- 调 `SMCReadKey(...)`
- 把结果字节复制到调用方缓冲区

### 对 Swift 的实操建议

当前 Swift 已经有：

- `src/FanControlMVP/SMC.swift`
- `CSMCBridge.h`

它已经能：

- 打开 `AppleSMC`
- 读取指定 key
- 解析 `sp78` / `flt ` / `fp88`

但它**还没有复刻 MFC 的 `getTemperatureKeys()` 扫描逻辑**。

所以如果你要补这条路，现实上有两种做法：

#### 做法 A：先做实用版

- 继续维护一份候选 SMC key 列表
- 用现有 `readTemperature(key:)` 扫这些 key
- 把读到的值并入总结果

优点：

- 实现快
- 和当前 Swift 代码兼容

缺点：

- 不等于 MFC 的“自动发现全部温度 key”

#### 做法 B：继续逼近 MFC

- 在 C bridge 里补 SMC key 枚举能力
- 复刻 `getTemperatureKeys()` 那套扫描逻辑
- 再做 XML 命名与过滤

优点：

- 更接近 MFC

缺点：

- 工作量明显更大

### 结论

Swift 里这条路**可以还原**，而且基础设施已经有了；只是当前实现还停在“按已知 key 读”，没到“MFC 那种自动发现 key”的程度。

---

## 路径 3：GPU 路径

### 已确认函数

- `TemperatureSensorGPU::UpdateValue` @ `0x1000423b0`
- `TemperatureSensorGPU::loadAvailableSensors` @ `0x1000426bc`
- `GPU::ProviderMac::discoverGPUs` @ `0x10006a664`
- `GPU::ProviderMac::getCoreTemperature` @ `0x10006ac74`
- `GPU::Card::getCoreTemperature` @ `0x10003ce30`

### 这条路在当前 arm64 样本里要特别小心

这里有一个很关键的事实：

- `GPU::ProviderMac::getCoreTemperature(...)` 在这个 arm64 样本里**直接返回 0.0**

也就是说，当前样本里并没有看到一个真正可用的“直接 GPU 温度读取实现”。

### 但 GPU provider 不是完全没用

`GPU::ProviderMac::discoverGPUs` 仍然会：

1. `IOServiceMatching("AGXFamilyAccelerator")`
2. `IOServiceGetMatchingServices(...)`
3. 对每个 entry 调 `IORegistryEntryCreateCFProperties(...)`
4. 从属性里取：
   - `model`
   - `gpu-core-count`
5. 调 `GPU::Provider::addGPU(...)` 创建设备对象

所以这条路目前至少承担：

- **发现 GPU 设备**
- **记录 GPU 基本属性**

### `TemperatureSensorGPU::UpdateValue` 的逻辑

它的行为是：

1. 如果有 `GPU::Card` 且未切到 fallback 模式：
   - 调 `GPU::Card::getCoreTemperature()`
2. 如果得到 `0.0`：
   - 记录日志 `Trying SMC instead`
   - 切换到 fallback 模式
3. fallback 模式下：
   - 调一个附加的 SMC 传感器对象的 `UpdateValue`
   - 然后把那个 SMC 传感器的当前值复制过来

### fallback 依赖哪些 SMC key

`TemperatureSensorProvider` 里还专门有：

- `getSmcGPUDieSensor()`
  - 优先找 `TG0D`
  - 找不到再找 `TGDD`
- `getSmcIntelGPUSensor()`
  - 找 `TCGC`

这说明 GPU 路径在实际运行里，**很可能会退回到 SMC GPU 相关 key。**

### 对 Swift 的实操建议

这里要避免一个错误预期：

- 不要假设当前 arm64 样本已经告诉你“直接读 Apple Silicon GPU 温度的稳定 API”

它没有。

更稳的 Swift 复刻方案是：

#### 第一阶段

- 先实现 GPU 设备发现：
  - `IOServiceMatching("AGXFamilyAccelerator")`
  - `IORegistryEntryCreateCFProperties(...)`
  - 取 `model`
  - 取 `gpu-core-count`

#### 第二阶段

- 如果后续确认到了可用的 direct temperature property，再补 direct read

#### 当前最实用的阶段

- 在输出层把 GPU 相关 SMC fallback 也并进来：
  - `TG0D`
  - `TGDD`
  - `TCGC`

### 结论

在当前 arm64 样本里，GPU 路径更像：

- **GPU 设备发现 + SMC fallback 容器**

而不是“已经成熟的 direct GPU temp provider”。

这点一定要和 x86 / 旧版思路区分开。

---

## 路径 4：磁盘温度路径

### 已确认函数

- `TempSensorDisk::loadAvailableSensors` @ `0x100040448`
- `TempSensorDiskMac::UpdateValue` @ `0x1000413dc`
- `TempSensorDisk::readSmartTemperature` @ `0x10003f7ac`
- `TempSensorDisk::readNVMeDriveTemperature` @ `0x10003f80c`

### 作用

这是磁盘 / SSD 温度来源。

### `loadAvailableSensors` 的逻辑

当前样本里能确认：

1. 先取本机驱动器列表
2. 区分：
   - `ATA`
   - `NVME`
3. 为每块支持的盘创建传感器对象

### `UpdateValue` 的逻辑

`TempSensorDiskMac::UpdateValue` 会：

- 如果盘类型是 `ATA`
  - 走 SMART 读取
  - 调 `readSmartTemperature(...)`
- 如果盘类型是 `NVME`
  - 读 NVMe smart / identify 数据
  - 调 `readNVMeDriveTemperature(...)`

### 对 Swift 的实操建议

这条路不属于你最关心的 CPU/GPU，但如果你要接近 MFC 全貌，它是最好补的一条，因为：

- 输入输出边界清晰
- 不依赖复杂聚合

但它涉及 SMART / NVMe 层，工作量比纯 IOHID 稍大。

---

## 4 条路径之间怎么配合

最重要的一句话：

> **MFC 不是“IOHID 优先，失败才 SMC”的单路径程序，而是多个来源并行建模、统一合并。**

更准确的结构是：

- IOKit / IOHID：负责一批 SoC / PMU / package 温度
- SMC：负责传统 key-based 传感器，也承担部分 fallback
- GPU：负责 GPU 设备发现，并在当前 arm64 样本里可回落到 SMC GPU 相关 key
- Disk：负责 ATA / NVMe 温度

然后：

- `TemperatureSensorProvider::getAllSensorsSorted` 统一合并
- `QFanControl::updateThread` 统一刷新

---

## 为什么你当前 Swift 版容易“少传感器”

因为当前 `TemperatureProbe.run()` 的逻辑是：

- 先跑 IOHID
- 只要 IOHID 非空就 `return`

也就是说：

- SMC 不会并入
- GPU 不会并入
- Disk 不会并入

这和 MFC 的真实结构不一致。

---

## Swift 侧建议的目标结构

建议直接改成下面这种统一模型：

```swift
enum TemperatureSource {
    case iohid
    case smc
    case gpu
    case disk
}

struct UnifiedTemperatureReading {
    let source: TemperatureSource
    let rawName: String
    let displayName: String
    let valueCelsius: Double
    let group: String?
    let type: String?
}
```

然后每条路径各自返回自己的数组：

- `IOHIDTemperatureProbe.readAll()`
- `SMCTemperatureProbe.readAll()`
- `GPUTemperatureProbe.readAll()`
- `DiskTemperatureProbe.readAll()`

最后统一合并：

```swift
let all =
    IOHIDTemperatureProbe.readAllUnified() +
    SMCTemperatureProbe.readAllUnified() +
    GPUTemperatureProbe.readAllUnified() +
    DiskTemperatureProbe.readAllUnified()
```

这才是和 MFC 架构方向一致的实现方式。

---

## Swift 实施优先级

### 优先级 1：先修正总结构

把现在的：

- `IOHID 有值就 return`

改成：

- `多来源都收集，再统一输出`

这是最先要改的。

### 优先级 2：补 SMC 合并路径

最务实做法：

- 先用候选 key 列表 + 现有 `SMCConnection.readTemperature(key:)`
- 把读到的有效值并入统一输出

这一步可以先做到 70 分。

### 优先级 3：补 GPU 发现 + fallback 输出

在当前 arm64 样本下，建议先做：

- AGX GPU 发现
- GPU 设备元数据输出
- SMC GPU fallback key 输出

不要先假装有稳定 direct GPU temp API。

### 优先级 4：补 Disk 路径

如果要更接近 MFC 全量温度视图，再加。

---

## 当前可直接落地的开发结论

### 已经可以直接照着做的

1. **IOHID**
   - 读取逻辑已确认
   - XML 命名已提取

2. **SMC 指定 key 读取**
   - 当前 Swift 已有基础设施
   - 只缺并入总结果

3. **GPU 设备发现**
   - `AGXFamilyAccelerator`
   - 读 `model` / `gpu-core-count`

### 现在还不能诚实承诺“已经完全确认”的

1. 当前 arm64 样本里的 **direct GPU temperature property**
   - 还没看到可用实现
   - 当前 provider 方法是 stub `return 0.0`

2. SMC 自动发现全部温度 key 的 Swift 版
   - MFC 有
   - 你当前 Swift 还没有

---

## 一句话版结论

> **Max Fan Control 的温度系统是一个多来源 provider 架构，不是单一路径。当前 arm64 样本里，IOHID 已经最清楚，SMC 可以继续实作，GPU 路径目前更像“设备发现 + SMC fallback”，Disk 则是独立的 SMART/NVMe 路径。Swift 下一步最重要的不是继续抠一条路径，而是先把多来源合并结构搭起来。**
