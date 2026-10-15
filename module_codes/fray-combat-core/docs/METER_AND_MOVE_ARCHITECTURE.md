# Fray Combat Core：统一气条与可组合招式架构

- 文档范围：统一气条、特殊技强化、绿冲取消、基础攻击、MK 式组合技与自定义角色招式装配
- 适用项目：`codes/fray-combat-core`
- 状态：设计建议，尚未替代当前固定 Demo 实现
- 日期：2026-08-09
- 相关实现：`scripts/fighter/`、`scripts/input/`、`addons/fray/src/hit/attack_attribute.gd`

---

## 1. 设计结论

未来可以让同一条气条同时承担两种用途：

1. **特殊技强化**：普通特殊技在输入窗口内转为强化版本，并支付气条。
2. **绿冲取消**：基础攻击命中或被格挡后，支付气条进入绿冲状态，再衔接基础攻击、组合技或特殊技。

推荐将气条设计为统一的进攻资源池，而不是为“特殊技强化”和“绿冲取消”建立两套独立资源系统。

```text
统一气条账户
    ├── 强化特殊技：购买当前招式的强化变体
    └── 绿冲取消：购买新的取消路线与连招机会
```

气条系统只负责：

- 当前值；
- 上限；
- 增加；
- 原子扣除；
- 资源变化事件。

招式或取消路线负责声明：

- 什么时候可以消费；
- 消费多少；
- 需要什么输入；
- 需要命中、格挡还是无条件；
- 消费后进入哪个 Fray 状态；
- 是否继承源招式时间轴。

这种设计是一个有明确资源竞争的混合战斗系统，不需要一比一复刻任何单款格斗游戏。

---

## 2. 当前项目已经具备的基础能力

### 2.1 统一气条账户已经存在

`CombatCoreFighter` 已经提供统一气条字段和操作方法：

- `meter`
- `can_spend_meter()`
- `try_spend_meter()`
- `add_meter()`
- `meter_changed`

位置：

```text
scripts/fighter/combat_core_fighter.gd:70-74
scripts/fighter/combat_core_fighter.gd:417-439
```

当前的 `try_spend_meter(amount, reason, attribute)` 已经可以作为未来所有付费动作的基础入口。

建议保持“原子检查并支付”的语义：检查失败时不修改气条，支付成功后只发出一次资源变化事件。

### 2.2 特殊技强化已有原型

`FrayAttackAttribute` 当前已经拥有：

```gdscript
amplify_target_state
amplify_start_frame
amplify_end_frame
amplify_meter_cost
```

位置：

```text
addons/fray/src/hit/attack_attribute.gd:42-52
```

当前普通波强化流程为：

```text
普通波
    ↓
施法时间轴内的 Amplify 输入窗口
    ↓
检查气条
    ↓
支付气条
    ↓
切换强化波状态与攻击资源
```

`CombatCoreProjectileAttackState` 已经使用共享施法 runtime，使普通波和强化波可以继续同一条时间轴，不重播动画、不重置施法计时，也不延后投射物生成。

位置：

```text
scripts/fighter/states/combat_core_projectile_attack_state.gd:33-90
```

### 2.3 数据化取消已经存在

`FrayAttackAttribute` 当前已经提供：

```gdscript
cancel_start_frame
cancel_end_frame
cancel_requirement
cancel_target_states
```

并支持：

```text
ALWAYS
ON_HIT
ON_BLOCK
ON_HIT_OR_BLOCK
```

位置：

```text
addons/fray/src/hit/attack_attribute.gd:66-87
```

`FighterStateMachineBuilder` 会读取攻击资源并生成 Fray press/sequence transition，当前的 `J → K → L` 和普通波路线就是这个机制的应用。

位置：

```text
scripts/fighter/fighter_state_machine_builder.gd:163-227
```

### 2.4 当前基础攻击状态已经遵循 Fray-first

`FoundationAttackState` 只保存攻击状态 ID，并从实际 `FrayHitState2D` 的 strike 读取 `FrayAttackAttribute`。

它不负责保存 damage、hitstun 或 knockback 等独立数值。

位置：

```text
scripts/fighter/states/foundation_attack_state.gd:1-6
scripts/fighter/states/foundation_attack_state.gd:28-45
```

未来绿冲取消应继续采用同样的状态机路径，而不是直接在 fighter 脚本中设置一个独立的 `green_rushing` 布尔状态。

---

## 3. 当前实现对“自由搭配招式”的限制

当前代码能够支持固定 Demo，但还不是完整的自定义角色招式系统。

### 3.1 攻击状态列表固定

`CombatCoreFighter` 中的 `ATTACK_STATES` 仍然是写死的：

```text
scripts/fighter/combat_core_fighter.gd:15-18
```

