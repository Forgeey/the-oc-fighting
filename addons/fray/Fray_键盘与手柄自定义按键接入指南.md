# Fray 键盘与手柄自定义按键接入指南

> 核对日期：2026-10-17。依据 Git 根目录 `addons/fray/` 的 `2.0.0-alpha` 源码；配合 `Fray_2D传统横版格斗游戏使用说明.md` 第 7 节使用。
>
> 本文是设置功能的接入设计和代码片段，不表示已实现设置场景或修改插件。`res://` 指目标 Godot 工程，游戏脚本应放在插件之外。示例已做静态核对，尚未在 Godot 中运行验收。

## 1. 结论：改 Godot 的事件绑定，保留 Fray 的逻辑名称

**推荐沿用主指南的 Godot InputMap → FrayInputMap action 桥接方案。** 项目设置保存出厂默认键位；运行时的设置菜单修改 InputMap；用户配置自行保存到 `user://`。Fray 负责读取、组合输入和指令识别，不自带完整的改键菜单、设备认领或配置存储系统。

```text
玩家设置档案：P1 / P2 的键盘键位、手柄键位、死区
                  + 本次运行的设备分配表：P1 → 某个手柄 device ID
    ↓ 游戏层编译配置
Godot InputMap：p1_left / p1_punch / p2_left / p2_punch ...
    ↓ FrayInputMap.add_bind_action(action, action)，启动时注册一次
FrayInput → FrayController / FraySequenceMatcher
    ↓ 每名玩家独立过滤、归一化
left / right / punch 等游戏语义 → FrayBufferedInputAdvancer / 状态机
```

例如 P1 将轻拳由 J 改为 K，改变的是 `p1_punch` 所关联的键盘事件；`p1_punch`、状态机中的 `punch`、连招定义及角色脚本不用重命名。键盘、手柄按键和摇杆方向都可以对应同一逻辑 action，多个事件表示“任一满足即可”，不是必须同时按。

### 三层名称与设备不要混为一谈

| 概念 | 示例 | 谁负责 |
| --- | --- | --- |
| 物理输入 | 键盘 K、手柄 A 键、左摇杆 X 轴负向 | Godot 原始 InputEvent |
| 玩家逻辑 action | `p1_punch`、`p2_punch` | 玩家设置档案 + Godot InputMap |
| 游戏语义 | `punch`、相对朝向的 forward、招式指令 | 游戏输入适配层 + Fray |
| 实际手柄 ID | 本次运行中 `event.device` | Godot 连接／设备认领流程 |
| Fray 轮询设备号 | `FrayController.device`、`FrayInputEvent.device` | Fray 输入状态实例，见第 3 节 |

主指南 7.1 的“项目设置中改键”是**开发者默认配置**；这里补充的是玩家在成品游戏中运行时改键。设置数据不应回写发布后的 `project.godot`，也不应覆盖 `ui_accept` 等全局 UI action 来实现角色改键。[R1、R5]

## 2. 当前 Fray 接口能做什么

| 接口／类型 | 当前源码行为 | 对设置功能的意义 |
| --- | --- | --- |
| `FrayInputMap.add_bind_action(name, action)` | 包装 Godot action，按名称查询 | 推荐桥接入口；改 InputMap 后无需重建此绑定 |
| `FrayInputMap.add_bind_key(name, key)` | `Input.is_key_pressed(key)`，忽略 device | 是逻辑键，不是 physical_keycode；不能靠切 device 分开两套键盘 |
| `add_bind_joy_button(name, button)` | 按查询时的 device 读取按钮 | 可用于纯手柄的设备感知路线 |
| `add_bind_joy_axis(name, axis, positive, deadzone)` | 按 device、轴号、正负方向和死区检测 | 左右／上下要分别配置，不是一个轴自动代表两个 action |
| `add_bind_fray_action(name, simple_binds)` | 多个简单绑定取逻辑“或” | 并非按玩家档案分别维护的一张表；混入键盘绑定仍会跨 device 生效 |
| `get_bind(name)`／`remove_input(name)` | 获取资源／删除映射 | 不负责设置 UI、存盘或清空所有历史输入状态 |
| `FrayController.disabled` | 禁止通过该 Controller 的查询 | 不会停止全局 FrayInput，也不会阻止自建事件监听器收集输入 |

