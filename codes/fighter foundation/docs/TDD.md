# Fighter Foundation 技术设计文档

## 1. 目标

本项目提供一个可继续扩展的 Fray-first 格斗角色基础。角色需要覆盖常见格斗游戏中的中立、移动、跳跃、攻防、受击、倒地、起身、KO 和控制锁定流程，并明确提供独立的二段跳状态。

设计约束：

1. 状态类全部继承 `FrayState`。
2. 状态拓扑只允许出现在 `FighterStateMachineBuilder`。
3. 输入转移使用 Fray press/sequence transition 和 `FrayBufferedInputAdvancer`。
4. 攻击与受击反应数据只来自 `FrayAttackAttribute`。
5. `FoundationMovement` 只实现物理动作，不实现平行状态机。
6. 外部战斗事件集中进入 `FoundationFighter.request_external_state()`。

## 2. 模块职责

### 2.1 FoundationFighter

负责：

- 验证 autoload、环境资源和调试反应资源；
- 装配 `FrayController`、输入映射、序列树、advancer 和状态机；
- 收集六个攻击 `FrayHitState2D`；
- 激活常驻 hurtbox，并把 fighter 设为 hitbox source；
- 直接持有 `facing_direction` 朝向属性，并根据对手位置提供 `needs_turn` condition；
- 集中处理 hitstun、blockstun、knockdown、wakeup、KO、locked、reset；
- 向 HUD 投影状态、输入缓冲和历史，不参与状态判定。

### 2.2 FighterStateMachineBuilder

负责唯一状态图。状态按职责分为：

- 中立：`idle`、`walk_forward`、`walk_back`、`crouch`；
- 移动动作：`turn`、`dash_forward`、`dash_back`、`jump_start`、`jump`、`double_jump`、`fall`、`land`；
- 防御：`stand_guard`、`crouch_guard`、`blockstun`；
- 攻击：六种站立/下蹲/空中轻重攻击；
- 反应：`hitstun`、`air_hitstun`、`knockdown`、`tech_roll`、`wakeup`；
- 终止与生命周期：`ko`、`locked`。

输入驱动转移：

- `W`：地面中立状态到 `jump_start`；
- 空中重新按 `W`：`jump` / `fall` 到 `double_jump`；
- 双击 forward/back：进入相应冲刺；
- `J` / `K`：按站立、下蹲或空中姿态进入对应攻击；
- `Q`：保持站防/蹲防，或在受身窗口按下进入 `tech_roll`；


自动转移：

- 地面中立/防御状态检测到换边后进入 `turn`，结束后按输入姿态退出；
- `jump_start -> jump -> fall -> land -> idle`；
- `double_jump -> fall`；
- 地面动作离地后进入 `fall`；
- 空中攻击落地后进入 `land`；
- hitstun 结束后按 grounded/knockdown 条件进入 `idle`、`fall` 或 `knockdown`；
- air hitstun 落地后进入 `knockdown`；
- blockstun 结束后根据防御保持姿态回到站防、蹲防或 idle；
- knockdown 结束后进入 `wakeup`，软倒地窗口可进入 `tech_roll`；
- `ko` 不自动退出。

### 2.3 FoundationMovement

这是 `CharacterBody2D` 的薄物理适配层，负责：

- 前进/后退差异化速度、加速和摩擦；
- 前冲/后撤的加速、制动和固定帧时长；
- 固定方向的一段跳轨迹；
- 上升、顶点、下落分段重力；
- 二段跳次数、速度刷新和落地重置；
- 受身翻滚；
- 攻击 lunge；
- 受击、格挡、倒地击退；
- 地面吸附、地面高度修正与 arena 边界；
- 每个状态每物理帧最多一次 `move_and_slide()`。

### 2.4 FoundationFighterEnvironment

环境资源保存非攻击类参数：

- 前进/后退速度及地面加速度；
- dash 参数；
- 一段跳、二段跳和重力参数；
- turn、tech roll、默认 knockdown、wakeup 参数；
- 格挡推退倍率和反应摩擦；
- floor snap、safe margin、floor_y 与 arena 边界。

damage、hitstun、blockstun、knockback、launch、knockdown 等攻击/受击数据不得进入该资源。

## 3. 朝向与转身设计

`FoundationFighter.facing_direction` 是朝向的唯一所有者，值被规范为 `1`（向右）或 `-1`（向左）。`FoundationInputSetup`、状态脚本和 `FoundationMovement` 都读取该属性，不再通过 `FoundationMovement.get_facing()` 间接访问。

`FoundationMovement.refresh_snapshot()` 只刷新 grounded 与空中跳跃次数，不再根据对手位置瞬间改向。Builder 将 `FoundationFighter.needs_turn()` 注册为 Fray condition，并仅允许 idle、前后走、crouch、站防和蹲防进入 `turn`。`FoundationTurnState` 在 enter 时调用 `turn_toward_opponent()` 提交朝向，经过 `turn_duration_frames` 后再按当前输入姿态退出。

