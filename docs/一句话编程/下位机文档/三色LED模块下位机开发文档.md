# 三色LED模块下位机开发文档

| 时间 | 修改内容 |
| ---- | ---- |
| 20260313 | 新建三色LED模块下位机开发文档 |

# 1. 文档目标

本文档用于定义首期 `三色LED模块` 的下位机开发范围、功能要求、协议行为、状态机、测试项和验收标准，作为固件开发、联调和测试的直接依据。

本文档默认继承主文档 [AI一句话编程](../AI一句话编程.md) 中的整体架构、自动编号、心跳机制和 CANFD 协议 v1 约束。

# 2. 模块定位

三色LED模块属于首期优先实现的低风险可视化输出模组，用于：

1. 提供最基础的灯光反馈能力。
2. 支持脚本通过颜色、亮度和闪烁模式表达状态。
3. 作为按键、传感器、告警逻辑的联动输出终端。
4. 作为教学和演示场景中最直观的结果展示模组。

该模块本身风险较低，但它会被高频调用，因此要求写入延迟低、状态可读、参数边界明确。

# 3. 首期实现范围

## 3.1 必须实现

1. 模组上电 `Hello` 自报。
2. 自动编号与重编号。
3. 心跳保活。
4. `Discover` 和 `GetCapabilities`。
5. `write.on`。
6. `write.rgb`。
7. `write.brightness`。
8. `execute.blink`。
9. `read.state`。
10. `read.status`。
11. `configure.default_brightness`。
12. `configure.blink_interval_ms`。
13. `configure.power_on_state`。
14. 本地参数持久化。
15. 两个按钮调整 `preferred_slot`。

## 3.2 首期可选实现

1. `execute.breathe`。
2. 板载动画缓存。
3. 渐变过渡。
4. OTA。

## 3.3 首期不做

1. 复杂脚本动画引擎。
2. 本地多段场景编排。
3. 音乐律动联动。
4. 长时离线动画存储。

# 4. 硬件假设

本文档基于以下硬件假设编写，若后续选型不同，需要同步修正文档和参数范围。

## 4.1 模块组成

1. MCU 一颗。
2. CANFD 收发器一颗。
3. 红、绿、蓝三路 PWM 输出。
4. 三色 LED 一组。
5. `slot_up` / `slot_down` 按钮各一个。
6. 状态 LED 可与主灯复用或单独设计。
7. 非易失存储区，用于保存参数和地址偏好。

## 4.2 电气假设

1. 模块逻辑电压为 `3.3V`。
2. LED 驱动为低功率场景，不考虑大电流恒流方案。
3. PWM 分辨率建议不低于 `8 bit`。
4. 首期默认亮度更新频率不会明显占用 CANFD 总线。

## 4.3 地址与身份

1. 每个模块出厂必须烧录唯一 `module_uid`。
2. 首次上电默认 `assigned_slot = 0xFF`。
3. `preferred_slot` 默认为 `1`，真正生效的地址由主机分配。

# 5. 功能需求

## 5.1 写入功能

模块必须提供以下输出能力：

1. `write.on`
2. `write.rgb`
3. `write.brightness`
4. `execute.blink`

说明：

1. `write.on` 控制灯整体开关。
2. `write.rgb` 写入当前颜色。
3. `write.brightness` 写入全局亮度。
4. `execute.blink` 按当前颜色和间隔执行闪烁。

## 5.2 读取功能

模块必须提供：

1. `read.state`
2. `read.status`

说明：

1. `read.state` 返回当前开关、颜色、亮度和模式。
2. `read.status` 返回当前模块状态位图。

## 5.3 配置功能

模块必须支持以下配置能力：

1. `configure.default_brightness`
2. `configure.blink_interval_ms`
3. `configure.power_on_state`

## 5.4 地址管理功能

模块必须支持：

1. 未分配状态接入。
2. 接收主机下发的 `assigned_slot`。
3. 保存 `preferred_slot`。
4. 按钮调整 `preferred_slot` 并发起改号请求。
5. 心跳中携带当前地址信息和灯状态摘要。

# 6. 模块能力定义

模块类型编码沿用主文档，`rgb_led = 0x02`。

## 6.1 能力表

| 能力 ID | 类型 | 数据类型 | 必须实现 | 说明 |
| ---- | ---- | ---- | ---- | ---- |
| `write.on` | Write | Boolean | 是 | 控制灯整体开关 |
| `write.rgb` | Write | Raw | 是 | 写入 RGB 三通道颜色 |
| `write.brightness` | Write | Int32 | 是 | 写入全局亮度 |
| `execute.blink` | Execute | Int32 | 是 | 执行闪烁次数或周期模式 |
| `read.state` | Read | Raw | 是 | 读取当前灯状态 |
| `read.status` | Read | BitMap | 是 | 读取状态位 |
| `configure.default_brightness` | Configure | Int32 | 是 | 配置默认亮度 |
| `configure.blink_interval_ms` | Configure | Int32 | 是 | 配置闪烁周期 |
| `configure.power_on_state` | Configure | Enum | 是 | 上电默认开关状态 |