`FrayInputMap` 是全局映射，不是每个 Controller 各有一份。不要给 P1 和 P2 分别调用 `add_bind_action("punch", ...)`，后者不会覆盖前者，而是报重名。用 `p1_punch`／`p2_punch`，或另行实现完整的每玩家输入适配层。

**本指南不混用两条路线。** 下面的改键只改 Godot InputMap，不再给同名输入重复调用 `add_bind_key()`、`add_bind_joy_button()`，也不在每次改键时 `remove_input()` 再注册。删除绑定不会自动清除 FrayDeviceState 中的历史状态及复合输入引用。

## 3. 双人键盘、双手柄与热插拔

### 3.1 玩家隔离放在 action 与事件上

- **双人同键盘：**P1 使用 `p1_*`，P2 使用 `p2_*`，设置不同键位；若允许相同键，两个角色会同时响应。标准键盘事件不能在这里可靠区分两把独立 USB 键盘，不要将它们当成两只手柄分配。
- **键盘 + 手柄：**给键盘玩家编译键盘事件，给手柄玩家编译指定 device 的手柄事件。是否允许一名玩家同时使用两类设备，应作为明确的设备模式，不要默认把键盘绑定复制到双方。
- **双手柄：**通过 `Input.get_connected_joypads()` 获取实际设备列表，按“按键加入／选择设备”分配给 P1、P2；所有属于 P1 的 InputEventJoypadButton／InputEventJoypadMotion 都指定 P1 的实际 device，P2 同理。
- **禁止用 device = -1 作为未连接玩家的占位。** Godot InputMap 中 -1 表示匹配所有设备。未分配手柄时，不给该玩家添加任何手柄事件；保留其键位档案以便重连后恢复。[R1、R2、R6]

P1、P2 是玩家槽位，不是手柄 ID；设备 ID 不一定是 0、1，也不能作为跨运行的持久身份。保存按钮／轴配置与可选的设备偏好，实际 ID 每次由连接与认领流程确定。GUID 可作型号匹配提示，但同型号手柄可能相同，不能据此唯一认领某一只。[R6]

### 3.2 Fray action 绑定的设备参数不是原始设备来源

当前 `FrayInputBindAction._is_pressed_impl(_device)` 调用 `Input.is_action_pressed(action)`，**忽略传入的 Fray device**。即使有两个 Fray 设备状态，它们也可能分别发出同一个 `p1_punch` 的事件。实际隔离来自 action 的玩家前缀以及手柄事件中的具体 device，而非 FrayInputEvent.device。

因此每个角色的 Fray 事件适配层都必须同时检查：

1. 设置／暂停期间是否允许接收战斗输入。
2. `event.device` 是否等于选定的**一个** Fray 轮询通道，避免相同 action 从多个通道重复投递。
3. `event.input` 是否属于该玩家的逻辑输入白名单；不能只按 device 分发给角色。

主指南 7.2 的 `event.input == punch_input` 已经做了单个攻击输入过滤；扩展方向、踢、防御时，使用明确的玩家输入名到语义名映射。序列匹配器也要先经过这个过滤，不要把全局所有事件喂给双方。

### 3.3 当前版本的设备枚举缺口与接入办法

源码的 `get_connected_devices()` 注释说“总有 0”，但实现实际上只在**没有手柄**时补 0；若只连接 ID 1 的手柄，就只轮询 1。`is_device_connected(0)` 仍可能返回 true，并不代表 0 仍在每帧更新。写死 `Controller.device = 0` 可能造成键盘或 action 状态停止刷新。

在不修改插件的 action 桥接方案下，可以由输入服务统一选择一个当前正在被轮询且已注册的通道：

```gdscript
# 游戏层辅助函数；-1 在这里仅表示“没有可用的 Fray 通道”，不能拿去创建手柄事件。
func choose_action_poll_device() -> int:
    for device in FrayInput.get_connected_devices():
        if FrayInput.is_device_connected(device):
            return device
    return -1
```

