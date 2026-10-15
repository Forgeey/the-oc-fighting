# Fighter Foundation 测试计划

## 1. 验证入口

在工作区根目录执行：

```bash
godot --headless --path "codes/fighter foundation" --quit
```

交互验证：

```bash
godot --path "codes/fighter foundation"
```

本机当前没有可用的 `godot` / `godot4` PATH 命令，因此本次修改未执行运行时验证；以下用例需要在 Godot 4.7 环境中完成。

## 2. 基础加载

### FF-01：项目加载

1. 启动 `res://scenes/main.tscn`。
2. 观察 Output 和 debugger。

预期：

- 无脚本解析错误、无缺失资源；
- fighter 初始化成功；
- HUD 显示 `idle`；
- hurtbox 常驻，六个 strike 初始关闭。

### FF-02：输入映射与 HUD

依次按 A、D、S、W、J、K、Q。

预期：

- HUD 能显示对应 `p1_*` 语义输入；
- 输入历史记录按下/松开边沿；
- 状态转移只由 Fray transition 产生。

## 3. 地面中立与移动

### FF-03：前进和后退

1. 面向右时按 D，再按 A。
2. 移动到 marker 另一侧或调整 marker，使角色面向左，再重复。

预期：

- 朝向右时 D=`walk_forward`、A=`walk_back`；朝向左时相反；
- `walk_back` 最大速度约为前进的 78%；
- 松开后回到 `idle`；
- 黄色箭头与 facing 一致。

### FF-04：下蹲与姿态切换

1. idle 时按住 S。
2. 保持 S 再按 Q。
3. 保持 Q 松开 S。
4. 松开 Q。

预期状态顺序：

`idle -> crouch -> crouch_guard -> stand_guard -> idle`。

### FF-05：冲刺

1. 角色面向右时快速输入 D、松开、再按 D（66），然后输入 A、松开、再按 A（44）。
2. 角色面向左时重复测试；此时 A 应为 66，D 应为 44。
3. 测试超出 220 ms 的慢双击。

预期：

- 任一朝向下，连续两次 `forward` 只进入 `dash_forward`，连续两次 `back` 只进入 `dash_back`；
- `p1_forward` 与 `p1_back` 不会由同一个物理方向同时触发；
- 前冲比后撤更快且持续更久，最后一帧速度分别收敛到各自最大速度的 `dash_exit_speed_ratio`；
- 慢双击不进入冲刺；
- 动作结束回 idle，意外离地则进入 fall。

### FF-06：换边与转身

1. 在 idle 或行走时越过 `OpponentMarker2D` 的水平位置。
2. 分别在 crouch、stand_guard、crouch_guard 中让 marker 换到角色背后。
3. 在攻击、冲刺、空中和受击过程中发生换边，观察状态结束后的行为。

预期：

- 允许转身的地面状态检测到换边后进入独立 `turn`；
- `turn` 进入时 `FoundationFighter.facing_direction` 改为对手方向，黄色箭头同步翻转；
- 默认持续 3F，期间水平速度停止，结束后根据当前输入进入 idle、前后走、下蹲或防御；
- 攻击、冲刺、空中和受击过程中不会被瞬间翻转，回到允许转身的地面状态后才进入 `turn`；
- 换边后 forward/back 与 66/44 按新朝向解释。

## 4. 跳跃与二段跳

### FF-07：一段跳轨迹

分别测试 W、A+W、D+W，并在角色换边后重复。

预期：

- 先进入 `jump_start`，再进入 `jump`；
- 预备阶段缓存相对方向；
- 生成垂直跳、前跳或后跳固定轨迹；
- 顶点进入 `fall`，落地进入 `land`，恢复后回 `idle`。

### FF-08：二段跳

1. 按 W 起跳。
2. 松开 W，在 `jump` 或 `fall` 中再次按 W。
3. 二段跳后尝试第三次按 W。
4. 落地后重新测试。

预期：

- 第二次独立 press 进入 `double_jump`；
- 垂直速度被重新设置为向上，水平速度按当前方向刷新；
- 同一次离地的第三次 W 不再进入 `double_jump`；
- 落地后次数重置，下一次离地可再次二段跳。

### FF-09：二段跳边界

1. 一段跳时持续按住 W，不松开。
2. 在 `air_light` / `air_heavy` 中按 W。
3. 走出平台后在 fall 中按 W。

预期：

- 长按不会自动触发二段跳；
- 空中攻击状态不接受二段跳输入；
- 自然落体仍可消耗一次空中跳跃进入 `double_jump`。

## 5. 攻击状态

### FF-10：站立轻重攻击

1. idle、前进和后退时分别按 J、K。
2. 观察状态、颜色、速度和 strike 调试形状。

预期：

- 进入 `stand_light` / `stand_heavy`；
- 角色显示攻击色；
- startup 期间 strike 关闭，active 窗口开启，之后关闭；
- 时长、active 与 lunge 来自对应 `FrayAttackAttribute`；
- 退出状态后 strike 不残留。

### FF-11：下蹲攻击

1. 按住 S 进入 crouch。
2. 分别按 J、K。

预期：

- 分别进入 `crouch_light`、`crouch_heavy`；
- crouch heavy 使用 low guard type，并带软倒地数据；
- 攻击结束且仍接地时回 idle。

### FF-12：空中攻击与落地