## 6.2 推荐子功能码

| 子功能码 | 能力 ID |
| ---- | ---- |
| `0x01` | `write.on` |
| `0x02` | `write.rgb` |
| `0x03` | `write.brightness` |
| `0x04` | `execute.blink` |
| `0x11` | `read.state` |
| `0x12` | `read.status` |
| `0x21` | `configure.default_brightness` |
| `0x22` | `configure.blink_interval_ms` |
| `0x23` | `configure.power_on_state` |

# 7. 数据定义

## 7.1 `write.rgb`

建议采用长度为 `3 Byte` 的 `Raw` 结构：

```text
Byte0 = R
Byte1 = G
Byte2 = B
```

每个通道范围为 `0 ~ 255`。

## 7.2 `read.state`

建议返回长度为 `6 Byte` 的 `Raw` 结构：

```text
Byte0 = on_off
Byte1 = brightness
Byte2 = R
Byte3 = G
Byte4 = B
Byte5 = effect_mode
```

## 7.3 状态位建议

`read.status` 建议返回位图：

| Bit | 含义 |
| ---- | ---- |
| `bit0` | 在线且已分配地址 |
| `bit1` | 当前灯已打开 |
| `bit2` | 当前处于闪烁模式 |
| `bit3` | 最近一次配置写入成功 |
| `bit4` | PWM 输出正常 |
| `bit5` | 地址等待重新分配 |

# 8. 参数范围

## 8.1 默认参数

| 参数 | 默认值 | 说明 |
| ---- | ---- | ---- |
| `default_brightness` | `128` | 默认亮度 |
| `blink_interval_ms` | `500` | 默认闪烁周期 |
| `power_on_state` | `0` | 默认上电关闭 |
| `heartbeat_interval_sec` | `10` | 默认心跳周期 |
| `lease_timeout_sec` | `30` | 默认离线租约 |

## 8.2 允许范围

| 参数 | 最小值 | 最大值 |
| ---- | ---- | ---- |
| `default_brightness` | `0` | `255` |
| `blink_interval_ms` | `100` | `5000` |
| `power_on_state` | `0` | `1` |

# 9. 协议行为

## 9.1 上电流程

模块上电后必须按以下顺序执行：

1. 初始化时钟、PWM、GPIO、CANFD、定时器和存储。
2. 读取本地持久化参数。
3. 若无 `module_uid`，则判定为制造错误，不进入正常运行。
4. 应用 `power_on_state` 和默认亮度。
5. 发送 `Hello`。
6. 等待主机 `Discover`、`GetCapabilities` 和地址配置。

## 9.2 Hello Payload

建议 `Hello` 至少包含：

```yaml
module_uid: 2A-11-9C-00-00-00-21
module_type: rgb_led
preferred_slot: 1
assigned_slot: 255
address_state: unassigned
fw_version: 1.0.0
protocol_version: 1
channel_count: 3
```

## 9.3 Read 响应

### `read.state`

返回：

1. 编码类型 `Raw`
2. 当前灯状态快照

### `read.status`

返回：

1. 编码类型 `BitMap`
2. 当前状态位图

## 9.4 Write 与 Execute

模块收到灯光写入或执行请求时必须：

1. 校验参数长度和范围。
2. 对 RGB、亮度和模式更新做原子切换。
3. 更新当前输出状态。
4. 返回 ACK 或错误码。

## 9.5 Configure 写入

模块收到 `Configure` 时必须：

1. 检查子功能码是否合法。
2. 检查参数类型是否合法。
3. 检查参数值是否越界。
4. 更新运行时配置。
5. 对持久化参数做异步写入。
6. 返回 ACK 或错误码。

# 10. 自动编号与按钮改号

## 10.1 地址模型

1. 同类型模块内 `assigned_slot` 唯一。
2. `0xFF` 表示未分配。
3. 主机是唯一地址分配者。
4. 模块只提出 `preferred_slot`，不能自行宣布地址生效。

## 10.2 按钮行为

### `slot_up`

1. 短按：`preferred_slot + 1`
2. 达到最大值后首期建议停留在最大值

### `slot_down`

1. 短按：`preferred_slot - 1`
2. 到达最小值后停留在 `1`

## 10.3 按钮改号后的动作

1. 更新本地 `preferred_slot`
2. 发送 `Event.SlotChangeRequest`
3. 等待主机下发新的 `assigned_slot`
4. 收到确认后更新本地状态

# 11. 心跳与在线状态

## 11.1 心跳内容

建议心跳至少包含：

```yaml
module_uid: 2A-11-9C-00-00-00-21
module_type: rgb_led
assigned_slot: 1
address_state: assigned
on_off: 1
brightness: 128
effect_mode: blink
status_flags: 0
uptime_sec: 180
```

## 11.2 心跳规则

