# 01 Fray Fighter Foundation

这是一个独立的 Godot 4.7 / Fray 2.0.0-alpha 格斗角色基础项目。当前版本重点展示一套由 **Fray 状态机、Fray 输入、Fray 输入缓冲与 Fray hitbox** 共同驱动的格斗游戏角色状态框架，并包含每次离地一次的二段跳。

- 项目入口：`res://scenes/main.tscn`
- 物理频率：60 Hz
- 状态拓扑：`scripts/fighter/fighter_state_machine_builder.gd`
- 角色入口：`scripts/fighter/foundation_fighter.gd`
- 移动适配：`scripts/fighter/foundation_movement.gd`
- 攻击数据：`resources/attacks/*.tres`

## 状态集合

### 地面与移动

- `idle`：站立待机
- `walk_forward`：相对朝向前进
- `walk_back`：相对朝向后退，速度低于前进
- `crouch`：下蹲
- `dash_forward`：双击 forward 前冲
- `dash_back`：双击 back 后撤
- `jump_start`：起跳预备
- `jump`：一段跳上升
- `double_jump`：二段跳；每次离地默认只能使用一次
- `fall`：下落
- `land`：落地恢复

### 防御

- `stand_guard`：站立防御
- `crouch_guard`：下蹲防御
- `blockstun`：格挡硬直

### 基础攻击

- `stand_light`：站立轻攻击
- `stand_heavy`：站立重攻击
- `crouch_light`：下蹲轻攻击
- `crouch_heavy`：下蹲重攻击
- `air_light`：空中轻攻击
- `air_heavy`：空中重攻击

### 受击、倒地与回合状态

- `hitstun`：地面受击硬直
- `air_hitstun`：空中受击硬直
- `knockdown`：倒地与受身窗口
- `tech_roll`：软倒地受身翻滚
- `wakeup`：起身恢复
- `ko`：KO 终止状态，只能由回合重置离开
- `locked`：集中控制锁定

## 操作

| 按键 | 行为 |
|---|---|
| `A` / `D` | 向左 / 向右；状态按当前朝向解释为前进或后退 |
| `S` | 下蹲 |
| `W` | 跳跃；空中重新按下可进入 `double_jump` |
| 双击相对 forward | 前冲 `dash_forward` |
| 双击相对 back | 后撤 `dash_back` |
| `J` | 轻攻击；站立、下蹲、空中进入对应攻击状态 |
| `K` | 重攻击；站立、下蹲、空中进入对应攻击状态 |
| `Q` | 保持防御；软倒地受身窗口中重新按下可进入 `tech_roll` |

| `1` | 调试地面/空中受击硬直 |
| `2` | 调试格挡硬直 |
| `3` | 调试倒地 |
| `4` | 调试起身恢复 |
| `5` | 调试 KO |
| `R` | 重置位置、朝向、状态、速度和输入缓冲 |
| `L` | 切换集中控制锁定 |
| `P` | 普通暂停：状态机停止消费，缓冲时钟继续 |
| `H` | hitstop 式暂停：状态机停止消费，缓冲时钟冻结 |

朝向由 `FoundationFighter.facing_direction` 直接保存，黄色箭头显示当前值。角色与 `OpponentMarker2D` 换边时，fighter 在允许自动改向的地面状态中直接更新朝向；同一物理方向键随后会映射为新的 `forward` / `back` 语义。

## 朝向与转身规则

- `FoundationFighter.facing_direction` 是角色朝向的唯一来源：`1` 表示向右，`-1` 表示向左。
- `FoundationMovement` 不再缓存或自动修改朝向，只读取 fighter 属性计算前后走、跳跃、冲刺、攻击前移和受击推退。
- 当角色处于地面中立或防御状态且对手换到背后时，fighter 直接更新 `facing_direction`，不进入独立转身状态。
- 朝向改变会发出 `facing_changed` 信号；假定表现层已有转身动画，并由该信号触发动画，而不阻塞 Fray 战斗状态。
- 攻击、空中、受击、倒地和冲刺过程中不会任意瞬间转身；回到允许自动改向的地面状态后才更新朝向。
- 状态基类已移除 `get_horizontal_axis()`；需要世界水平输入的状态直接从 `FrayController` 读取 left/right 轴。
## 二段跳规则