启动注册输入后、创建角色前选择一次；收到 Godot `Input.joy_connection_changed` 后，先关闭战斗输入入口，再延迟到 Fray 连接回调已完成的安全阶段重新选择。选不到就保持暂停，不要让角色查询无效通道。

- 所有采用 action 桥接的 Controller 可以使用同一通道；双方仍通过 `p1_*`／`p2_*` 隔离。不要用此通道来决定给哪个玩家分配物理手柄。
- 同步更新相关 Controller、事件过滤器及可选 FrayInputBuffer 的 device，并按第 7 节清理旧输入；不能只改 Controller 而漏掉其他消费者。
- 这只是**action 桥接**的兼容办法，不适用于直接 `add_bind_joy_button()`／`add_bind_joy_axis()` 的设备感知路线。
- 正式项目也可以另行修正插件枚举逻辑，让键盘通道 0 始终被更新，再固定使用 0；本文没有实施这个修复。不能只根据原注释认为问题已经不存在。

设备 0 的连接变化被 Fray 的连接回调特殊处理，因此设备认领／断线提示应监听 **Godot 的 `Input.joy_connection_changed`**，不能只监听 Fray 的连接信号。断线时移除该玩家 action 的手柄事件、暂停该玩家输入并提示重连；禁止自动抢走另一玩家的手柄。

## 4. 设置页面的数据与交互

推荐在插件外组织：

```text
res://settings/input/
├── input_settings.gd       # 默认值、工作副本、校验、应用、保存
├── input_device_router.gd # P1/P2 设备认领、热插拔、Fray 通道选择
└── rebind_dialog.gd        # 原始事件捕获与确认弹窗
```

以上是建议创建的游戏脚本，不是 Fray 已有文件或类。设置页每个玩家分别显示：设备模式、手柄认领、动作名、键盘主／副键、手柄主／副绑定、摇杆死区，以及“应用／取消／恢复默认”。

### 4.1 用可持久化描述保存绑定，不保存运行时设备号

建议一个档案维护每个语义动作的多槽位数组，键盘、手柄同时保存在数据中，设备模式决定实际编译哪些事件：

```gdscript
# 游戏自定义数据结构示例，非插件资源类型。
var p1_profile: Dictionary = {
    "device_mode": "keyboard_and_pad",  # 也可以是 keyboard / pad
    "actions": {
        "punch": {
            "deadzone": 0.5,
            "keyboard": [{"kind": "key_physical", "code": KEY_J}],
            "pad": [{"kind": "joy_button", "button": JOY_BUTTON_A}],
        },
        "left": {
            "deadzone": 0.5,
            "keyboard": [{"kind": "key_physical", "code": KEY_A}],
            "pad": [
                {"kind": "joy_button", "button": JOY_BUTTON_DPAD_LEFT},
                {"kind": "joy_axis", "axis": JOY_AXIS_LEFT_X, "sign": -1},
            ],
        },
    },
}
```

实际档案必须包含游戏要求的所有 action；这个片段只展示两项。也可支持 `key_logical`；不要把 keycode 与 physical_keycode 当成同一种编码混用。游戏移动常使用物理键位；文字快捷键是否采用逻辑键由产品决定。UI 需明确显示所采用的模式。[R3]

冲突比较以规范化描述为准：键盘比较键种类和码值（跨物理／逻辑模式也需提示可能冲突）；手柄按钮比较按钮号；轴比较轴号与正负号，不能把同轴的左和右误判为冲突。同一手柄归属不可重复；两名玩家各自手柄上的 A 键则不构成冲突。

允许“交换／替换／取消”等明确操作；不要静默解绑其他动作。某动作移除最后一个绑定、双方共用键盘键、同侧方向绑定到攻击键等情况都要提示。SOCD（左右／上下同时输入）的中立或优先规则由游戏层统一处理，不由改键菜单或 Fray 自动决定。

### 4.2 捕获原始事件，不捕获改键后的 action