新增角色招式时需要修改 fighter 脚本，无法完全通过角色资源完成装配。

### 3.2 取消目标到输入的映射固定

`FighterStateMachineBuilder` 当前通过常量将状态名映射到输入：

```gdscript
CANCEL_PRESS_INPUT_SUFFIXES
CANCEL_SEQUENCE_INPUT_SUFFIXES
```

位置：

```text
scripts/fighter/fighter_state_machine_builder.gd:9-17
```

这意味着取消规则虽然部分数据化，但目标状态和输入命令仍然依赖 Builder 中的固定映射。

### 3.3 输入序列固定

`FoundationInputSetup` 当前固定创建：

- 前前冲刺；
- 后后冲刺；
- 后、前、轻攻击普通波。

位置：

```text
scripts/input/foundation_input_setup.gd:42-67
```

未来自定义角色需要通过资源声明自己的特殊技命令，而不是继续向这个脚本中添加角色专用分支。

### 3.4 普通波与强化波是专用字段

当前 fighter 直接导出：

```gdscript
projectile_attack_attribute
enhanced_projectile_attack_attribute
```

位置：

```text
scripts/fighter/combat_core_fighter.gd:34-38
```

这适合单个 Demo 招式，但不适合拥有多个普通/强化变体的角色。未来应改为由角色招式注册表收集所有 move 和 variant。

### 3.5 当前取消窗口不能表达多条独立路线

当前每个攻击只有一组：

```gdscript
cancel_start_frame
cancel_end_frame
cancel_requirement
cancel_target_states
```

但同一个基础攻击以后可能同时拥有：

- 免费字符串路线；
- 命中特殊技取消；
- 格挡特殊技取消；
- 付费绿冲取消；
- 不同路线不同窗口。

因此最终需要从“单一取消窗口”升级到“取消路线数组”。

---

## 4. 推荐的角色与招式分层

建议将角色系统拆成三层。

### 4.1 `CombatCharacterDefinition`

角色装配资源只负责声明该角色拥有的招式集合：

```gdscript
class_name CombatCharacterDefinition
extends Resource

@export var character_id: StringName
@export var display_name: String
@export var moves: Array[CombatMoveDefinition]
@export var max_health: int
@export var initial_meter: int
```

示例：

```text
CharacterDefinition
├── stand_light
├── stand_medium
├── stand_heavy
├── string_112_second
├── string_112_third
├── fireball
├── fireball_enhanced
├── uppercut
├── uppercut_enhanced
└── rush_cancel
```

更换角色时主要替换这个资源，而不是修改 `CombatCoreFighter` 的常量。

### 4.2 `CombatMoveDefinition`

招式装配资源只负责描述招式如何接入状态机：

```gdscript
class_name CombatMoveDefinition
extends Resource

@export var move_id: StringName
@export var display_name: String
@export var runtime_kind: RuntimeKind
@export var command: CombatCommandDefinition
@export var hit_state_scene: PackedScene
@export var animation_name: StringName
@export var source_tags: PackedStringArray
```

建议的 `runtime_kind`：

```text
MELEE_ATTACK
PROJECTILE_CAST
RUSH_MOVEMENT
UTILITY
```

此资源不重复保存以下字段：

```text
damage
hitstun
blockstun
knockback
launch
meter gain
```

这些字段仍然只来自实际 strike 上的 `FrayAttackAttribute`。

### 4.3 `FrayAttackAttribute`

实际攻击属性继续保持唯一来源：

```text
CombatMoveDefinition
        ↓ 装配
FrayHitState2D
        ↓ 实际 strike.attribute
FrayAttackAttribute
```

`CombatCoreMatch` 仍然只读取：

```gdscript
strike_hitbox.attribute
```

这样可以避免角色定义、招式表和攻击属性之间出现数值漂移。

---

## 5. 将取消系统改为路线数组

建议新增一个 Fray-compatible 资源，例如：

```gdscript
class_name FrayCancelRoute
extends Resource

## 取消后进入的目标 Fray 状态。
@export var target_state: StringName

## 触发该路线所需的语义输入或序列 ID。
@export var input_id: StringName

## 取消窗口开始帧。
@export var start_frame: int = 0

## 取消窗口结束帧；负值表示持续到源状态结束。
@export var end_frame: int = -1

## 该路线所需的命中/格挡接触条件。
@export var contact_requirement: int = FrayAttackAttribute.CancelRequirement.ALWAYS

## 该路线的气条成本；0 表示免费路线。
@export var meter_cost: int = 0

## 是否从源招式继承时间轴。
@export var continue_source_timeline: bool = false

## 每个连段最多使用次数；负值表示不限制。
@export var max_uses_per_combo: int = -1
```

然后在 `FrayAttackAttribute` 中增加：

