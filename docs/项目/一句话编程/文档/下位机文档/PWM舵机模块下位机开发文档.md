# PWM舵机模块下位机开发文档

| 时间 | 修改内容 |
| ---- | ---- |
| 20260313 | 新建 PWM 舵机模块下位机开发文档 |

# 1. 文档目标

本文档用于定义首期 `PWM舵机模块` 的下位机开发范围、功能要求、协议行为、状态机、测试项和验收标准，作为固件开发、联调和测试的直接依据。

本文档默认继承主文档 [AI一句话编程](../AI一句话编程.md) 中的整体架构、自动编号、心跳机制和 CANFD 协议 v1 约束。

# 2. 模块定位

PWM舵机模块属于首期优先实现的简单执行模组，用于：

1. 接收角度指令并驱动标准 PWM 舵机转动。
2. 为演示、教学和轻载联动场景提供最基础的机械动作输出。
3. 支持脚本通过 `send_cmd("pwm_servo", slot, "write.angle", angle)` 进行控制。
4. 作为后续高风险执行器接入前的中等风险执行模组练手对象。

该模块比纯传感器和纯灯光模组风险更高，因此首期必须加强角度边界、频率限制和上电默认行为约束。

# 3. 首期实现范围

## 3.1 必须实现

1. 模组上电 `Hello` 自报。
2. 自动编号与重编号。
3. 心跳保活。
4. `Discover` 和 `GetCapabilities`。
5. `write.angle`。
6. `read.angle`。
7. `read.status`。
8. `configure.min_angle`。
9. `configure.max_angle`。
10. `configure.home_angle`。
11. `configure.min_interval_ms`。
12. `execute.home`。
13. `execute.stop`。
14. 本地参数持久化。
15. 两个按钮调整 `preferred_slot`。

## 3.2 首期可选实现

1. `configure.move_speed_dps`。
2. `subscribe.reached`。
3. 本地校准模式。
4. OTA。

## 3.3 首期不做

1. 多舵机同步控制。
2. 复杂轨迹插补。
3. 力矩闭环控制。
4. 高负载机械臂级联。

# 4. 硬件假设

本文档基于以下硬件假设编写，若后续选型不同，需要同步修正文档和参数范围。

## 4.1 模块组成

1. MCU 一颗。
2. CANFD 收发器一颗。
3. PWM 输出一路。
4. 舵机供电接口一组。
5. `slot_up` / `slot_down` 按钮各一个。
6. 状态 LED 一颗。
7. 非易失存储区，用于保存参数和地址偏好。

## 4.2 电气假设

1. 模块逻辑电压为 `3.3V`。
2. PWM 控制周期默认为 `20 ms`。
3. 脉宽范围默认为 `500 us ~ 2500 us`。
4. 首期默认不带位置反馈传感器。

## 4.3 地址与身份

1. 每个模块出厂必须烧录唯一 `module_uid`。
2. 首次上电默认 `assigned_slot = 0xFF`。
3. `preferred_slot` 默认为 `1`，真正生效的地址由主机分配。

# 5. 功能需求

## 5.1 控制功能

模块必须提供以下控制能力：

1. `write.angle`
2. `execute.home`
3. `execute.stop`

说明：

1. `write.angle` 接收目标角度并执行动作。
2. `execute.home` 将舵机移动到预设归中角度。
3. `execute.stop` 停止当前动作并保持最近安全输出。

## 5.2 读取功能

模块必须提供：

1. `read.angle`
2. `read.status`

说明：

1. `read.angle` 返回当前目标角度或最近一次已应用角度。
2. `read.status` 返回当前模块状态位图。

## 5.3 配置功能

模块必须支持以下配置能力：

1. `configure.min_angle`
2. `configure.max_angle`
3. `configure.home_angle`
4. `configure.min_interval_ms`

## 5.4 地址管理功能

模块必须支持：

1. 未分配状态接入。
2. 接收主机下发的 `assigned_slot`。
3. 保存 `preferred_slot`。
4. 按钮调整 `preferred_slot` 并发起改号请求。
5. 心跳中携带当前地址信息和动作摘要。

# 6. 模块能力定义

模块类型编码沿用主文档，`pwm_servo = 0x0A`。

## 6.1 能力表

| 能力 ID | 类型 | 数据类型 | 必须实现 | 说明 |
| ---- | ---- | ---- | ---- | ---- |
| `write.angle` | Write | Int32 | 是 | 写入目标角度 |
| `read.angle` | Read | Int32 | 是 | 读取当前目标角度 |
| `read.status` | Read | BitMap | 是 | 读取状态位 |
| `configure.min_angle` | Configure | Int32 | 是 | 配置最小角度 |
| `configure.max_angle` | Configure | Int32 | 是 | 配置最大角度 |
| `configure.home_angle` | Configure | Int32 | 是 | 配置归中角度 |
| `configure.min_interval_ms` | Configure | Int32 | 是 | 配置最小动作间隔 |
| `execute.home` | Execute | Int32 | 是 | 执行归中动作 |
| `execute.stop` | Execute | Int32 | 是 | 停止当前动作 |