弹窗打开后先进入“等待全部相关键释放、摇杆回中”阶段，再开始监听 `_input(event)`。忽略打开弹窗的那次点击／按键；监听原始 `InputEventKey`、`InputEventJoypadButton`、`InputEventJoypadMotion`，不能用 `is_action_pressed("p1_punch")` 推断用户刚按了哪一个物理键。[R3、R4]

下面是候选转换的核心片段。调用前由弹窗检查 `capture_armed`、当前玩家、当前绑定槽类别及手柄认领；返回空字典表示忽略。它不负责冲突确认和保存：

```gdscript
func describe_candidate(event: InputEvent, slot: String, pad_id: int) -> Dictionary:
    if slot == "keyboard" and event is InputEventKey:
        if not event.pressed or event.echo:
            return {}
        # 本例只允许单个非修饰键；不支持 Shift+J 等组合快捷键。
        if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
            return {}
        if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_ESCAPE]:
            return {}  # Escape 留给取消；产品也可选择独立的取消按钮。
        if event.physical_keycode == 0:
            return {}
        return {"kind": "key_physical", "code": event.physical_keycode}

    if slot == "pad" and pad_id >= 0 and event.device == pad_id:
        if event is InputEventJoypadButton and event.pressed:
            return {"kind": "joy_button", "button": event.button_index}
        if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.7:
            return {
                "kind": "joy_axis", "axis": event.axis,
                "sign": 1 if event.axis_value > 0.0 else -1,
            }
    return {}
```

- 只捕获被认领的那只手柄；按钮按下才接受，释放不产生绑定。
- 摇杆和模拟扳机都可能表现为轴事件。十字键通常是按钮事件；以 Godot 标准化后的事件为准，不写死某一品牌的原始编号。
- `0.7` 是示例**捕获阈值**，不等于战斗 action 的 `deadzone`。开始监听前可要求允许捕获的轴回到中立区（例如绝对值小于 0.2）；特殊设备需要校准静止值和允许轴清单，避免漂移抢占绑定。
- 捕获一个候选后立刻停止监听，进入冲突／确认状态，等待按钮释放才允许确认或返回；否则同一次按键会同时完成绑定和触发菜单。
- 用 `get_viewport().set_input_as_handled()` 阻止事件继续传给后续 UI，但它不等于停止 Godot Input 的全局状态更新，更不等于停止 Fray 轮询。战斗输入隔离必须按第 7 节单独做。[R6]
- 保留不会被玩家改没的取消／恢复默认入口，例如独立 UI 按钮与固定 Escape；控制器上的返回键是否可绑定应有明确规则。

## 5. 将工作配置应用到 InputMap 并接入 Fray

### 5.1 描述转换为 Godot 事件

以下函数放在游戏层输入设置服务中。**只接收已经校验的描述**：kind 白名单、键／按钮／轴码范围、轴 sign 只能为 -1 或 1，且 pad_id 来自当前实际设备认领表。`null` 也用于“当前没有手柄”，不能把它转换成全设备匹配。

```gdscript
func binding_to_event(binding: Dictionary, pad_id: int) -> InputEvent:
    match String(binding["kind"]):
        "key_physical", "key_logical":
            var key_event := InputEventKey.new()
            if binding["kind"] == "key_physical":
                key_event.physical_keycode = int(binding["code"])
            else:
                key_event.keycode = int(binding["code"])
            return key_event
        "joy_button":
            if pad_id < 0:
                return null
            var button_event := InputEventJoypadButton.new()
            button_event.device = pad_id
            button_event.button_index = int(binding["button"])
            return button_event
        "joy_axis":
            if pad_id < 0:
                return null
            var axis_event := InputEventJoypadMotion.new()
            axis_event.device = pad_id
            axis_event.axis = int(binding["axis"])
            axis_event.axis_value = float(binding["sign"])
            return axis_event
    return null
```

InputMap 保存的是**事件模板**，不要把当前按下状态、echo、输入时间戳或设备对象写进用户档案。手柄事件编译时填入实际 ID；键盘事件不拿这个 ID 做玩家隔离。[R1、R3、R4]

### 5.2 以整个 action 为单位重建，保留其他绑定槽