```gdscript
@export var cancel_routes: Array[FrayCancelRoute] = []
```

旧字段可以先保留一段时间，用于兼容当前 Demo 资源；迁移完成后再废弃旧字段。

### 5.1 基础攻击绿冲路线示例

```text
源攻击：stand_medium
目标状态：rush_cancel
输入：rush
开始帧：16
结束帧：32
接触条件：ON_HIT_OR_BLOCK
气条成本：1500
时间轴：开始目标状态时间轴
每连段最大次数：1
```

### 5.2 字符串路线示例

```text
源攻击：stand_light
目标状态：stand_combo_medium
输入：medium
开始帧：21
结束帧：32
接触条件：ALWAYS
气条成本：0
```

### 5.3 强化特殊技路线示例

```text
源状态：fireball
目标状态：fireball_enhanced
输入：amplify
开始帧：0
结束帧：11
接触条件：ALWAYS
气条成本：1000
时间轴：继承源状态时间轴
```

这样，免费字符串、特殊技取消、强化技和绿冲都变成同一种“取消路线”概念。

---

## 6. 绿冲状态设计

建议新增：

```gdscript
class_name CombatRushCancelState
extends FoundationState
```

它只负责：

- 进入时启动前冲；
- 按固定物理帧推进移动；
- 维持绿冲期间的控制窗口；
- 在规定阶段允许新的 Fray press/sequence transition；
- 结束时返回中立状态。

推荐状态拓扑：

```text
基础攻击
   │
   │ 命中/格挡 + rush 输入 + meter 足够
   ▼
rush_cancel
   ├── light press  ──> stand_light
   ├── medium press ──> stand_medium
   ├── heavy press  ──> stand_heavy
   ├── sequence     ──> special_move
   └── 时间结束     ──> idle / walk
```

建议给 `rush_cancel` 添加类似以下 Fray tags：

```text
grounded
movement_action
controllable
rush_cancel
```

不要在 `CombatCoreFighter` 中新增一套独立的字符串状态分发：

```gdscript
if state == "green_rush":
    ...
```

如果需要外部战斗事件打断绿冲，继续通过已有的集中反应网关处理。

---

## 7. 输入系统资源化

建议新增 `CombatCommandDefinition`，由角色招式资源声明命令：

```gdscript
class_name CombatCommandDefinition
extends Resource

enum CommandKind {
    PRESS,
    COMPOSITE,
    SEQUENCE,
    HOLD_RELEASE,
}

@export var command_id: StringName
@export var kind: CommandKind
@export var input_steps: Array
@export var max_step_delays: PackedInt32Array
@export var priority: int = 0
```

示例：

```text
rush:
  kind = COMPOSITE
  inputs = [medium, heavy]
```

```text
fireball:
  kind = SEQUENCE
  inputs = [back, forward, light]
```

```text
uppercut:
  kind = SEQUENCE
  inputs = [forward, down, down_forward, heavy]
```

角色初始化时：

1. 遍历 `CombatCharacterDefinition.moves`；
2. 收集所有 command；
3. 使用 Fray 输入 API 注册语义输入、组合输入和序列输入；
4. `FighterStateMachineBuilder` 根据招式资源生成状态和转移。

这样更换角色时不需要修改 `FoundationInputSetup`。

---

## 8. 统一气条的平衡建议

当前规则是三格气条，每格内部值为 `1000`。可以以此作为第一版测试基础。

建议的起始测试值：

| 行为 | 建议初始成本 |
|---|---:|
| 强化特殊技 | 1000 |
| 基础攻击绿冲取消 | 1500～2000 |
| 超级技（以后加入） | 2000～3000 |

这些数值只是初始平衡点，最终需要通过连段、压制和资源获取测试调整。

绿冲通常比单次强化特殊技拥有更高的通用性，因为它可能提供：

- 连招延长；
- 重新贴身；
- 压制延续；
- 格挡后的继续进攻；
- 连段路线重置。

因此不建议一开始让强化技和绿冲都只消耗同样的 1000。

### 8.1 推荐的第一版绿冲限制

```text
基础攻击必须命中或被格挡
挥空不能绿冲
每个连段最多绿冲一次
绿冲本身不立即奖励大量气条
```

原因是当前攻击命中会产生 meter gain。如果允许：

```text
命中赚气 → 绿冲 → 再命中赚气 → 再绿冲
```

连段很容易变成资源循环。

`ComboContext` 可以记录以下运行时字段：

```gdscript
rush_cancel_count
meter_spent
special_amplify_count
```

这些是运行时派生数据，不属于第二套攻击定义表。

---

## 9. 输入缓冲与 hitstop 注意事项

当前 hitstop 会集中暂停：