## 6.2 推荐子功能码

| 子功能码 | 能力 ID |
| ---- | ---- |
| `0x01` | `write.angle` |
| `0x02` | `read.angle` |
| `0x03` | `read.status` |
| `0x11` | `configure.min_angle` |
| `0x12` | `configure.max_angle` |
| `0x13` | `configure.home_angle` |
| `0x14` | `configure.min_interval_ms` |
| `0x21` | `execute.home` |
| `0x22` | `execute.stop` |

# 7. 数据定义

## 7.1 角度定义

1. `write.angle` 和 `read.angle` 使用 `Int32`。
2. 单位统一为角度 `deg`。
3. 首期建议逻辑范围为 `0 ~ 180`。

## 7.2 状态位建议

`read.status` 建议返回位图：

| Bit | 含义 |
| ---- | ---- |
| `bit0` | 在线且已分配地址 |
| `bit1` | PWM 输出正常 |
| `bit2` | 当前处于移动中 |
| `bit3` | 当前位于 `home_angle` |
| `bit4` | 最近一次配置写入成功 |
| `bit5` | 动作被频率限制拒绝 |
| `bit6` | 地址等待重新分配 |

## 7.3 角度到脉宽映射

首期建议使用线性映射：

```text
pulse_us = min_pulse_us + angle * (max_pulse_us - min_pulse_us) / (max_angle - min_angle)
```

要求：

1. 在进入计算前先做角度裁剪。
2. 若 `max_angle <= min_angle`，则判定配置非法。

# 8. 参数范围

## 8.1 默认参数

| 参数 | 默认值 | 说明 |
| ---- | ---- | ---- |
| `min_angle` | `0` | 默认最小角度 |
| `max_angle` | `180` | 默认最大角度 |
| `home_angle` | `90` | 默认归中角度 |
| `min_interval_ms` | `200` | 默认最小动作间隔 |
| `heartbeat_interval_sec` | `10` | 默认心跳周期 |
| `lease_timeout_sec` | `30` | 默认离线租约 |

## 8.2 允许范围

| 参数 | 最小值 | 最大值 |
| ---- | ---- | ---- |
| `min_angle` | `0` | `180` |
| `max_angle` | `0` | `180` |
| `home_angle` | `0` | `180` |
| `min_interval_ms` | `100` | `5000` |

# 9. 协议行为

## 9.1 上电流程

模块上电后必须按以下顺序执行：

1. 初始化时钟、PWM、GPIO、CANFD、定时器和存储。
2. 读取本地持久化参数。
3. 若无 `module_uid`，则判定为制造错误，不进入正常运行。
4. 默认不上电主动转动舵机。
5. 发送 `Hello`。
6. 等待主机 `Discover`、`GetCapabilities` 和地址配置。

## 9.2 Hello Payload

建议 `Hello` 至少包含：

```yaml
module_uid: 2A-11-9C-00-00-00-41
module_type: pwm_servo
preferred_slot: 1
assigned_slot: 255
address_state: unassigned
fw_version: 1.0.0
protocol_version: 1
angle_range: [0, 180]
```

## 9.3 Read 响应

### `read.angle`

返回：

1. 编码类型 `Int32`
2. 当前目标角度

### `read.status`

返回：

1. 编码类型 `BitMap`
2. 当前状态位图

## 9.4 Write 与 Execute

模块收到角度写入或执行请求时必须：

1. 检查地址是否已分配。
2. 检查目标角度是否在允许范围内。
3. 检查距离上次动作是否满足 `min_interval_ms`。
4. 对角度做裁剪或拒绝执行。
5. 输出对应 PWM。
6. 更新当前状态并返回 ACK 或错误码。

## 9.5 Configure 写入

模块收到 `Configure` 时必须：