界面修改的是工作档案中的一个槽位；应用时从该 action 的完整配置重建事件数组。不要只执行“清空 action → 加一个新键”，否则会顺带删掉手柄或副键。

```gdscript
# 前置条件：action 来自程序定义的玩家 action 白名单；config 已完整校验；
# 战斗输入已关闭，所有相关旧／新绑定处于释放状态。
# 本函数和 binding_to_event() 放在同一个游戏层脚本。
func apply_action(action: StringName, config: Dictionary,
        keyboard_enabled: bool, pad_id: int) -> void:
    var events: Array[InputEvent] = []
    if keyboard_enabled:
        for binding in config["keyboard"]:
            var event := binding_to_event(binding, -1)
            if event != null:
                events.append(event)
    if pad_id >= 0:
        for binding in config["pad"]:
            var event := binding_to_event(binding, pad_id)
            if event != null:
                events.append(event)

    if not InputMap.has_action(action):
        InputMap.add_action(action)
    InputMap.action_erase_events(action)
    InputMap.action_set_deadzone(action, float(config["deadzone"]))
    for event in events:
        InputMap.action_add_event(action, event)
```

例如先在工作档案中用 K 替换 `punch.keyboard[0]`，验证后调用：

```gdscript
# assigned_pad_id：设备路由服务提供的当前实际 ID；-1 表示不编译手柄绑定。
p1_profile["actions"]["punch"]["keyboard"][0] = {
    "kind": "key_physical", "code": KEY_K,
}
apply_action(&"p1_punch", p1_profile["actions"]["punch"], true, assigned_pad_id)
```

设备模式为 keyboard 时传 `pad_id = -1`，为 pad 时传 `keyboard_enabled = false`，混合模式才启用两者。手柄断线时配置数组不删除，只用 -1 重新编译；重连认领成功后用新的实际 ID 重新编译。动作的死区用 `InputMap.action_set_deadzone()` 设置，范围应做产品限制，例如 `0.05～0.95`，而不是允许摇杆静止时就持续触发。[R1]

### 5.3 桥接只在启动注册，设置页面不重注册

```gdscript
func register_action_bridge(actions: Array[StringName]) -> void:
    for action in actions:
        assert(InputMap.has_action(action))
        if not FrayInputMap.has_input(action):
            FrayInputMap.add_bind_action(action, action)
        else:
            var existing := FrayInputMap.get_bind(action) as FrayInputBindAction
            assert(existing != null and existing.action == action,
                "同名 Fray 输入已用于其他绑定或复合输入，请修正初始化配置")
```

应用默认值／用户配置 → 注册桥接 → 选择 Fray 轮询通道 → 创建并初始化角色。`assert` 用于开发期发现错误；发布版本还应显式处理失败，不要靠断言进行用户档案校验。

后续按键改变时保持桥接、复合输入名称和指令名称不变，下一轮 Fray 物理采样会读取新 action 状态。**改变绑定不是一次新的输入事件，更不会自动清掉此前积累的蓄力或连招记录。** 遵守第 7 节的恢复边界。

## 6. 保存、加载、取消与恢复默认

### 6.1 保存用户档案而非运行时 InputMap

推荐用 `ConfigFile` 保存描述字典到 `user://input_bindings.cfg`，带格式版本号；也可用 JSON，但需统一处理数值类型。不要保存当前手柄 ID，也不要在启动时信任文件中的任意 action 名称。[R5]

```gdscript
const INPUT_SETTINGS_PATH := "user://input_bindings.cfg"
const INPUT_SETTINGS_VERSION := 1

# profiles 只包含可持久化描述，调用前已经校验。
func save_profiles(profiles: Dictionary) -> Error:
    var file := ConfigFile.new()
    file.set_value("meta", "version", INPUT_SETTINGS_VERSION)
    file.set_value("players", "profiles", profiles)
    return file.save(INPUT_SETTINGS_PATH)

# 返回未经信任的候选数据；必须经过验证／迁移后才能交给 apply_action()。
func read_profile_candidate() -> Dictionary:
    var file := ConfigFile.new()
    var error := file.load(INPUT_SETTINGS_PATH)
    if error == ERR_FILE_NOT_FOUND:
        return {}  # 第一次运行：使用默认配置。
    if error != OK:
        push_warning("无法加载输入配置，回退默认值：%s" % error)
        return {}
    if file.get_value("meta", "version", 0) != INPUT_SETTINGS_VERSION:
        push_warning("输入配置版本不兼容，需要迁移或恢复默认")
        return {}
    var candidate = file.get_value("players", "profiles", {})
    if not candidate is Dictionary:
        return {}
    return candidate
```