- Fray 状态机；
- 运动推进；
- `FrayBufferedInputAdvancer` 的输入消费；
- 输入缓冲时钟。

相关实现：

```text
scripts/fighter/foundation_fighter.gd:326-337
scripts/input/foundation_input_setup.gd:95-100
```

实现绿冲时需要明确测试以下问题：

1. 绿冲输入是否允许在 hitstop 期间被记录；
2. hitstop 结束后是否能在取消窗口内消费；
3. 取消窗口的帧数是按游戏逻辑帧还是按真实时间计算；
4. 预输入路线失败时是否需要清理对应 sequence；
5. 绿冲转移和同帧命中批量结算的先后顺序是否固定。

推荐继续使用固定 60 Hz 的游戏逻辑帧，不要让动画帧成为绿冲窗口的第二个时钟。

---

## 10. 推荐实施顺序

### 阶段 1：建立角色招式注册表

新增：

- `CombatCharacterDefinition`；
- `CombatMoveDefinition`；
- `CombatCommandDefinition`。

先把当前固定 Demo 招式迁移进去，但保持行为不变。

目标：新增招式时不再修改 `CombatCoreFighter` 的攻击常量。

### 阶段 2：迁移取消规则

新增 `FrayCancelRoute`，把当前路线迁移为：

```text
stand_light → stand_combo_medium
stand_combo_medium → stand_heavy
stand_combo_medium → projectile
projectile → enhanced_projectile
```

同时保留旧字段作为过渡兼容，避免一次迁移过大。

### 阶段 3：通用化 Amplify

将普通波专用的：

```text
amplify_target_state
amplify_meter_cost
can_amplify_projectile
```

逐步转化为通用的带成本取消路线。

投射物状态仍可保留共享施法 runtime，但不再限制只有一组普通波/强化波。

### 阶段 4：加入 `CombatRushCancelState`

先支持：

```text
地面基础攻击命中/格挡
    → 绿冲
    → 基础攻击
```

确认状态中断、hitstop、输入缓冲和 meter 支付都稳定后，再加入特殊技和字符串分支。

### 阶段 5：验证第二个角色

第二个角色应能够只通过资源完成以下内容：

- 基础攻击；
- 不同的 MK 式组合技；
- 两种以上特殊技；
- 至少一种强化特殊技；
- 基础攻击绿冲取消；
- 不同于第一个角色的输入命令。

如果需要修改通用 fighter 或 Builder 的角色专用常量，说明装配层仍然没有完全资源化。

---

## 11. 最终架构目标

最终希望得到以下数据流：

```text
CombatCharacterDefinition
        ↓
CombatMoveDefinition[]
        ↓
FrayStateMachineBuilder
        ├── Fray press transition
        ├── Fray sequence transition
        ├── cancel route condition
        └── resource payment gate
        ↓
FrayState / FrayHitState2D
        ↓
实际 strike.attribute
        ↓
FrayAttackAttribute
        ↓
CombatCoreMatch
        ├── damage
        ├── hitstun / blockstun
        ├── knockback / launch
        ├── meter gain
        └── combat reaction
```

统一气条的使用路径：

```text
FrayCancelRoute
        ├── meter_cost = 1000
        │       └── 强化特殊技
        │
        └── meter_cost = 1500～2000
                └── 绿冲取消
```

核心约束保持不变：

- 输入使用 Fray；
- 状态拓扑使用 Fray；
- 攻击和受击数值只来自 `FrayAttackAttribute`；
- 状态内行为由 `FrayState` 负责；
- 跨角色的通用规则放在资源或 Builder；
- 角色特殊行为保持薄层；
- 不建立第二套并行的攻击定义表或状态分发系统。

---

## 12. 本设计的取舍

### 优点

- 一个资源池带来清晰的战术取舍；
- 强化技和绿冲可以共享支付、事件和 HUD；
- 适合 MK 式字符串与传统方向指令并存；
- 能保留 Fray-first 的输入和状态机设计；
- 新角色主要通过资源装配；
- 方便以后加入超级技、特殊防御或其他付费动作。

### 风险

- 统一气条可能让绿冲和强化技互相竞争，平衡难度高于独立资源；
- 如果取消路线仍使用单一窗口，无法表达复杂角色；
- 如果绿冲允许无限连段使用，可能产生资源循环；
- 如果输入注册和攻击状态仍写死在 Builder 中，自定义角色最终仍需要改代码；
- 需要专门验证 hitstop、输入缓冲、批量结算与支付时机。

### 结论

可以采用统一气条方案。建议把它正式定义为：

> **统一气条驱动的多用途进攻资源系统。**

其中强化特殊技和绿冲取消都是 `FrayAttackAttribute` 声明的、可由 Fray transition 触发的付费路线；区别只在于目标状态、时间轴策略、接触条件和资源成本。