1. 默认每 `10 秒` 发送一次。
2. 若主机要求，也可配置为 `30 秒` 一次。
3. 心跳发送失败时可记录错误计数，但不允许自行改地址。

# 12. 灯效执行设计

## 12.1 输出刷新原则

1. 写入新颜色时应立即更新 PWM 占空比。
2. 更新亮度时应等比例作用于三通道输出。
3. 开关动作优先级高于闪烁任务。

## 12.2 闪烁模式

1. `execute.blink` 触发后进入闪烁状态。
2. 闪烁周期使用 `blink_interval_ms`。
3. 闪烁结束后恢复到执行前的常亮状态或关闭状态。

## 12.3 上电策略

1. 首期建议默认上电关闭。
2. 若 `power_on_state = 1`，则使用默认亮度和默认颜色点亮。

# 13. 状态与保护设计

## 13.1 参数保护

1. 亮度不得超过 `255`。
2. 闪烁周期不得低于 `100 ms`，避免过高刷新频率。

## 13.2 运行保护

1. 灯效执行过程中收到新的写入命令，应允许覆盖当前效果。
2. 不允许异常循环导致 CPU 被动画逻辑长时间占满。

# 14. 固件状态机

建议固件至少包含以下状态：

1. `BOOT`
2. `UNASSIGNED`
3. `ASSIGN_PENDING`
4. `ASSIGNED_IDLE`
5. `BLINKING`
6. `FAULT`
7. `OTA`

## 14.1 状态说明

### `BOOT`

初始化硬件、读取参数、准备上报。

### `UNASSIGNED`

尚未获得主机分配的逻辑号。

### `ASSIGN_PENDING`

已经收到地址分配，等待确认写入和切换。

### `ASSIGNED_IDLE`

已分配地址，等待写入或执行请求。

### `BLINKING`

当前处于闪烁效果执行中。

### `FAULT`

存在严重错误，例如 PWM 初始化失败、存储损坏或参数非法。

# 15. 本地持久化内容

模块建议持久化以下参数：

1. `module_uid`
2. `preferred_slot`
3. 上次 `assigned_slot`
4. `default_brightness`
5. `blink_interval_ms`
6. `power_on_state`

说明：

1. 当前实时颜色可不强制持久化。
2. 配置写入 Flash 时要做磨损控制。

# 16. 错误处理

## 16.1 推荐内部错误码

| 错误码 | 含义 |
| ---- | ---- |
| `0x01` | PWM 初始化失败 |
| `0x02` | 颜色参数非法 |
| `0x03` | 亮度参数越界 |
| `0x04` | Flash 写入失败 |
| `0x05` | 地址未分配 |

## 16.2 异常处理原则

1. 参数非法时拒绝写入。
2. 关键初始化失败时进入 `FAULT`。
3. 效果执行失败时允许保留最近一次安全输出。
4. 不允许因为单次写入失败而反复重启整机。

# 17. 开发拆分建议

建议下位机固件按以下模块拆分：

1. `bsp_pwm`
2. `bsp_canfd`
3. `storage_nv`
4. `rgb_output_service`
5. `effect_service`
6. `address_manager`
7. `protocol_handler`
8. `heartbeat_service`

## 17.1 关键任务

1. `can_rx_task`
2. `can_tx_task`
3. `effect_task`
4. `heartbeat_task`
5. `nv_commit_task`

# 18. 测试项

## 18.1 功能测试

1. 上电后是否能正确发送 `Hello`
2. 主机分号后是否能进入 `Assigned`
3. `write.on` 是否生效
4. `write.rgb` 是否能正确输出颜色
5. `write.brightness` 是否能正确调整亮度
6. 掉电重启后配置是否保留

## 18.2 灯效测试

1. `execute.blink` 是否能按周期闪烁
2. 闪烁过程中新的写入命令是否能覆盖旧效果
3. 低亮度和高亮度边界是否都能正确显示

## 18.3 地址与心跳测试

1. 首次插入是否自动分号
2. 同类型两个模块同时插入是否能正确区分
3. 按钮改号后是否能正确触发重分发
4. 心跳是否按设定周期发送
5. 心跳超时后主机是否能判定离线

## 18.4 异常测试

1. 颜色参数非法时是否拒绝生效
2. PWM 异常时状态位是否正确
3. Flash 写入失败时是否能返回错误

# 19. 验收标准

满足以下条件即可认为首期三色LED模块下位机开发完成：

1. 能完成 `Hello -> Discover -> GetCapabilities -> AssignSlot -> Heartbeat` 全流程。
2. 能稳定执行 `write.on`、`write.rgb`、`write.brightness` 和 `execute.blink`。
3. 能正确返回当前灯状态。
4. 能正确保存和加载默认亮度与闪烁参数。
5. 连续运行 `24 小时` 无异常死机或协议失联。

# 20. 后续可扩展项

后续可以在不破坏首期协议兼容性的前提下扩展：

1. 呼吸灯效果。
2. 渐变和过渡动画。
3. 多灯串联版本。
4. OTA。