这里的文件函数只是存取片段，不包含完整验证器。验证器至少检查：玩家槽位白名单、语义动作白名单、嵌套字段类型、数组长度上限、事件种类和码值、合法方向、有限且有效的死区、必需动作是否可用、冲突规则和版本迁移。损坏的单项回退默认，不能让恶意／损坏数据创建任意 `ui_*` action。保存失败要提示并允许重试，不显示虚假的“保存成功”；需要更强可靠性时另加临时文件与替换流程。

### 6.2 默认配置与编辑事务

1. **默认值：**项目 Input Map 定义出厂默认键位。首次应用用户覆盖之前，由游戏设置服务提取自己拥有的 action 的事件和死区，转换成第 4 节格式并保存只读默认副本；从默认手柄事件中提取按钮／轴，不持久化 device。也可以维护一份版本化默认配置资源，但应指定唯一默认来源，避免两处不一致。
2. **打开设置：**对已确认档案做 `duplicate(true)`，生成工作副本；所有改键、交换、删除只改工作副本。
3. **应用：**先校验所有变更，再在关闭战斗输入的安全阶段同步应用；更新已确认档案并保存。磁盘失败时保留明确的“仅本次生效／尚未保存”状态。
4. **取消：**若尚未实时应用，直接丢弃工作副本；若有试玩／实时预览，则必须重新应用进入页面前的档案，不能只关窗口。
5. **恢复默认：**把当前玩家或选定范围的工作副本替换为默认值，仍允许确认或取消；不要清除另一玩家档案、手柄归属或整个项目的 UI 映射。
6. **启动加载：**先建立默认值，加载并迁移／验证保存文件，补齐新增 action，再根据本次设备认领编译 InputMap，最后注册 Fray 桥接与创建角色。

`InputMap.action_add_event()` 修改的是运行时映射，不会替你持久化配置。也不要用 `InputMap.load_from_project_settings()` 当成“只重置 P1”：它是全局重载，会覆盖其他运行时修改。[R1]

## 7. 改键期间的战斗输入隔离与恢复

推荐只在主菜单、对战暂停菜单或训练设置中应用改键。下面是游戏层应实现的流程，**不是 Fray 内置的一键 rebind 接口**：

```text
打开设置／手柄掉线
  → 关闭玩家战斗输入入口，暂停战斗逻辑
  → Controller.disabled = true，输入事件适配层停止喂 matcher / advancer
  → 保存推进器原 paused 状态，暂停并清空待消费队列
  → 捕获与编辑工作副本（保持 UI 正常工作）
  → 等待相关旧输入与新输入全部释放，摇杆回中
  → 校验并应用 InputMap；重新选择通道／同步消费者（若设备变化）
  → Fray 恢复物理采样但战斗输入入口仍关闭，确认新配置下已中立
  → 清理观察到的旧边沿、连招历史、蓄力计时和输入窗口
  → 恢复原暂停策略，再开启战斗输入入口
```

具体注意事项：