- `FoundationFighterEnvironment.max_air_jumps` 默认是 `1`，即一段跳后最多追加一次空中跳跃。
- 二段跳必须在 `jump` 或 `fall` 中重新按下 `W`，长按起跳键不会自动重复触发。
- 二段跳进入独立的 `double_jump` Fray 状态，并刷新垂直速度与当前方向的水平轨迹。
- 落地后空中跳跃次数由 `FoundationMovement` 集中重置。
- 二段跳转移仍由 `FrayBufferedInputAdvancer` 和 Fray press transition 完成，没有私有输入分发。

## 攻击数据与 hitbox

六种基础攻击均使用 `FrayAttackAttribute` 资源作为唯一数据来源，包含：

- 总时长、startup、active；
- damage、block damage；
- hitstun、blockstun、hitstop；
- knockback、launch、knockdown、受身窗口；
- 攻击前移 lunge。

六个攻击 `FrayHitState2D` 由角色场景中的 `FrayHitStateManager2D` 统一管理；每个 hit state 直接包含至少一个 `FrayHitbox2D`，且其 `attribute` 直接绑定对应 `.tres`。角色初始化时从 hitbox 校验并缓存唯一的 `FrayAttackAttribute`，`FighterStateMachineBuilder` 不再直接引用攻击资源；`FoundationAttackState` 只读取该 attribute 来推进攻击帧、位移和 strike 激活窗口。

角色场景还包含常驻 `FrayHurtboxAttribute` hurtbox。当前 foundation 主要演示状态框架、攻击判定资源和外部反应 API；完整的双角色伤害、格挡判定、血量、连段与回合裁判仍应由后续战斗解析层接入。

## Fray-first 设计

- 所有角色状态继承 `FrayState`，共享薄基类 `FoundationState`。
- 全部状态拓扑集中在 `FighterStateMachineBuilder`。
- 按键与双击序列通过 Fray press/sequence transition 进入状态。
- 外部 hitstun、blockstun、knockdown、wakeup、KO 统一通过 `FoundationFighter.request_external_state()` 进入。
- `FoundationMovement` 只负责 `CharacterBody2D` 运动，不维护状态枚举或转移图。
- `FoundationFighterEnvironment` 只保存环境、移动、跳跃和恢复物理参数；攻击与受击数值不在其中重复定义。
- 攻击 strike 直接挂载 `FrayAttackAttribute`，符合 Fray hitbox attribute 数据流。

## 输入与缓冲

输入层包含：

- `FrayController`：读取移动、轻/重攻击和防御；
- `FrayConditionalInput`：根据朝向生成 `p1_forward` 与 `p1_back`；
- `FrayCombinationInput`：生成 `p1_down_forward`；
- `FraySequenceTree`：识别双击 forward/back；
- `FrayBufferedInputAdvancer`：配置 5F（`0.083333 s`）最大候选年龄窗口；
- 调试 HUD：显示当前状态、tag、速度、输入、缓冲年龄、状态历史与成功招式历史。

Fray 原版 advancer 会在尝试队首输入后移除该项目；若当前状态拒绝该输入，它不会跨状态继续保存。这是当前 Fray core 的既有语义，本项目没有另写并行缓冲系统。

## 目录结构

```text
fighter foundation/
├─ addons/fray/                         # Fray 核心，未为本功能另建并行系统
├─ resources/
│  ├─ attacks/                          # FrayAttackAttribute 攻击/调试反应资源
│  ├─ combat/                           # FrayHurtboxAttribute
│  └─ environment/                      # 移动与舞台环境参数
├─ scenes/
│  ├─ hitboxes/                         # 六种攻击的 FrayHitState2D 场景
│  ├─ fighter_foundation.tscn           # fighter、hurtbox 与 strike 实例
│  ├─ foundation_debug_overlay.tscn
│  └─ main.tscn
├─ scripts/
│  ├─ fighter/                          # fighter、movement、builder 与状态
│  ├─ input/
│  ├─ resources/fighter/
│  └─ debug/
└─ docs/
   ├─ TDD.md
   └─ TEST_PLAN.md
```

## 启动与验证

在项目目录运行：

```bash
godot --path .
```

从工作区根目录运行：

```bash
godot --path "codes/fighter foundation"
```

无窗口加载检查：

```bash
godot --headless --path "codes/fighter foundation" --quit
```

本工作区当前机器未将 `godot` / `godot4` 加入 PATH，因此本次修改只能完成静态检查；请在安装 Godot 4.7 的环境中按 `docs/TEST_PLAN.md` 进行运行验证。