1. 一段跳或二段跳后按 J、K。
2. 在攻击 active/recovery 期间落地。

预期：

- 分别进入 `air_light`、`air_heavy`；
- 攻击过程中继续应用空中重力；
- 落地立即进入 `land`，攻击 hit state 被关闭；
- 未落地且攻击结束时进入 `fall`。

### FF-13：攻击资源单一来源

在 Inspector 检查 `fighter_foundation.tscn` 和六个 `scenes/hitboxes/*_hit_state.tscn`。

预期：

- `AttackHitStateManager` 挂载 `FrayHitStateManager2D`，六个攻击 `FrayHitState2D` 都是其直接子节点；
- 每个 `FrayHitState2D` 至少直接包含一个 strike `FrayHitbox2D`；
- `FrayHitbox2D.attribute` 直接挂对应 `resources/attacks/*.tres`；
- `FighterStateMachineBuilder` 不 preload 攻击资源；
- fighter 脚本和状态脚本没有 damage/hitstun/knockback 平行表。

## 6. 防御与反应状态

### FF-14：站防与蹲防

1. idle 时保持 Q。
2. Q+S 切换蹲防。
3. 保持 Q 松开 S。
4. 松开 Q。

预期：

- 状态在 `stand_guard` / `crouch_guard` 间切换；
- 防御中不能主动行走或攻击；
- 松开 Q 返回 idle。

### FF-15：格挡硬直

1. 保持 Q 后按数字 2。
2. 硬直中分别保持/松开 Q，并测试 S 姿态。

预期：

- 进入 `blockstun`；
- 持续帧与推退基于 debug `FrayAttackAttribute`；
- 结束后按保持姿态进入站防、蹲防或 idle。

### FF-16：地面受击硬直

1. 地面按数字 1。
2. 观察速度、持续时间和结束状态。

预期：

- 进入 `hitstun`；
- 水平击退和硬直帧来自 debug attribute；
- 资源当前无垂直 launch，结束后回 idle。

### FF-17：空中受击硬直

1. 跳跃中按数字 1。
2. 分别观察落地前和落地时状态。

预期：

- 进入 `air_hitstun`；
- 空中继续应用重力；
- 落地转入 `knockdown`，随后进入起身流程。

### FF-18：软倒地、受身和起身

1. 按数字 3 进入 knockdown。
2. 不输入 Q，等待状态结束。
3. 再次进入 knockdown，在不可受身帧结束后重新按 Q。
4. 在不可受身窗口内提前按 Q。

预期：

- 不受身：`knockdown -> wakeup -> idle`；
- 合法受身：`knockdown -> tech_roll -> idle`；
- 过早 Q 不进入受身，且按 Fray 当前缓冲语义不会跨状态窗口自动触发；
- 离开 knockdown 后受身许可关闭。

### FF-19：KO

1. 按数字 5。
2. 尝试移动、跳跃和攻击。
3. 按 R。

预期：

- 进入 `ko` 后不自动离开；
- 普通角色输入不能改变状态；
- R 清理状态并回到 idle。

### FF-20：外部 wakeup

1. 任意状态按数字 4。
2. 等待恢复帧结束。

预期：进入 `wakeup`，结束后回 idle；外部状态跳转只经过 `FoundationFighter.request_external_state()`。

## 7. 生命周期与缓冲

### FF-21：控制锁定

1. 行走、跳跃、攻击或反应中按 L。
2. 锁定期间输入移动和攻击。
3. 再按 L。

预期：

- 集中进入 `locked`；
- controller 禁用且输入缓冲清空；
- 锁定期间无输入转移；
- 解锁回 start state。

### FF-22：回合重置

1. 移动并进入任意动作/反应状态。
2. 按 R。

预期：

- 恢复出生 transform 与 facing；
- 清除速度、控制锁、暂停、受身窗口、反应缓存和所有 strike；
- 清空输入/状态/招式调试历史；
- 回到 idle。

### FF-23：普通暂停

1. 按 P 暂停。
2. 输入 W/J 或 dash sequence，等待超过 100 ms。
3. 按 P 恢复。

预期：状态机暂停期间不消费；缓冲时钟继续，超过 `83.333 ms` 的输入恢复后被清理。

### FF-24：hitstop 式暂停

1. 按 H 暂停。
2. 输入 W/J 或 dash sequence，等待 1 秒。
3. 观察 buffer age，再按 H 恢复。

预期：状态机不消费且缓冲时钟冻结；恢复后按冻结年龄尝试输入。

## 8. 静态回归

- `.gd`、`.tscn`、`.tres`、`.godot`、`.cfg` 为 UTF-8 无 BOM；
- `.tscn` / `.tres` 第一字节是 `[`；
- 所有项目源文件中的 `res://` 引用存在；
- 新增 GDScript 使用 tab 缩进；
- 项目内 `class_name` 不重复；
- 所有 fighter 状态继承 `FoundationState -> FrayState`；
- 状态转移只在 builder 中定义；
- fighter 输入转移不使用 `Input.is_action_*`；
- 攻击数值只存在于 `FrayAttackAttribute`；
- strike 与 hurtbox 使用不同物理层，并共享 fighter source 以避免自击。

## 9. 测试记录模板

```text
日期：
Godot / Fray 版本：
测试 ID：
操作：
实际结果：
预期结果：
通过/失败：
日志、截图或视频：
备注：
```