1. 检查子功能码是否合法。
2. 检查参数类型是否合法。
3. 检查最小角度、最大角度和归中角度逻辑是否合理。
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
module_uid: 2A-11-9C-00-00-00-41
module_type: pwm_servo
assigned_slot: 1
address_state: assigned
latest_angle: 90
moving: 0
status_flags: 0
uptime_sec: 180
```

## 11.2 心跳规则

1. 默认每 `10 秒` 发送一次。
2. 若主机要求，也可配置为 `30 秒` 一次。
3. 心跳发送失败时可记录错误计数，但不允许自行改地址。

# 12. 驱动控制策略

## 12.1 上电默认策略

1. 首期建议上电后不立即运动。
2. 仅在收到显式控制命令或 `execute.home` 后才开始动作。

## 12.2 动作间隔限制

1. 两次有效角度写入之间至少满足 `min_interval_ms`。
2. 未满足间隔时应拒绝执行并返回错误码或状态位标记。

## 12.3 归中策略

1. `execute.home` 使用 `home_angle`。
2. 若 `home_angle` 超出 `min_angle ~ max_angle`，则视为配置非法。

# 13. 安全限制设计

## 13.1 角度边界

1. 不允许输出超出配置边界的角度。
2. 推荐在主机和模组两侧都做边界检查。

## 13.2 执行频率

1. 不允许高频连续改写导致舵机抖动。
2. 若脚本调用过于频繁，模组侧仍应拒绝超限动作。

## 13.3 断电与故障

1. 出现 PWM 初始化失败或关键配置非法时进入 `FAULT`。
2. 故障时保留心跳能力，便于主机定位问题。

# 14. 固件状态机

建议固件至少包含以下状态：

1. `BOOT`
2. `UNASSIGNED`
3. `ASSIGN_PENDING`
4. `ASSIGNED_IDLE`
5. `MOVING`
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

已分配地址，等待控制指令。

### `MOVING`

当前处于动作执行中。

### `FAULT`

存在严重错误，例如 PWM 初始化失败、参数非法或存储损坏。

# 15. 本地持久化内容

模块建议持久化以下参数：

1. `module_uid`
2. `preferred_slot`
3. 上次 `assigned_slot`
4. `min_angle`
5. `max_angle`
6. `home_angle`
7. `min_interval_ms`

说明：

1. 当前角度不强制掉电保存。
2. 配置写入 Flash 时要做磨损控制。

# 16. 错误处理

## 16.1 推荐内部错误码

| 错误码 | 含义 |
| ---- | ---- |
| `0x01` | PWM 初始化失败 |
| `0x02` | 角度参数非法 |
| `0x03` | 配置上下限非法 |
| `0x04` | 动作频率超限 |
| `0x05` | Flash 写入失败 |
| `0x06` | 地址未分配 |

## 16.2 异常处理原则

1. 参数非法时拒绝写入。
2. 关键初始化失败时进入 `FAULT`。
3. 频率超限时拒绝当前动作，但不重启整机。
4. 故障时允许继续发送心跳，便于主机定位问题。

# 17. 开发拆分建议

建议下位机固件按以下模块拆分：

1. `bsp_pwm`
2. `bsp_canfd`
3. `storage_nv`
4. `servo_control_service`
5. `address_manager`
6. `protocol_handler`
7. `heartbeat_service`
8. `safety_guard_service`

## 17.1 关键任务

1. `can_rx_task`
2. `can_tx_task`
3. `servo_control_task`
4. `heartbeat_task`
5. `nv_commit_task`

# 18. 测试项

## 18.1 功能测试

1. 上电后是否能正确发送 `Hello`
2. 主机分号后是否能进入 `Assigned`
3. `write.angle` 是否能正确输出角度
4. `execute.home` 是否能回到归中角度
5. `execute.stop` 是否能停止当前动作
6. 掉电重启后配置是否保留

## 18.2 保护测试

1. 超出角度范围时是否拒绝执行
2. 连续高频写入时是否触发频率限制
3. `min_angle >= max_angle` 时是否拒绝配置
4. `home_angle` 越界时是否拒绝生效

## 18.3 地址与心跳测试

1. 首次插入是否自动分号
2. 同类型两个模块同时插入是否能正确区分
3. 按钮改号后是否能正确触发重分发
4. 心跳是否按设定周期发送
5. 心跳超时后主机是否能判定离线

## 18.4 异常测试

1. PWM 异常时状态位是否正确
2. Flash 写入失败时是否能返回错误
3. 动作被拒绝时是否不影响后续合法控制

# 19. 验收标准

满足以下条件即可认为首期 PWM 舵机模块下位机开发完成：

1. 能完成 `Hello -> Discover -> GetCapabilities -> AssignSlot -> Heartbeat` 全流程。
2. 能稳定执行 `write.angle`、`execute.home` 和 `execute.stop`。
3. 能正确保存和加载角度边界及动作间隔参数。
4. 能在超限控制时拒绝危险动作。
5. 连续运行 `24 小时` 无异常死机或协议失联。

# 20. 后续可扩展项

后续可以在不破坏首期协议兼容性的前提下扩展：

1. 速度控制。
2. 到位事件。
3. 本地校准向导。
4. OTA。