共享状态基类不再提供 `get_horizontal_axis()`。需要世界方向输入的 walk、jump start、double jump 和 tech roll 状态直接调用 `FrayController.get_axis()`；朝向和输入轴保持两个独立概念。
## 4. 二段跳设计

二段跳由三个部分配合：

1. `FoundationMovement.can_double_jump()` 检查角色未接地且 `_air_jumps_used < max_air_jumps`。
2. Builder 仅从 `jump` 与 `fall` 注册上方向 press transition 到 `double_jump`。
3. `FoundationDoubleJumpState._enter_impl()` 调用 `launch_double_jump()`，集中消耗次数并刷新速度。

默认 `max_air_jumps = 1`。`refresh_snapshot()` 检测接地后把使用次数归零。由于 transition 是 press 而不是按住 condition，玩家必须松开并重新按下 `W`，不会因一段跳时持续按住而自动触发二段跳。

## 5. 攻击与判定数据流

每种攻击由两部分组成：

- `resources/attacks/*.tres`：`FrayAttackAttribute` 唯一数据源；
- `scenes/hitboxes/*_hit_state.tscn`：`FrayHitState2D` 直接包含 strike `FrayHitbox2D`，hitbox attribute 直接指向上述资源。

角色场景使用 `FrayHitStateManager2D` 统一管理六个攻击 hit state。初始化时逐个校验 hit state 至少包含一个 `FrayHitbox2D`、所有 hitbox 引用同一个 `FrayAttackAttribute`，并要求 attribute ID 与状态名一致。`FighterStateMachineBuilder` 只声明攻击状态拓扑，不直接 preload 攻击资源。

`FoundationAttackState` 在 enter 时取得已校验的 hit state 和 hitbox attribute，在 startup 结束后启用全部 strike，在 active 结束后关闭，并在 exit 时确保整个 hit state 停用。攻击状态不复制帧数或伤害数据。

角色 hurtbox 使用 `FrayHurtboxAttribute`。strike layer/mask 为 4/8，hurtbox layer/mask 为 8/4；同一 fighter 的所有 hitbox source 相同，因此默认不会自击。

当前 foundation 没有实现完整战斗解析器。后续解析器应从交叉的 strike `FrayHitbox2D.attribute` 取得 `FrayAttackAttribute`，再根据格挡姿态调用 `request_external_state("blockstun")` 或 `request_external_state("hitstun")`，而不是拆散参数传递。

## 6. 反应与恢复

- `FoundationHitstunState`：读取 `hitstun_frames`、`knockback`、`launch_y_velocity`。
- `FoundationBlockstunState`：读取 `blockstun_frames`，推退使用 `knockback * block_pushback_ratio`。
- `FoundationKnockdownState`：读取 `knockdown_frames`、`untechable_frames`、硬倒地标记。
- `FoundationTechRollState`：只在软倒地受身窗口中由 Q press 进入。
- `FoundationWakeupState`：使用环境资源中的固定恢复帧。
- `FoundationKOState`：非完成状态，只能 reset 或外部生命周期切换。

## 7. Tag 与全局规则

- `neutral`：idle、前后走、crouch；
- `movement_action`：turn、dash、jump 流程与 land；
- `defense`：stand/crouch guard、blockstun；
- `attack`：六种攻击；
- `reaction`：blockstun、hitstun、air hitstun、knockdown、tech roll、wakeup；
- `terminal`：KO；
- `locked`：locked。

可控制状态与反应状态允许通过 Fray global rule 进入 `locked`。外部强制反应仍由 `FoundationFighter` 集中 `goto()`，避免任意状态脚本散落跳转。

## 8. 暂停、重置和调试

- `P`：停止状态机与 advancer 消费，但缓冲时钟继续。
- `H`：同时冻结缓冲时钟，模拟 hitstop。
- `R`：清缓冲、速度、临时反应资源、受身窗口与调试历史，并回到 start state。
- `L`：通过集中 API 进入/退出 locked。
- 数字 `1`～`5`：通过外部状态 API 演示硬直、倒地、起身与 KO。

HUD 只读取快照和 Fray 信号，不得反向驱动角色。

## 9. 已知边界

- 当前场景只有一个可操作 fighter 和一个朝向 marker，没有完整双角色结算。
- 没有血量、资源槽、连段修正、投技、特殊技、超必杀、AI 与回合裁判。
- 没有自动测试套件；运行验证见 `TEST_PLAN.md`。
- Fray 原版 buffered advancer 不会保留当前状态已经拒绝的队首输入，本项目不修改 Fray core。