- `FrayBufferedInputAdvancer.paused = true` **只停止消费，不阻止入队**；必须同时拦截调用 `buffer_press()`／`buffer_sequence()` 的事件入口，再 `clear_buffer()`。
- 当前 FraySequenceMatcher 没有公开 `clear()`。需要清空指令历史时，建议在安全阶段新建 matcher，用原序列树 `initialize(tree)` 并重新接线，同时保留原过滤选项、解除旧引用／连接。不要仅对原实例再次 initialize 就假定所有历史已清空：当前方法没有重置 `_current_frame`、`_last_matched_node`、`_match_branch`。也不从游戏代码直接调用私有 `_reset()`。
- 若使用实验性 FrayInputBuffer，清除其 buffer／window，并在恢复时按玩法重新创建；`clear_buffer()`／`clear_window()` 会删除配置，不只是清空一次按下。另见主指南 7.5 的实现限制。
- 原始 `_input` 的“事件已处理”不会阻止 Fray 读取 Input 状态。`Controller.disabled` 也不会自动关闭全局信号连接；每个输入适配器必须有自己的 `accept_gameplay_input` 等门禁。
- 新旧键都按住时直接换映射，会把一次连续按住继承成新绑定的蓄力／按下状态。必须观察原始键／按钮释放与轴回中；UI 可提供取消等待，但不能将长按误当成确认后的攻击。
- 暂停 SceneTree 可能同时暂停 Fray 的物理采样。UI 使用适当的暂停处理模式；退出设置后先恢复采样、保持战斗入口关闭，至少经过一次**已完成的** Fray 物理更新并检查全部玩家 action 为释放态，再清理缓存并恢复。只 `await process_frame` 或仅等待一个未经顺序确认的 physics_frame 信号不保证 Fray 已采样。
- 通道切换后必须检查新通道状态，不能沿用旧通道的“刚按下／刚松开”。断线玩家在重新认领前保持暂停，不自动回退到全设备手柄输入。
- 恢复推进器原有的暂停／取消窗口策略，不是无条件 `paused = false`；避免从招式前摇中的暂停菜单退出后突然开放取消。

玩家在菜单按下的确认键、改键捕获键、掉线前的长按，都不能在恢复对战时触发一次额外攻击。

## 8. 若不使用 Godot action，而直接用 Fray 绑定

纯手柄、全玩家共用同一键位方案时，可以在启动阶段直接注册：

```gdscript
FrayInputMap.add_bind_joy_button(&"pad_punch", JOY_BUTTON_A)
FrayInputMap.add_bind_joy_axis(&"pad_left", JOY_AXIS_LEFT_X, false, 0.5)
FrayInputMap.add_bind_joy_axis(&"pad_right", JOY_AXIS_LEFT_X, true, 0.5)
# 这条路线下 Controller.device 必须是各玩家实际手柄 ID。
```

改键可取得 `FrayInputBindJoyButton` 后修改 `button`，或取得 `FrayInputBindJoyAxis` 后修改 `axis`、`use_positive_axis`、`deadzone`；键盘绑定可以修改 `FrayInputBindKey.key`。但这些资源属于全局映射：共享 `pad_punch` 的玩家会一起被改。玩家独立设置仍需 `p1_*`／`p2_*` 或自定义适配层，并自行实现持久化、捕获及输入历史清理。

当前实现还有必须先处理的限制：

- `FrayInputBind.get_strength(device)` 调用 `_get_strength_impl()` 时遗漏 device，导致直接手柄绑定的强度可能读设备 0，而 `is_pressed(device)` 却读取指定设备。因此在设备非 0 时，方向 `get_axis()`／强度与按下结果可能不一致。不要把直接手柄路线描述成当前版本已经完整可用；正式采用前应另行修复并测试。
- `FrayInputBindKey` 使用逻辑 `keycode` 语义；不能直接把捕获到的 `physical_keycode` 存进去并声称支持物理键位。要用物理键位，采用本文 action 桥接或实现自己的绑定类。
- `FrayInputBindFrayAction` 可以组合键盘／手柄简单绑定，但键盘绑定忽略 device，会对所有查询通道生效；它不是现成的双人设备路由器。
- 前述设备枚举缺口、动态删除输入后的历史状态、复合输入引用都仍需处理。当前虚拟设备也不能未经验证就当成完整的玩家路由替代方案：物理轮询列表只枚举手柄或回退 0。

因此本项目设置功能优先采用前文的 **玩家独立 action + Godot InputMap + Fray action 桥接**，不是两套方案同时维护相同逻辑输入。

## 9. 验收清单

### 键盘与手柄改键

- [ ] P1 轻拳 J 改 K 后旧键失效、新键生效；角色／指令仍使用原逻辑名称。
- [ ] 修改键盘主键不丢失副键或手柄绑定；修改手柄按钮不丢失键盘配置。
- [ ] physical_keycode 与 keycode 的选择、显示和存取一致；按住键产生 echo 不重复捕获。
- [ ] 十字键、摇杆四方向、模拟扳机都可捕获；轴正负方向正确，漂移不会自动完成绑定。
- [ ] 死区修改实际影响 action，捕获阈值与战斗死区不混用。
- [ ] 冲突可明确交换／替换／取消；不能无提示地移除最后一个必要绑定。

### 双人、设备与热插拔

- [ ] 双人同键盘、键盘 + 手柄、双手柄三种组合互不串输入。
- [ ] 连接 ID 不为 0 的单只手柄时，键盘和 Fray action 状态仍正常更新。
- [ ] 同一个 action 即使在多个 Fray 设备状态中产生事件，也只向该玩家推进器投递一次。
- [ ] P1 拔掉手柄后不会被 P2 手柄控制；重新认领不同 ID 后使用同一键位档案。
- [ ] 设备 0 的连接／断线同样能被 UI 检测；设备归属不只依赖 Fray 连接信号。
- [ ] 同型号双手柄不靠 GUID 自动交换玩家；未认领玩家不添加 device = -1 的事件。

### 设置事务与战斗状态

- [ ] 取消不改变已确认配置；恢复默认只影响指定范围；重启后加载正确。
- [ ] 缺失、损坏、旧版本配置能安全回退／迁移；无法保存时明确提示。
- [ ] 菜单确认、改键候选和长按旧键不会在恢复对战后出招或继承蓄力。
- [ ] Controller、事件适配器、推进器、matcher 和可选 FrayInputBuffer 的暂停／恢复一致。
- [ ] 暂停 SceneTree 后仍能改键；恢复时确实经过 Fray 物理采样再开放战斗输入。
- [ ] 若选择直接 Fray 手柄绑定，已单独修复并覆盖设备非 0 的强度／get_axis 问题。

## 10. 核验依据与参考

### 本地源码（相对 Git 根目录）

- `addons/fray/src/input/autoloads/fray_input_map.gd`：注册、查询、删除绑定；全局映射。
- `addons/fray/src/input/autoloads/fray_input.gd`：设备枚举、连接处理、物理采样、事件分发。
- `addons/fray/src/input/device/binds/input_bind.gd`：get_strength 的 device 传递缺口。
- 同目录 `input_bind_action.gd`、`input_bind_key.gd`、`input_bind_joy_button.gd`、`input_bind_joy_axis.gd`、`input_bind_fray_action.gd`：绑定读取与组合语义。
- `addons/fray/src/input/controller.gd`：device 与 disabled 的作用边界。
- `addons/fray/src/input/device/device_state.gd`：输入状态的保存与按需注册。
- `addons/fray/src/input/sequence_matcher.gd`、`input_buffer.gd`：初始化及缓冲／窗口清理。
- `addons/fray/src/state_mgmt/component/buffered_input_advancer.gd`：暂停只影响消费，以及 clear_buffer()。

### Godot 4.2 官方接口参考

R1 为 InputMap 动态事件与死区接口，R2 为匹配设备的实现参考，R3 为键盘码与事件属性，R4 为手柄事件，R5 为用户配置存储，R6 为设备枚举和输入状态。设备路由、设置事务、冲突策略及上面的兼容流程是本项目设计，不是引擎或 Fray 自动提供的功能。

```text
R1 https://docs.godotengine.org/en/4.2/classes/class_inputmap.html
R2 https://github.com/godotengine/godot/blob/4.2/core/input/input_map.cpp
R3 https://docs.godotengine.org/en/4.2/classes/class_inputeventkey.html
R4 https://docs.godotengine.org/en/4.2/classes/class_inputeventjoypadbutton.html
   https://docs.godotengine.org/en/4.2/classes/class_inputeventjoypadmotion.html
R5 https://docs.godotengine.org/en/4.2/classes/class_configfile.html
R6 https://docs.godotengine.org/en/4.2/classes/class_input.html
```
