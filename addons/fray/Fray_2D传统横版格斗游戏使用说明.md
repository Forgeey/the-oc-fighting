# Fray（Godot 4）2D 传统横版格斗游戏使用说明

> **依据：仓库根目录 `addons/fray/` 当前源码，`plugin.cfg` 版本 `2.0.0-alpha`。**
> **核对日期：2026-10-16；输入映射、FrayInputBuffer、多框组合、自定义按键、Advancer 表驱动与统一输入仲裁补充核对：2026-10-17。** 插件随附安装说明标注 Godot 4.2+；本文示例使用 Godot 4 GDScript。
>
> 本文是面向本项目的推荐接入方案，不表示项目已经实现全部功能。插件接口以根目录 `addons/fray/` 为依据；动画组织参考 `addons/fray_demo/` 的角色场景。已静态核对相关接口和引用路径，示例尚未通过 Godot 引擎运行测试。
>
> **核心约定：每个角色仅有一个 `FrayHitStateManager2D`。每个 `FrayHitState2D` 只包含该姿态实际需要的框，同类框可以有多个；idle、jump 等非攻击动作无需创建 Attackbox，也不按框的类别拆成多个管理器。**

## 目录

1. [能力边界与安装](#1-能力边界与安装)
2. [推荐角色节点树](#2-推荐角色节点树)
3. [单管理器与位掩码](#3-单管理器与位掩码)
4. [三类框的属性和碰撞层](#4-三类框的属性和碰撞层)
5. [初始化与动作播放入口](#5-初始化与动作播放入口)
6. [动画方案：AnimationPlayer 主控，AnimatedSprite2D 显示](#6-动画方案animationplayer-主控animatedsprite2d-显示)
7. [输入与行为状态机](#7-输入与行为状态机)
8. [指令识别与取消](#8-指令识别与取消)
9. [命中防御与去重](#9-命中防御与去重)
10. [推挤框与角色分离](#10-推挤框与角色分离)
11. [当前源码注意事项](#11-当前源码注意事项)
12. [实施步骤与验收清单](#12-实施步骤与验收清单)
13. [源码与参考资料](#13-源码与参考资料)

## 1. 能力边界与安装

### 1.1 Fray 提供什么

| 模块 | 当前插件类／单例 | 游戏层需要补充的内容 |
| --- | --- | --- |
| 输入映射与查询 | `FrayInputMap`、`FrayInput`、`FrayController` | 双人设备分配、方向归一化、前后换算 |
| 指令识别 | `FraySequenceMatcher`、`FraySequenceTree`、`FraySequenceBranch` | 必杀技指令表、优先级、输入消费策略 |
| 行为状态 | `FrayStateMachine`、`FrayCompoundState`、`FrayState` | 移动、跳跃、攻击、防御、受击、倒地状态逻辑 |
| 缓冲输入推进 | `FrayBufferedInputAdvancer` | 取消窗口、何时暂停消费、命中停顿规则 |
| 判定管理 | `FrayHitStateManager2D`、`FrayHitState2D` | 各动作框布局、启用时机 |
| 区域与属性 | `FrayHitbox2D`、`FrayHitboxAttribute` | 伤害、防御、连段、击退、推挤解算 |
| 动画观察（可选） | `FrayAnimationObserver`、动画跟踪资源 | 动画与招式逻辑的权威时钟约定 |

**`FrayHitbox2D` 是通用战斗区域，不只代表攻击框。** 本文三类框都用这个类型，依靠自定义属性和碰撞层区分用途。插件不会自动扣血，不会自动把重叠角色推开，也不自带完整的传统格斗规则。

### 1.2 安装与工程边界

1. 把当前根目录插件的内容放进目标 Godot 工程的 `res://addons/fray/`，保证存在 `res://addons/fray/plugin.cfg`。
2. 在项目设置的插件页启用 Fray，检查自动加载 `FrayInputMap`、`FrayInput`。不要重复添加同名单例。
3. 确认 Godot 能识别 `FrayHitStateManager2D` 等 `class_name` 类型。
4. 示例按 **60 Hz 固定物理节拍**设计，请在目标工程中明确配置。不要用渲染帧率决定招式帧数。
5. 自定义脚本、场景和 `.tres` 应放在插件之外，方便以后升级插件。

本文的 `res://` 始终指**目标 Godot 工程根目录**。Git 根目录的插件并不会自动成为 `the-oc-fighting/project.godot` 使用的插件；把同名目录放在仓库里不等于该工程已加载它。不要把完整 Demo 工程或其他插件副本一并复制进目标工程的资源目录，以免扫描到重复类名和无关脚本。

推荐资源布局：

```text
res://
├── addons/fray/                   # 插件，不在这里放游戏逻辑
├── combat/attributes/             # 三类框的自定义属性
├── combat/moves/                  # 游戏自定义招式数据
├── fighters/common/               # 角色公共脚本、行为状态
├── fighters/character_a/           # 角色场景、动画、专用招式
└── battle/                        # 对战流程、命中队列、推挤解算
```

## 2. 推荐角色节点树

下列结构是推荐新建的角色场景，括号内为类型。为便于入门，主树先展示每类一个框；**不代表每个状态只能有一个攻击框或一个受击框**。每个 `→ CollisionShape2D` 表示该框下有一个直接子形状节点，多框与多形状扩展见本节后半部分。

```text
Fighter (CharacterBody2D，角色脚本)
├── WorldCollision (CollisionShape2D，场景地面／墙体碰撞)
├── Controller (FrayController)
├── AnimationPlayer (AnimationPlayer，动作时间轴，Physics 更新)
├── StateMachine (FrayStateMachine)
│   ├── InputAdvancer (FrayBufferedInputAdvancer)
│   └── AnimationObserver (FrayAnimationObserver，可选)
├── VisualRoot (Node2D，图像与判定统一换向)
│   ├── Sprite (AnimatedSprite2D，仅显示帧，不自行播放)
│   ├── EffectsRoot (Node2D)
│   └── HitStateManager (FrayHitStateManager2D，角色唯一管理器)
│       ├── Stand (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       ├── Crouch (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       ├── Jump (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       ├── LightPunch (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   ├── Attackbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       ├── Guard (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       ├── Hurt (FrayHitState2D)
│       │   ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│       │   └── Pushbox (FrayHitbox2D) → CollisionShape2D
│       └── Knockdown (FrayHitState2D)
│           ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
│           └── Pushbox (FrayHitbox2D) → CollisionShape2D
└── Audio (AudioStreamPlayer2D)
```

### 必须遵守的结构规则

- **一个角色一个管理器**，两名角色各一个，不是整场对战共用一个。
- 每个 HitState 只创建实际需要的框。Stand（供 idle／walk 使用）、Jump 等非攻击姿态不创建 Attackbox；Hurtbox、Pushbox 也按玩法需要保留，可以只有其中一种。上图的非攻击姿态以同时保留 Hurtbox、Pushbox 为例。
- HitState 是管理器的**直接子节点**；实际存在的判定框是 HitState 的**直接子节点**。不要增加中间分组节点，插件不会递归查找其中的框。
- 推荐已有框按 **所有 Hurtbox → 所有 Attackbox → 所有 Pushbox** 的相对顺序排列，缺少的框直接省略，**不保留空位**。每个状态的位索引按实际框顺序单独计算；增删／重排框后必须同步修改该状态的掩码和动画轨。不要在这些直接子节点之间混入装饰或工具节点，避免 Inspector 标号与位索引混淆。
- `WorldCollision` 用于角色与场景的实体碰撞；Pushbox 用于角色之间的战斗推挤检测，不是替代场景碰撞的实体形状。
- 图像和判定按同一朝向制作。换向由 VisualRoot 或统一的镜像逻辑处理，别只改 Sprite 的 `flip_h` 而忘记框，也别重复镜像。
- `FrayState` 是资源对象，不是 Godot 场景节点。Idle、LightPunch 等行为状态通过代码构建，无需在 StateMachine 下堆同名 Node。
- 可选 AnimationObserver 应配置相应的 tracker 资源和动画节点路径；它不替你播放动画或决定招式有效帧。不使用时不要添加一个 tracker 为空的观察器节点，当前实现会直接调用 tracker。

### 多框组合：同一 HitState 下平铺多个判定框

某些姿态需要用头、躯干、腿部多个框组成受击轮廓；某些招式需要用拳头、前臂或武器多个框组成攻击范围。它们仍属于**同一个完整 HitState**，不需要为每个框创建一个状态或管理器。下面是主树的局部扩展示例，`StandComposite`、`HeavySlash` 都直接放在原有 HitStateManager 下：

```text
HitStateManager (FrayHitStateManager2D，仍是原来的唯一管理器)
├── StandComposite (FrayHitState2D，非攻击姿态示例)
│   ├── HurtHead (FrayHitbox2D) → CollisionShape2D       # 索引 0，位值 1
│   ├── HurtTorso (FrayHitbox2D) → CollisionShape2D      # 索引 1，位值 2
│   ├── HurtLegs (FrayHitbox2D) → CollisionShape2D       # 索引 2，位值 4
│   └── Pushbox (FrayHitbox2D) → CollisionShape2D       # 索引 3，位值 8
└── HeavySlash (FrayHitState2D，攻击姿态示例)
    ├── HurtHead (FrayHitbox2D) → CollisionShape2D       # 索引 0，位值 1
    ├── HurtTorso (FrayHitbox2D) → CollisionShape2D      # 索引 1，位值 2
    ├── HurtLegs (FrayHitbox2D) → CollisionShape2D       # 索引 2，位值 4
    ├── AttackNear (FrayHitbox2D) → CollisionShape2D    # 索引 3，位值 8
    ├── AttackTip (FrayHitbox2D) → CollisionShape2D     # 索引 4，位值 16
    └── Pushbox (FrayHitbox2D) → CollisionShape2D       # 索引 5，位值 32
```

- `HurtHead` 等只是节点名称；每个受击框都要配置 HURT 属性和 Hurt 碰撞层，每个攻击框都要配置 ATTACK 属性以及检测 Hurt 的 Mask（见第 4 节）。不要靠节点名字推断类别。
- 每个独立框都占一个 `active_hitboxes` 位，可分别启停、移动和配置属性；同类别、同规则的多个框可以共享属性资源，但命中记录仍保存在游戏层。
- 不要建成 `HeavySlash/Hurtboxes/HurtHead` 或 `HeavySlash/Attackboxes/AttackTip`。中间的 Node2D 分组会使框脱离当前状态的直接子节点管理范围，包括位掩码控制、source 传播和信号转发。
- 上面的 StandComposite 是可选替代布局，不会自动替换主树的 Stand。如果实际替换，需同步修改第 5 节初始化常量以及 idle／walk 动画轨；不能继续使用原两框布局的 `3`。

### 另一种组合：一个逻辑框下挂多个形状

如果几块区域始终共享启停时机、属性和碰撞层，且结算不需要识别命中了哪一块，可以只建一个 `FrayHitbox2D`，用多个直接子 `CollisionShape2D` 拼出轮廓。Godot 的 Area2D 支持这种组合，参见第 13.2 节 G6、G7。

```text
HeavySlash (FrayHitState2D)
├── Hurtbox (FrayHitbox2D，索引 0，位值 1)
│   ├── HeadShape (CollisionShape2D)
│   ├── TorsoShape (CollisionShape2D)
│   └── LegsShape (CollisionShape2D)
├── Attackbox (FrayHitbox2D，索引 1，位值 2)
│   ├── NearShape (CollisionShape2D)
│   └── TipShape (CollisionShape2D)
└── Pushbox (FrayHitbox2D，索引 2，位值 4)
    └── CollisionShape2D
```

这是与上一个 HeavySlash **二选一的布局**：它在 Fray 看来只有三个逻辑框，前摇／后摇仍为 `5`，有效段仍为 `7`。形状数量不增加掩码位数。`attribute`、Layer／Mask 和 source 都属于所属 FrayHitbox2D，不是每个形状独立一套。

当前 Fray 使用 `area_entered`／`area_exited` 转发框级信号，没有转发携带形状索引的 `area_shape_entered`／`area_shape_exited`；通过管理器的两个框参数无法判断具体碰到 HeadShape 还是 LegsShape。需要部位差异、甜点／弱点伤害或独立开关时，优先采用上面的**多个独立 FrayHitbox2D**，而不是期待管理器自动识别子形状。

`FrayHitbox2D.activate()`／`deactivate()` 控制整个区域，不会重置子形状的 `disabled`。如另行控制形状开关，应自行管理其生命周期，并遵守 CollisionShape2D 的延迟设置要求（G7）；本指南推荐用独立框的位掩码表达战斗开关，避免再维护一套形状开关状态。

## 3. 单管理器与位掩码

### 3.1 两种状态，不要混淆

**行为状态**决定角色做什么，例如前进、轻拳、受击硬直。

**HitState**决定该动作使用的整套判定区域，只包含当前姿态需要的受击框、攻击框和／或推挤框。

Idle、Walk 可以共用 Stand 判定；LightPunch 行为可以始终使用 LightPunch 判定，只改变攻击框的开关。若需要把前摇／有效帧／后摇分别建成三个 HitState，也可以，但**每个必须包含该阶段所需的完整判定，由同一个管理器切换**，不能指望保留上一状态的受击框或推挤框。前摇／后摇状态可以不创建 Attackbox；如果共用一个 LightPunch 状态，则保留 Attackbox，只在有效段启用。

不要创建 HurtStateManager、AttackStateManager、PushStateManager 三套独立管理器。否则攻击换姿势时，很容易遗留上一姿势的受击框或推挤框。

### 3.2 `active_hitboxes` 的含义

索引按**当前 HitState 实际拥有的直接子 `FrayHitbox2D` 节点顺序**计数，从 0 开始。位值为 `1 << 索引`，多个框用按位或 `|` 合并。**位表示框的位置，不表示框的类别；缺少 Attackbox 时不会为它空出一位。**

以下按第 2 节节点顺序举例：

| HitState／实际框布局 | 索引与位值 | 常用掩码 |
| --- | --- | --- |
| Stand、Jump 等：Hurtbox → Pushbox | Hurtbox：索引 0，位值 `1`；Pushbox：索引 1，位值 `2` | `3` = 受击 + 推挤；`1` = 仅受击；`2` = 仅推挤 |
| 只有 Hurtbox 的姿态 | Hurtbox：索引 0，位值 `1` | `1` = 仅受击 |
| 只有 Pushbox 的姿态 | Pushbox：索引 0，位值 `1` | `1` = 仅推挤 |
| LightPunch：Hurtbox → Attackbox → Pushbox | Hurtbox：索引 0，位值 `1`；Attackbox：索引 1，位值 `2`；Pushbox：索引 2，位值 `4` | 前摇／后摇 `5`；普通有效段 `7` |
| 任意布局 | — | `0` = 关闭该状态的所有框，不用于选中另一个状态 |

因此不能跨状态共用固定的 `HURT = 1`、`ATTACK = 2`、`PUSH = 4` 作为类别位值。建议使用带布局／状态前缀的常量，动画轨的数值也按目标状态分别填写：

```gdscript
# Stand：只有 Hurtbox、Pushbox。
const STAND_HURT := 1 << 0
const STAND_PUSH := 1 << 1
const STAND_DEFAULT_MASK := STAND_HURT | STAND_PUSH  # 3

# LightPunch：Hurtbox、Attackbox、Pushbox。
const LIGHT_PUNCH_HURT := 1 << 0
const LIGHT_PUNCH_ATTACK := 1 << 1
const LIGHT_PUNCH_PUSH := 1 << 2
const LIGHT_PUNCH_PASSIVE_MASK := LIGHT_PUNCH_HURT | LIGHT_PUNCH_PUSH  # 5
const LIGHT_PUNCH_ACTIVE_MASK := LIGHT_PUNCH_PASSIVE_MASK | LIGHT_PUNCH_ATTACK  # 7
```

**只有实际框布局相同的状态才能复用同一套位常量。** 比如 Jump 若与 Stand 一样包含 Hurtbox → Pushbox，可同样使用 `3`；若 Jump 只有 Hurtbox，则启用值为 `1`。属性中的 `kind` 和第 4 节碰撞层用于区分框类别，不会决定 `active_hitboxes` 的位索引。

仅针对上述 **LightPunch 三框布局**，特殊情况的掩码为：无敌攻击有效段 `6`（攻击 + 推挤）、无敌但仍阻挡对手 `4`（仅推挤）、可受击但允许穿身 `1`（仅受击）。不要把这些数字直接套到 Stand 或其他布局。

防御通常保留受击框，通过结算判断是命中还是防御。关闭受击框是让攻击接触不到角色，不等于普通防御。

### 3.3 如何选中状态

当前源码通过**给目标 HitState 设置非零 `active_hitboxes`**选中状态：

```gdscript
# 两个独立的选中示例，按动作需要调用其中一个。
$VisualRoot/HitStateManager/Stand.active_hitboxes = 3       # Hurtbox + Pushbox
$VisualRoot/HitStateManager/LightPunch.active_hitboxes = 7  # Hurtbox + Attackbox + Pushbox
```

实际调用链：

```text
赋值 active_hitboxes
  → 启停目标状态的各个框
  → active_hitboxes_changed 信号
  → 如果掩码非零，管理器记录目标名称并停用其他状态
  → 调用该状态 activate()
```

重要区别：

- 当前管理器没有公开 `switch_state()`／`change_state()`。不要直接调用下划线开头的内部切换方法。
- `HitState.activate()` 只设置活动标记并显示节点，**不会自动开启所有框**。
- **写入 0 不会把管理器切到目标状态**。当前状态名也不会因此自动清空。
- 管理器仍会对发出变化信号的状态调用 `activate()`，所以 `is_active()`／`visible` 不一定精确反映“该状态有框在工作”。应结合管理器当前名称、`active_hitboxes` 和实际框监测状态检查。
- 当前 `set_hitbox_active(index, enabled)` 已移除原先阻止从零开启框的错误判断，但尚未补上合法索引检查，见第 11.2 节。本文仍统一使用整值赋值；若调用辅助方法，必须保证索引属于当前状态实际存在的框。

### 3.4 多框组合的掩码与管理器用法

以下只对应第 2 节的**六框 HeavySlash 布局**，不是三逻辑框、多形状版本：

```gdscript
# HeavySlash：HurtHead、HurtTorso、HurtLegs、AttackNear、AttackTip、Pushbox。
const HEAVY_HURT_HEAD := 1 << 0
const HEAVY_HURT_TORSO := 1 << 1
const HEAVY_HURT_LEGS := 1 << 2
const HEAVY_ATTACK_NEAR := 1 << 3
const HEAVY_ATTACK_TIP := 1 << 4
const HEAVY_PUSH := 1 << 5

# 组合常量只是游戏脚本中的整数，不是插件内置的“类别组”。
const HEAVY_HURT_MASK := HEAVY_HURT_HEAD | HEAVY_HURT_TORSO | HEAVY_HURT_LEGS  # 7
const HEAVY_ATTACK_MASK := HEAVY_ATTACK_NEAR | HEAVY_ATTACK_TIP  # 24
const HEAVY_PASSIVE_MASK := HEAVY_HURT_MASK | HEAVY_PUSH  # 39
const HEAVY_ACTIVE_MASK := HEAVY_PASSIVE_MASK | HEAVY_ATTACK_MASK  # 63
```

| 目标状态与阶段 | 掩码 | 实际开启的框 |
| --- | --- | --- |
| StandComposite 常态 | `15` = `1 \| 2 \| 4 \| 8` | 三个受击框 + 推挤框 |
| HeavySlash 前摇／后摇 | `39` = `7 \| 32` | 三个受击框 + 推挤框 |
| HeavySlash 仅近端有效 | `47` = `39 \| 8` | 三个受击框 + AttackNear + 推挤框 |
| HeavySlash 近端和尖端同时有效 | `63` = `39 \| 24` | 全部六个框 |
| HeavySlash 仅尖端有效 | `55` = `39 \| 16` | 三个受击框 + AttackTip + 推挤框 |
| HeavySlash 有效段、仅头部不可受击 | `62` = `63 & ~1` | 除 HurtHead 外的五个框 |
| HeavySlash 有效段、全部受击框关闭 | `56` = `24 \| 32` | 两个攻击框 + 推挤框 |

要选中六框 HeavySlash，仍然只需给它写入非零整组掩码，例如 `heavy_slash.active_hitboxes = HEAVY_PASSIVE_MASK`（`heavy_slash` 为该节点引用）。管理器不需要新增接口，会停用同级的其他 HitState；本状态内部允许多个同类框同时开启。**互斥单位是 HitState，不是单个 Hitbox。**

动画中统一写 `HeavySlash:active_hitboxes`，不要为 HurtHead、AttackNear 等分别建立管理器，也不要让两个 HitState 分别贡献一部分受击／攻击轮廓。若用 `set_hitbox_active()` 单独开框，也会经过同一状态选择逻辑；不能在非当前状态上开一位来“叠加”它。

组合受击框还需注意：关闭 HurtHead 只表示该区域不参与受击检测；若 HurtTorso 与头部区域重叠，对手仍可能通过 HurtTorso 命中。整身不可受击必须清掉**所有受击位**，而不是只清某一个 Hurtbox。多个攻击框也不自动代表多段攻击，段号与去重规则见第 9 节。

## 4. 三类框的属性和碰撞层

### 4.1 推荐碰撞层

这是一套工程约定，不是 Fray 预置设置。层号从 1 开始，括号内是代码中的位值。

| 对象 | Collision Layer | Collision Mask |
| --- | --- | --- |
| 地面、墙壁 | 第 1 层 World（1） | 按场景配置 |
| Hurtbox | 第 2 层 Hurt（2） | 0 |
| Attackbox | 第 3 层 Attack（4） | 第 2 层 Hurt（2） |
| Pushbox | 第 4 层 Push（8） | 第 4 层 Push（8） |

攻击框主动检测受击框；受击框不反向产生攻击检测。推挤框可双向检测，但每对角色在一帧中只做一次分离解算。

`FrayHitbox2D.activate()` 会将 `monitoring`、`monitorable` 都设为 true，所以单靠在 Inspector 关闭 Hurtbox 的 monitoring 并不能永久限定检测方向。应使用 Mask 和属性筛选。

角色物理体的场景碰撞层应另行约定，Mask 包含 World；若使用本指南的自定义推挤，不要再让两名 CharacterBody2D 互相作为同一套刚性阻挡重复解算。

### 4.2 统一的自定义属性示例

新建下列游戏脚本。它不是插件自带类；所有三类框都使用其资源实例，以 `kind` 区分。

```gdscript
# res://combat/attributes/fighting_box_attribute.gd
@tool
class_name FightingBoxAttribute
extends FrayHitboxAttribute

enum Kind { HURT, ATTACK, PUSH }
enum HitLevel { MID, LOW, OVERHEAD }

@export var kind: Kind = Kind.HURT
@export var hit_level: HitLevel = HitLevel.MID
@export var damage: int = 0
@export var hitstun_frames: int = 0
@export var blockstun_frames: int = 0
@export var hitstop_frames: int = 0
@export var knockback: Vector2 = Vector2.ZERO

func _allows_detection_of_impl(other: FrayHitboxAttribute) -> bool:
    var other_box := other as FightingBoxAttribute
    if other_box == null:
        return false
    match kind:
        Kind.ATTACK:
            return other_box.kind == Kind.HURT
        Kind.PUSH:
            return other_box.kind == Kind.PUSH
    return false

func _get_color_impl() -> Color:
    match kind:
        Kind.HURT:
            return Color(0.2, 0.5, 1.0, 0.4)
        Kind.ATTACK:
            return Color(1.0, 0.2, 0.2, 0.4)
        Kind.PUSH:
            return Color(0.2, 1.0, 0.3, 0.4)
    return Color(1.0, 1.0, 1.0, 0.4)
```

为每类框保存对应 `.tres`：

- `hurt.tres`：kind 为 HURT。
- `light_punch.tres`：kind 为 ATTACK，并填写伤害、硬直和击退等配置。
- `push.tres`：kind 为 PUSH。

将资源赋给框的 **`attribute`（单数）**。自定义脚本必须包含 `@tool`，供编辑器调用调试颜色逻辑。当前实现会把 `get_color()` 的返回值写入直接子 `CollisionShape2D.debug_color`；调试显示仍需在编辑器／运行调试中启用相应可视化。

`_allows_detection_of_impl()` 表示“当前框是否主动检测对方”，不是“允许谁打我”。HURT 返回 false 不妨碍 ATTACK 主动检测它。

以上伤害等字段是**游戏自定义数据**，插件不会读取它们并自动扣血。MID／LOW／OVERHEAD 的规则也由游戏定义：例如普通 MID 允许站防或蹲防、LOW 要求蹲防、OVERHEAD 要求站防。

### 4.3 source、实例和资源共享

- 管理器的 `source` 是 **Node 引用**，在 Inspector 选择 Fighter，或运行时赋值 `hit_manager.source = self`。
- source 会传递给管理器下的各个框。保持 `detect_source_hitboxes = false`，结算层也应明确拒绝同 source。
- 所有框都应有非空 attribute；空属性会走宽松检测分支，不能把它当作可靠过滤。
- 属性资源保存配置，不保存生命值、命中过谁等运行状态。共享 `.tres` 会影响多个使用者。
- 每个实例需要独立改变 Shape2D 时，使用独立／本地场景资源，避免一个角色改框导致另一个也变形。
- 弹体可以拥有独立的判定生命周期，但其攻击者归属、队伍与去重策略必须明确；不需要给本体再添第二个 HitStateManager 来表示弹体。

## 5. 初始化与动作播放入口

本文采用第 6 节的方案：**招式内部的显示帧与判定开关交给 AnimationPlayer；脚本只负责初始化、动作开始／中断、命中结算和状态转换。** 不再由状态脚本逐帧写攻击框掩码。

下面是 Fighter 上的基础脚本。先按照第 6 节创建动画资源，再接入第 7 节的行为状态机。它不包含移动与完整伤害结算。

```gdscript
# res://fighters/common/fighter.gd
extends CharacterBody2D

# 仅适用于 Stand 的 Hurtbox → Pushbox 布局。
const STAND_HURT := 1 << 0
const STAND_PUSH := 1 << 1

@onready var hit_manager: FrayHitStateManager2D = $VisualRoot/HitStateManager
@onready var sprite: AnimatedSprite2D = $VisualRoot/Sprite
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var attack_instance_id: int = 0
var attack_segment_id: int = 0
var action_generation: int = 0
var _action_name: StringName = &""
var _action_finished: bool = false

func _ready() -> void:
    hit_manager.source = self
    for child in hit_manager.get_children():
        if child is FrayHitState2D:
            child.active_hitboxes = 0
    apply_hit_pose(&"Stand", STAND_HURT | STAND_PUSH)  # 3：无动作时的初始化姿态

    sprite.autoplay = ""
    sprite.stop()
    animation_player.autoplay = ""
    animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
    animation_player.playback_default_blend_time = 0.0
    animation_player.animation_finished.connect(_on_action_animation_finished)
    # 接好第 7 节后，在这里调用 _initialize_behavior()。

# 仅供初始化、紧急切换等生命周期操作使用；动作内部由动画属性轨写掩码。
func apply_hit_pose(state_name: StringName, mask: int) -> void:
    var state := hit_manager.get_node_or_null(NodePath(state_name)) as FrayHitState2D
    if state == null:
        push_error("Unknown hit state: %s" % state_name)
        return
    if mask == 0 and hit_manager.get_current_state() != state_name:
        push_error("A zero mask cannot select a different hit state.")
        return
    state.active_hitboxes = mask

# 本例约定 AnimationPlayer 默认库中的动作名与 SpriteFrames 动画组名相同。
# 返回动作代号，供行为状态辨认本次播放是否正常完成。
func begin_action(action_name: StringName) -> int:
    if not animation_player.has_animation(action_name):
        push_error("Missing action animation: %s" % action_name)
        return -1
    if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(action_name):
        push_error("Missing sprite frames: %s" % action_name)
        return -1

    end_action()
    _action_name = action_name
    _action_finished = false
    # 先选择图片组，之后动画轨只需要驱动 frame，避免两条轨的赋值顺序歧义。
    sprite.stop()
    sprite.animation = action_name
    sprite.frame = 0
    sprite.frame_progress = 0.0
    animation_player.speed_scale = 1.0
    animation_player.play(action_name, 0.0)  # 不混合两套战斗判定
    animation_player.advance(0.0)            # 立即应用 t=0 的画面和完整判定
    return action_generation

func end_action() -> void:
    action_generation += 1
    _action_name = &""
    _action_finished = false
    animation_player.clear_queue()
    animation_player.stop(true)
    sprite.stop()
    # stop 不代表清理框；取消和受击也会走这里，不依赖动画结尾关键帧。
    var current := hit_manager.get_current_state_obj()
    if current != null:
        current.active_hitboxes = 0

func is_action_finished(generation: int) -> bool:
    return generation >= 0 and generation == action_generation and _action_finished

func _on_action_animation_finished(animation_name: StringName) -> void:
    if animation_name == _action_name:
        _action_finished = true  # 只记结果，由行为状态在自己的更新阶段决定下一步
```

关键约定：

- `idle`、`light_punch` 等 AnimationPlayer 资源必须存在，SpriteFrames 中也要有对应组名。
- 每个动作 **t=0 必须包含自己的 frame 和完整非零掩码关键帧**，否则播放后可能只有图片而没有正确判定。
- 在 Inspector 中也关闭两个节点的 Autoplay，避免角色 `_ready()` 之前就开始播放。
- `apply_hit_pose()` 不是第二套逐帧控制系统。正常攻击的 5 → 7 → 5 只出现在动画轨上。
- 例子直接监听当前 AnimationPlayer 的完成信号，未使用异步等待；若项目增加延迟方法、协程或排队事件，必须附带并检查 `action_generation`。
- `begin_action()`、`end_action()` 只能在初始化或安全的逻辑更新阶段调用。碰撞回调先收集事件，不要在那里切换动画／改区域监测状态。
- 当前实现主要在 `_ready()` 建立状态与框的连接，初版预建全部 HitState；动态新增时另行完成 source 和信号接入。
## 6. 动画方案：AnimationPlayer 主控，AnimatedSprite2D 显示

### 6.1 是否采用 Demo 的做法

**建议采用“AnimationPlayer 时间轴统一控制画面和判定”的思路。** 本地参考场景为 `addons/fray_demo/demos/example/2d/player/player.tscn`，其中能看到精灵 `frame`、`animation` 属性轨，以及 `HitStates/HitState2D:active_hitboxes` 属性轨；角色脚本也通过播放动作动画响应行为切换。

但要准确区分“参考思路”和“已经完成的战斗实现”：当前 Demo 中检索到的 `active_hitboxes` 轨位于 RESET 动画，并不能证明所有招式都已配置了完整的攻击有效帧。我们应自行给**每个动作**配置所需判定框和相应的 0 时刻／有效段／结束段关键帧，不照搬 RESET 的判定值、框顺序或 Demo 的节点组织。

### 6.2 两个节点不是二选一

Godot 的 AnimationPlayer 可驱动节点属性，也可以与 AnimatedSprite2D 组合使用；AnimatedSprite2D 通过 SpriteFrames 管理帧图。下面是本项目基于这一能力作出的分工，而不是引擎强制规定。参见第 13.2 节资料 G1、G2。

| 方案 | 适合情况 | 本项目结论 |
| --- | --- | --- |
| AnimatedSprite2D 自行播放 | 纯画面循环、无精确战斗判定的装饰动画 | 可用于独立特效，不作为主角色战斗时序 |
| AnimationPlayer + Sprite2D | 素材统一为规则图集，愿意维护 texture／hframes／vframes／frame | 完全可行，作为图集规范统一后的替代方案 |
| **AnimationPlayer + AnimatedSprite2D** | 角色帧图分组多，需要方便组织动作素材，并在同一时间轴编辑判定 | **本项目默认方案** |

这里不是认为 AnimatedSprite2D 画质更好或 AnimationPlayer 性能必然更好。选择依据是素材组织和战斗时序维护：

- **AnimatedSprite2D**：保存动作图片组并显示指定 `frame`，运行时不调用它的 `play()`。
- **AnimationPlayer**：决定何时显示哪张图，何时开启／关闭三类判定，必要时驱动局部框位置和表现事件。
- **FrayStateMachine**：决定能否开始、取消或结束动作，以及下一状态是什么。
- **对战逻辑**：处理伤害、防御、命中停顿、推挤、连段与资源消耗。

禁止“AnimatedSprite2D 自行播放图片，同时 AnimationPlayer 只播放判定轨”。那样同一个动作有两套独立时间进度，变速、暂停或中断时容易不同步。

### 6.3 节点与轨道配置

按第 2 节节点树，设置 `AnimationPlayer.root_node = NodePath("..")`，下列路径都相对于 Fighter：

| 轨道目标 | 用途 | 设置 |
| --- | --- | --- |
| `VisualRoot/Sprite:frame` | 显示哪个帧图 | Value 属性轨，Update Mode = Discrete，Interpolation = Nearest |
| `VisualRoot/HitStateManager/LightPunch:active_hitboxes` | 整套框启用位掩码 | Value 属性轨，Discrete，Nearest |
| `VisualRoot/HitStateManager/LightPunch/Attackbox:position` | 攻击框随姿势变化（需要时） | 通常 Discrete，Nearest |
| `VisualRoot/HitStateManager/LightPunch/Hurtbox:position` | 受击轮廓变化（需要时） | 通常 Discrete，Nearest |
| `VisualRoot/HitStateManager/LightPunch/Pushbox:position` | 推挤轮廓变化（需要时） | 通常 Discrete，Nearest |
| 局部视觉偏移、特效或声音 | 表现 | 按需要，不能反过来决定伤害 |

Discrete 使属性在关键帧更新；位掩码与帧索引不能按连续数值插值。平滑表现轨可以连续插值，但不要让这种设置扩散到判定掩码上。参见资料 G3。

本方案由 `begin_action()` 先指定 SpriteFrames 动画组，时间轴只写 `frame`。若改成像 Demo 一样也加 `Sprite:animation` 轨，需要明确动画组赋值早于 frame；改变动画组会重置其帧进度，不能依赖未知的轨道顺序。

形状变化优先通过分段 HitState 或独立 Shape2D 资源实现。若关键帧直接修改 `CollisionShape2D.shape` 内部尺寸，确保每个角色实例资源独立。不要同时 key `active_hitboxes`、`monitoring`、`monitorable`、`CollisionShape2D.disabled` 四套开关，否则管理器与形状实际状态容易互相矛盾。

**不把 CharacterBody2D 的全局 position 交给动画轨处理战斗移动。** 前进、击退、冲刺位移由物理逻辑执行；AnimationPlayer 可驱动专用“期望速度／位移数据”，再由角色移动逻辑消费。视觉后仰和残影可以只操作显示子树。

### 6.4 编辑一个完整轻拳

下面是 60 Hz 下的**动作时间轴设计**：前摇 5 帧，有效 3 帧，后摇 12 帧，共 20 帧。图片帧不等于逻辑帧，一张图可保持多个逻辑帧。

1. 在 SpriteFrames 中创建 `light_punch` 图片组，本例至少有索引 0–4 的五张图。
2. 在 AnimationPlayer 的默认 AnimationLibrary 中创建同名 `light_punch` 动画。
3. 关闭该动作的循环；Length 设为 `20.0 / 60.0` 秒。
4. 时间轴吸附步长设为 `1.0 / 60.0` 秒。吸附只是编辑辅助，不会自动保证引擎物理检测的采样顺序。
5. 给 `Sprite:frame` 和 `LightPunch:active_hitboxes` 添加下面的离散关键帧。
6. 编辑器预览时，先手动将 Sprite 的 animation 选为 light_punch，再拖动 AnimationPlayer 时间轴；运行时这一步由 begin_action 完成。单纯选中时间轴动画不会自动执行角色脚本的图片组选取。

| 时间（秒） | 对应段起点 | frame（示例画面索引） | active_hitboxes |
| --- | --- | --- | --- |
| `0` | 动作第 1 帧开始 | 0 | 5 |
| `3 / 60` | 第 4 帧开始，继续前摇 | 1 | 保持 5，无需额外关键帧 |
| `5 / 60` | 第 6 帧开始，有效段开始 | 2 | 7 |
| `8 / 60` | 第 9 帧开始，后摇开始 | 3 | 5 |
| `14 / 60` | 第 15 帧开始，继续后摇 | 4 | 保持 5 |
| `20 / 60` | 动作时间轴结束 | 保持最后画面 | 保持 5；行为状态负责退出 |

于是三段区间是 `[0, 5/60)`、`[5/60, 8/60)`、`[8/60, 20/60)`。不要把“第 6 帧开始”写成 `6/60`，否则时间轴设计就多了一帧前摇。

表格是制作数据的约定，**不声称未经运行验证就一定恰好产生 3 次 Area2D 有效采样**。首帧应用、物理查询更新和节点处理顺序可能影响采样边界，需用实际日志确认并固定工程执行顺序，不能通过随意改关键帧时间掩盖问题。

另建循环动画 `idle`：t=0 写 `Stand.active_hitboxes = 3` 和 `Sprite.frame = 0`，之后仅切换待机图片；其他动作同理。每个动画只写自己要使用的 HitState；交接时由管理器关闭其他状态。

**循环仅用于待机／持续移动等持续动作。** 普通攻击、受击、倒地过渡等按设计使用非循环动画；循环动画不发出正常结束信号，不能用它等待轻拳结束。参见资料 G4。

#### 多框招式的动画轨扩展

对于第 2、3.4 节的六框 HeavySlash，仍只有一条整组启停轨：

```text
VisualRoot/HitStateManager/HeavySlash:active_hitboxes
```

使用 Value／Discrete／Nearest，按招式阶段打入 `39 → 47 → 63 → 55 → 39`（前摇 → 近端有效 → 两框有效 → 尖端有效 → 后摇）；若两个攻击框始终同时开关，则简化为 `39 → 63 → 39`。这些都是布局相关的示例，不规定招式必须有几个有效阶段。

需要改变轮廓时，再分别添加 `HeavySlash/HurtHead:position`、`HeavySlash/AttackNear:position`、`HeavySlash/AttackTip:position` 等属性轨（前缀同上）。不同位置轨不意味着不同管理器或不同伤害段。若使用一个逻辑框下多个形状的版本，则可以驱动 `HeavySlash/Attackbox/TipShape:position`，但仍用三框布局的 `5 → 7 → 5` 控制区域启停。

继续遵守本节的单时间轴约定：脚本只负责动作开始／中断等边界，不逐帧与动画争写掩码。初帧、RESET 和中断清理应覆盖新增状态及必要的姿态属性，增删／重排独立框后重新计算全部掩码键值。

### 6.5 物理节拍、停止与首帧

本项目初版使用 AnimationPlayer 的 **Physics** 更新方式，与状态机、输入推进器都工作在物理节拍。`play()` 后调用 `advance(0)` 可立即应用当前时刻属性，但它不是一次额外的物理步进。参考资料 G1、G4、G5。

- 不要同时启用 Physics 自动更新，又每帧调用一次 `advance(delta)`；这会重复推进。
- 不要用 `_process()`／渲染帧数决定攻击有效段。
- 不要每个物理帧重复 stop／play 同一动作，否则会不断重启；只在状态进入或明确重启动作时播放。动作资源不配置自动 Next，不通过 queue 接连招；统一由行为状态选择下一动作。
- 不给战斗动画设置淡入淡出、Capture 或跨动作混合。当前方案一个动作一条权威时间轴，不让两套判定参与混合。
- 在统一的物理逻辑中安排动画更新、状态转换、输入消费、移动、碰撞采样和结算；验证完成信号在预期更新点被消费，而非无意多停留一帧。

后续若需要严格逐帧回放或回滚，可把 AnimationPlayer 改为 **Manual**，由唯一战斗时钟逐步调用 `advance(1.0 / 60.0)`；同时统一 Fray 状态更新与输入时钟。那是完整调度方案的变更，不能只切一个属性，也不能因为时间轴能手动推进就认为物理结果自动可确定重放。

### 6.6 正常结束、中断和 RESET

正常结束：AnimationPlayer 发出 `animation_finished` → 角色只记录完成标志 → FrayState 判断本次动作是否完成 → 进入下一合法状态。

被打断：安全结算阶段请求 Hurt／Guard／Knockdown → 当前状态退出时 `end_action()` 停止时间轴并清空当前框 → 目标状态 `begin_action()` → t=0 立即设置新动作完整判定。

必须同时处理这两条路径。**不能只在动画最后放一个“关攻击框”关键帧**，因为受击或取消会提前终止播放；也不要只 `stop()` 而假设 Area2D 自动恢复默认。停播不会代替游戏的判定清理。

RESET 用于编辑器基准姿态，不作为每次攻击结束时的游戏动作。若保留判定轨，把其基准值设为全部关闭；运行时由 idle 的 t=0 选择 Stand。不要从 RESET 开启某个攻击框，也不要让普通招式动画给所有其他 HitState 逐一写 0。

动画方法轨可通知表现事件，但伤害、防御、扣资源和投技锁定仍由游戏逻辑判定。若方法轨请求状态切换，记录请求、带动作代号，在安全阶段处理，避免正在更新动画轨时递归切换动画或生成碰撞修改。

### 6.7 命中停顿与取消窗口

命中停顿时要同时冻结动作时间轴、角色位移与需要冻结的状态逻辑。**只设置 `state_machine.active = false` 不会停止独立 AnimationPlayer。**

可在统一停顿控制器保存并设置 `animation_player.speed_scale = 0.0`，冻结时间进度，结束后恢复原值；不要用 stop 代替暂停，更不要在停顿中反复清空判定。推进器是否继续收集、何时消费、缓冲是否随真实时间过期，仍按第 7.3 节决定。停顿期间的重复接触由命中去重处理。

时间轴可维护一个游戏自定义的 `cancel_window_open` 属性，但它只表示“时间窗口打开”。是否真正取消还要判断当前动作、命中确认、目标类型和资源条件。进入／退出动作时显式恢复窗口默认值；不要让动画轨和状态脚本同时争写 `input_advancer.paused`。本指南最小轻拳示例不支持中途取消，因此只由状态脚本控制 paused。

### 6.8 为什么不只用 frame_changed 驱动框

画面可能一张图保持 4 个逻辑帧，其中只有最后 2 帧有攻击判定。以图片 `frame_changed` 作为唯一时钟就无法清楚表达这一情况；重用素材、追加无敌窗口也会把游戏规则绑死在图片索引上。

因此美术帧数和战斗帧数分开：SpriteFrames 管理“有哪些图”，AnimationPlayer 决定“图和判定分别在何时变化”。单独播放的火花、烟雾等非权威特效仍可使用独立 AnimatedSprite2D，不影响主角色动作时钟。
## 7. 输入与行为状态机

### 7.1 基础输入：项目设置配置按键，脚本桥接 Fray

**本项目的默认按键在 Godot「项目 → 项目设置 → 输入映射（Input Map）」中配置，不把所有键位硬编码在脚本里。玩家运行时改键则由设置菜单修改 InputMap，并自行保存用户配置，见第 7.7 节。** 两层映射的职责不同：

```text
键盘／手柄事件
    ↓ 项目设置 → 输入映射（Godot InputMap）
p1_left、p1_punch 等 action
    ↓ FrayInputMap.add_bind_action()：桥接名称，不重新指定物理键
FrayInput / FrayController 查询、Fray 输入事件与指令识别
    ↓ 游戏层把 p1_punch 映射为 punch 等语义请求
状态机 / 输入推进器
```

#### 7.1.1 在编辑器中设置实际键位

在**目标 Godot 工程**的输入映射页添加以下 action，再为它们添加输入事件。下面是起步用的示例键位，可以在编辑器里调整：

| Godot action | 示例键位 | 用途 |
| --- | --- | --- |
| `p1_left` | A | 向画面左侧移动 |
| `p1_right` | D | 向画面右侧移动 |
| `p1_down` | S | 蹲下／方向输入 |
| `p1_up` | W | 向上／跳跃方向输入 |
| `p1_punch` | J | 轻拳 |

本指南的跳跃缓冲示例复用 `p1_up`；若需要独立跳跃键，可在编辑器添加 `p1_jump`，再替换示例名称并加入桥接列表。双人同键盘另建 `p2_*` action 并绑定另一组键位。按需给 action 添加手柄按钮或轴事件；双手柄隔离另见下文。

这些默认设置随目标工程的 `project.godot` 保存。开发期间调整默认键位只改输入映射，不需要修改脚本里的 `KEY_A`、`KEY_J` 等常量；玩家运行时覆盖另存 `user://`，不回写项目文件。本文只说明配置方式，不表示已替你修改实际工程的输入映射。

#### 7.1.2 初始化时桥接到 FrayInputMap

Godot InputMap 和 FrayInputMap 不是同一张表；**仅在项目设置里添加 action，不会自动创建 Fray 输入**。使用 `FrayController`、`FraySequenceMatcher` 或 `FrayInputBuffer` 时，需要以下桥接。在对战初始化阶段、实例化角色之前调用一次；重复进入对战时先检查是否存在。

```gdscript
func register_p1_inputs() -> void:
    var actions: Array[StringName] = [
        &"p1_left", &"p1_right", &"p1_down", &"p1_up", &"p1_punch",
    ]
    for action in actions:
        if not InputMap.has_action(action):
            push_error("请先在项目设置 → 输入映射中创建 action: %s" % action)
            continue
        if not FrayInputMap.has_input(action):
            FrayInputMap.add_bind_action(action, action)
```

`add_bind_action(Fray输入名, Godot动作名)` 的两个名称可以不同，本文使用同名减少混淆。脚本只负责桥接和游戏规则，不再通过 `add_bind_key()` 重复设置这批键位。若初始化函数放在对战父节点的 `_ready()`，应在注册完成后再实例化／添加角色；不要假设父节点 `_ready()` 先于已在场景中的子角色执行。

迁移旧示例时，若同名 Fray 输入已经用 `add_bind_key()` 注册，上述存在性检查不会将它替换成 action 绑定。删除旧注册入口并重新运行工程；不要在战斗中直接删除／重建底层绑定，相关缓存风险见第 11.6 节。

角色仍通过 `FrayController.is_pressed()`、`is_just_pressed()`、`is_just_released()`、`get_axis()` 查询。第 7.2 节的 `punch_input = &"p1_punch"` 及输入事件处理无需改成直接判断物理键。

若某个模块只使用 Godot `Input.is_action_just_pressed()` 再手动调用 `InputAdvancer.buffer_press()`，它可以不经过 Fray 输入桥接，因为推进器接受的是游戏语义名。但本指南默认保持 Fray 输入事件链路；**不要把同一次按下同时从 Godot Input 和 Fray 事件重复投递给推进器。**

#### 7.1.3 双人和设备限制

默认 Controller.device 为 0，对应插件的键鼠／首个手柄基准设备约定；但当前设备枚举在仅有非 0 手柄时可能不轮询 0，热插拔接入不能只依赖这个默认值，详见第 7.7 节及专项指南第 3 节。当前 `FrayInputBindAction` 内部直接调用 `Input.is_action_pressed(action)`，忽略传入的 Fray 设备参数；`FrayInputBindKey` 同样不按这个参数隔离键盘。

- **双人同键盘：**使用 `p1_*`／`p2_*` 独立 action 和不同事件；只切换 Controller.device 不能隔离键盘。
- **双手柄：**不要把双方手柄事件都绑定到同一个接受所有设备的 action，再以为 Controller.device 会拆分它们。可以在项目输入映射中使用双方独立 action，并为手柄事件指定各自设备；即使如此，Fray 的 action 绑定仍读取 action 的聚合状态，不应把 Fray 事件的 device 当成原始事件来源证明。角色也必须使用各自输入名称。
- 若需要按 Fray 设备号统一查询同一套名称，应另行使用设备感知的手柄绑定／自定义适配层，并定义重连策略；这属于额外设备接入，不是要求所有键盘键位都回到脚本硬编码。

前进、后退、防御方向由实际左右输入与角色朝向换算。定义左右同时按下的规则，以及指令识别期间换边时方向如何解释，不要让插件猜测角色面向。

### 7.2 最小 Idle → LightPunch → Idle 示例

以下脚本依赖第 5 节的播放入口，以及第 6 节建好的 `idle`／`light_punch` 动画和帧图组。**状态不再计数到第 6 帧才开框；掩码关键帧只维护在 AnimationPlayer 中。**

```gdscript
# res://fighters/common/idle_state.gd
extends FrayState

var actor

func _ready_impl(context: Dictionary) -> void:
    actor = context["actor"]

func _enter_impl(_args: Dictionary) -> void:
    actor.begin_action(&"idle")

func _exit_impl() -> void:
    actor.end_action()
```

```gdscript
# res://fighters/common/light_punch_state.gd
extends FrayState

var actor
var input_advancer: FrayBufferedInputAdvancer
var action_token: int = -1

func _ready_impl(context: Dictionary) -> void:
    actor = context["actor"]
    input_advancer = context["input_advancer"]

func _enter_impl(_args: Dictionary) -> void:
    actor.attack_instance_id += 1
    actor.attack_segment_id = 0
    input_advancer.paused = true  # 本例不开放中途取消
    action_token = actor.begin_action(&"light_punch")

func _is_done_processing_impl() -> bool:
    return actor.is_action_finished(action_token)

func _exit_impl() -> void:
    actor.end_action()           # 正常结束、受击、取消都要清理
    input_advancer.paused = false
```

把下面的成员和方法加入第 5 节角色脚本，并在该脚本 `_ready()` 最后调用 `_initialize_behavior()`。不要再定义第二个 `_ready()`。如果素材缺失导致 begin_action 返回 -1，应在开发阶段修复资源配置；示例不把播放失败当作攻击完成。

```gdscript
const IdleStateScript = preload("res://fighters/common/idle_state.gd")
const LightPunchStateScript = preload("res://fighters/common/light_punch_state.gd")

@export var punch_input: StringName = &"p1_punch"
@onready var controller: FrayController = $Controller
@onready var state_machine: FrayStateMachine = $StateMachine
@onready var input_advancer: FrayBufferedInputAdvancer = $StateMachine/InputAdvancer

func _initialize_behavior() -> void:
    state_machine.advance_mode = FrayStateMachine.AdvanceMode.PHYSICS
    input_advancer.advance_mode = FrayBufferedInputAdvancer.AdvanceMode.PHYSICS
    input_advancer.max_buffer_time = 5.0 / 60.0  # 秒，约 5 个 60 Hz 帧
    input_advancer.paused = false

    var root := (FrayCompoundState.builder()
        .add_state(&"Boot", FrayState.new())
        .start_at(&"Boot")
        .add_state(&"Idle", IdleStateScript.new())
        .add_state(&"LightPunch", LightPunchStateScript.new())
        .transition_press(&"Idle", &"LightPunch", {"input": &"punch"})
        .transition(&"LightPunch", &"Idle", {
            "auto_advance": true,
            "switch_mode": FrayStateMachineTransition.SwitchMode.AT_END,
        })
        .build()
    )
    state_machine.initialize({"actor": self, "input_advancer": input_advancer}, root)
    state_machine.active = true
    state_machine.goto(&"Idle")  # Boot → Idle，显式执行初始待机的进入逻辑。
    FrayInput.input_detected.connect(_on_input_detected)

func _on_input_detected(event: FrayInputEvent) -> void:
    if controller.disabled or event.device != controller.device:
        return
    if event.input == punch_input and event.is_just_pressed():
        input_advancer.buffer_press(&"punch")
```

`Boot` 是一次性的空启动状态；当前初始化路径不会对普通初始叶状态调用进入逻辑，所以通过公开 `goto()` 从 Boot 进入 Idle，见第 11.8 节。这不是每帧强制切换。

`initialize(context, root)` 会把 context 字典设为只读，但其中的 actor 引用仍可用于调用角色行为。每个角色创建自己的运行状态实例，不共享 actor、动作代号等可变状态。

若素材使用命名 AnimationLibrary，播放键会形如 movement/walk；应在 begin_action 增加播放键到 SpriteFrames 组名的映射，不能直接假设两个名称相同。

上例把物理输入名 `p1_punch` 映射为语义名 `punch`。`transition_press()` 不会自动监听键盘，必须转发输入。一次物理更新可能同时发生动画结束、自动返回待机和消费下一次攻击输入；正式对战应统一转换顺序和每帧转换次数。

受击状态也应在进入时播放自己的 `hurt` 动画、退出时执行 end_action。强制受击由结算逻辑请求 `state_machine.goto()`；不要让受击等待攻击的正常动画结束。`AT_END` 仅用于正常完成路线，不是强制打断机制。
### 7.3 缓冲不是永久保存失败输入

`FrayBufferedInputAdvancer` 的当前实现会取出队头输入并尝试推进，失败后也不会放回队列。

- 不可取消阶段若希望保留短期预输入，应设置 `paused = true`，在合法窗口再恢复消费。
- `paused` 只暂停输入尝试，不冻结状态机、动画，也不停止输入继续入队。
- 缓冲以 `Time.get_ticks_msec()` 计时；停顿期间仍会过期。`max_buffer_time` 单位是**秒**。
- 命中停顿若要保留“剩余动作帧意义上的缓冲”，需实现游戏时钟策略，不能只暂停推进器。
- `FrayInputBuffer` 是另一套标注为实验性的输入缓冲／窗口工具，不等同于 `FrayBufferedInputAdvancer`。本指南不要求再叠加它。

### 7.4 FrayInputBuffer：可选的实验性缓冲／窗口节点

**对本项目的核心格斗输入，默认不叠加这个节点。** 不使用 `FrayInputBuffer` 不等于不要输入缓冲；第 7.2～7.3 节使用的 `FrayBufferedInputAdvancer` 是另一套实现。以下用法用于理解接口、简单原型或修正实现后的验证，不代表当前节点已满足正式对战需求。

| 对比项 | `FrayInputBuffer` | `FrayBufferedInputAdvancer` |
| --- | --- | --- |
| 角色 | 记住按下／检测时间窗口，由游戏代码查询 | 保存输入请求并尝试推进父状态机 |
| 输入来源 | `set_buffer`／`set_window` 后监听 `FrayInput.input_detected` | 游戏代码显式调用 `buffer_press`／`buffer_sequence` |
| 保存形式 | 每个输入一个标记，不是完整事件队列 | 请求队列；尝试失败也会出队 |
| 时长单位 | `duration` 为毫秒 | `max_buffer_time` 为秒 |
| 自动执行动作 | 不会，必须自行决定和执行 | 尝试调用状态机 `advance()` |
| 时钟 | 真实毫秒时间 | 真实毫秒时间 |

#### 7.4.1 Buffer：提前按下，稍后消费

例如落地前 50ms 按下跳跃，若配置了 100ms 缓冲，落地时可以读取这个记录并执行跳跃。注册后不需要每帧手动往该节点投递按键。

先完成第 7.1 节的项目输入映射和 Fray 桥接，再给角色添加一个挂载 `FrayInputBuffer` 脚本的 Node 子节点，命名为 `InputBuffer`。它不必作为状态机的子节点。下面是**简单跳跃原型的接入片段，不是完整移动控制器，也不应绕过正式角色的状态机跳跃条件**：

```gdscript
@onready var input_buffer: FrayInputBuffer = $InputBuffer

# 在角色现有 _ready() 中调用，不要再定义第二个 _ready()。
func setup_jump_buffer() -> void:
    # 当前实现存在设备传递问题；这个最小示例只使用默认设备 0。
    input_buffer.device = 0
    input_buffer.set_buffer(&"p1_up", 100)  # 毫秒，不是 0.1 秒

# 在现有物理更新中调用；这里不包含重力和 move_and_slide()。
func try_buffered_jump() -> void:
    if is_on_floor() and input_buffer.is_press_buffered(&"p1_up"):
        velocity.y = -400.0
        # 确实执行成功后消费，避免有效期内反复触发。
        input_buffer.reset_buffer(&"p1_up")
```

接入状态机时，应在跳跃转换确实被接受后再清除；若动作未执行且希望稍后重试，就不要提前消费。跳跃资格、受击限制和是否允许连跳仍由游戏层判断。

主要接口：

- `set_buffer(input, duration, can_reset)`：配置并监听该输入；通常初始化一次，不要每帧反复配置。
- `is_press_buffered(input)`：查询当前记录是否存在且未过期；查询本身不消费输入。
- `reset_buffer(input)`：清掉本次记录，保留配置和后续监听。
- `is_pressed_or_buffered(input)`：缓冲有效**或当前持续按住**就返回 true。即使 reset 后仍可能因按住返回 true，不适合作为默认的一次性出拳检测。
- `erase_buffer(input)`／`clear_buffer()`：移除一项／全部缓冲配置，不等于仅消费一次记录；当前信号清理问题见第 7.5 节。

`can_reset` 是“何时自动清掉已有记录”的回调，不是“何时允许跳跃”。直接传入 `is_on_floor` 可能使输入在动作消费前就被清除，结果取决于节点更新顺序。简单方案优先使用成功执行后的显式 `reset_buffer()`。

#### 7.4.2 Window：先开时间窗口，再检测按下

Window 的设计意图与 Buffer 相反：Buffer 记住先发生的按键，Window 先记录一个开始时间，再检查后续按键是否落在有效期内。例如离开平台后短暂允许起跳。

以下只展示接口调用顺序；**当前 Window 有结果覆盖、过期与重启语义问题，不要把这段当成可直接上线的土狼时间实现。**

```gdscript
# 初始化（p1_up 已通过第 7.1 节桥接）：
input_buffer.set_window(&"p1_up", 100)

# 检测到从平台离开的那一刻，仅调用一次：
input_buffer.start_window(&"p1_up")

# 后续更新查询；动作是否允许、是否已消费，需由游戏逻辑判断：
var pressed_in_window := input_buffer.is_press_in_window(&"p1_up")
```

`set_window(input, duration, can_start, can_end)` 也接受自动开窗／结束回调。但 `can_start` 只要持续为 true 就会每个物理更新重设开始时间，并不是仅在 false → true 时开一次窗。不要直接用“当前不在地面”这样的持续状态实现一次性的离地宽限期。`is_press_in_window()` 也不是“窗口当前仍然开放”的查询接口。

### 7.5 FrayInputBuffer 当前实现的使用问题

依据 `src/input/input_buffer.gd` 静态检查；下面区分源码可见行为与尚需运行验证的生命周期风险，本文不修改插件源码。

1. **设备值未传入内部对象。** 节点导出了 `device`，但 `set_buffer()`／`set_window()` 没有将它赋给内部 `_InputBuffer.device`／`_InputWindow.device`。内部默认仍为 0，事件却按内部 device 筛选。因此只改节点 Inspector 的设备号不足以支持其他设备；`is_pressed_or_buffered()` 还可能混合“设备 0 的缓冲”和“节点指定设备的实时按住状态”。修正时需要处理创建和运行时设备切换两种情况。
2. **Buffer 是单个标记，不是输入历史。** 内部检测要求 `not is_pressed`；已有记录时再次按下不会入队，也不会刷新开始时间。不要依赖它记录连按次数、完整顺序或处理普通拳／必杀技优先级。
3. **Window 结果会被其他事件覆盖。** 同设备的任何后续事件，只要不满足窗口按下条件就会把 `is_pressed` 置 false；可能包括其他按键、释放或按住产生的 echo，甚至同一物理帧内的后续事件。一次有效按下不一定能保留到角色查询时。
4. **Window 缺少完整的过期／重启处理。** `is_press_in_window()` 只返回标记，物理更新没有按时长自动结束窗口；若没有后续事件或清理回调，true 可能超过预期时间仍保留。`start_window()` 只更新时间，不清旧标记；时间判断也没有显式验证 `time_pressed >= time_started`。不要把注释中“到期自动结束”视为当前已经实现的保证。
5. **自动回调的语义与执行顺序容易误用。** `can_start` 持续为 true 会连续续窗；`can_end` 仅在 window.is_pressed 为 true 时才调用，不是无条件关闭一个尚未收到按键的窗口。`can_reset` 则可能在角色消费前清掉缓冲。当前没有公开的 `end_window()` 或“读取并消费窗口结果”的原子接口。
6. **真实时间过期，不随战斗帧冻结。** Buffer 使用 `Time.get_ticks_msec()`；即使暂停节点的处理，查询过期仍取决于真实时间。命中停顿、慢动作或回放若要求以模拟帧计时，必须另建时钟／缓冲策略，不能仅停止角色动画。
7. **删除配置时没有显式断开信号。** `erase_buffer/window` 和 `clear_buffer/window` 只改字典，未配对执行 `input_detected.disconnect()`，也没有节点退出时统一清理的实现。内部对象和回调的实际存活情况需运行验证；反复建立／删除配置时应检查残留连接，不把清空字典当成已验证的完整解绑方案。

使用时还应保证 Fray 自动加载已就绪、输入名称已经注册、先配置再查询。输入名称不存在时 `_WARN_INPUT_DOES_NOT_EXIST()` 只是警告，调用方并不会自动创建 Godot action 或对应 Fray 绑定。

### 7.6 本项目的缓冲选择

- **先实现最小战斗闭环：**使用第 7.2 节的 `FrayBufferedInputAdvancer`，按第 7.3 节控制消费窗口，不必再串联 `FrayInputBuffer`，避免同一次输入被重复投递或消费。 动作增加后改用第 7.8 节的输入映射表与转移规则表，不必扩展成长串状态判断。
- **只做简单单机跳跃原型：**可以在明确上述限制后试用 Buffer；Window 建议修正并测试后再使用。即使输入来源改成项目设置的 action，也不会自动修复该节点内部的问题。
- **正式格斗规则需要精确预输入：**建议游戏层保存“请求类型、产生帧、有效帧数、消费状态”，明确失败是否保留、招式优先级和命中停顿是否扣除有效帧，执行成功后消费。Fray 可继续承担输入查询、指令识别或状态机职责，不必为此放弃整套插件。

### 7.7 设置功能：玩家自定义键盘与手柄按键

完整方案见同目录 **`Fray_键盘与手柄自定义按键接入指南.md`**，包含原始输入捕获、键位冲突、InputMap 更新代码、用户配置保存／加载、设备认领、热插拔和验收清单。

本项目采用：**项目 Input Map 定义默认值 → 玩家设置覆盖运行时 InputMap → 保持 Fray action 桥接及逻辑名称不变**。例如把 `p1_punch` 的键盘事件由 J 改为 K，不修改状态机中的 `punch` 或连招定义，也不重复删除／创建 Fray 绑定。

接入要点：

- 每名玩家使用 `p1_*`／`p2_*` action。双手柄事件填入认领后的实际 device ID；未分配手柄时不添加事件，不能用匹配所有设备的 `-1` 代替“没有手柄”。
- `FrayInputBindAction` 忽略 Fray device，读取 action 聚合状态。双方隔离靠玩家 action 和实际手柄事件；Fray 事件入口还需过滤一个选定轮询通道，避免重复投递。设备枚举缺口及不改插件的兼容办法见专项指南第 3 节。
- 设置弹窗捕获原始键盘／手柄按钮／轴事件，键盘区分 physical_keycode 与 keycode；轴记录轴号、方向和死区。修改一个槽位后，从完整配置重建 action，保留副键与另一设备类别的绑定。
- 档案用 ConfigFile 等存入 `user://`，保存版本、键位描述和死区，不持久化本次运行的手柄 ID。应用前验证配置；取消、恢复默认和保存失败都有明确行为。
- 改键期间同时关闭 Controller 查询和事件适配层，阻止 matcher／advancer 收集菜单输入。应用前等待旧／新键释放；恢复物理采样后清理旧缓冲、指令历史和蓄力，再开放战斗输入。仅设置 `input_advancer.paused = true` 不够。

专项指南也列出直接 Fray 手柄绑定的限制：当前 `FrayInputBind.get_strength(device)` 未将 device 传给实现方法，设备非 0 时强度可能与按下检测不一致。因此不要未经修复／测试就把直接绑定路线当成完整的双手柄设置方案；本文推荐 action 桥接。

### 7.8 基本输入与序列招式：分开识别、统一仲裁、统一推进

**不需要把角色脚本写成一长串状态名 `if/elif`，也不需要为普通攻击和必杀技分别建一个 Advancer。** 本节采用“分开识别、统一仲裁、统一推进；持续输入保留状态查询”的方案，使用游戏层脚本扩展，不修改 `addons/fray/src/`。

```text
键盘／手柄 → Godot action → Fray 输入状态
                  ↓ 每玩家筛选、方向归一化
     ┌────────────┼──────────────────┐
 普通按下／释放候选  FraySequenceMatcher    持续方向／防御状态
     └────────────┬──────────┘              ↓
           同次触发的候选组               移动与状态条件查询
                  ↓ 原始时间戳、窗口、合法性、候选优先级
           游戏层统一仲裁（每组最多选择一个）
                  ↓ buffer_press() 或 buffer_sequence()
           唯一 FrayBufferedInputAdvancer
                  ↓ advance(输入字典)
           转移规则表 + prereqs → 目标 FrayState
```

普通输入和序列输入**分开识别**，因为前者是按下／释放边沿，后者需要方向历史和时间窗口；但是两者必须**统一仲裁和消费**，否则最后一次 P 可能既触发普通拳又触发 236P。Advancer 的两个接口共用一个队列，不等于插件会自动解决这个竞争。

本节代码的明确策略：

| 输入／情况 | 处理方式 |
| --- | --- |
| 轻拳、重拳的按下／释放 | 生成一次动作候选，不在按住期间重复入队 |
| 236P 的最后一次 P | 将序列候选与这次 P 的普通拳候选放进同一组 |
| 指令合法且资源足够 | 序列候选优先，整组消费，普通拳不残留 |
| 指令不合法／气量不足 | 尝试该组普通拳；普通拳也不合法则丢弃该组 |
| 消费窗口关闭 | 保留整组直到窗口开放或按原始时间过期 |
| 左右移动、按住下、按住防御 | 查询持续状态；方向变化也可供 matcher 观察，但不每帧生成移动请求 |

这里采用**消费时判断合法性**，不是输入发生时立即丢掉暂时不能执行的必杀技。已匹配的候选不会因为排队而重新匹配；状态、蹲姿、气量和取消窗口则在消费时查询。如果项目需要按下瞬间的姿态快照，需另加请求上下文，不能从当前状态反推。

#### 7.8.1 接入范围与准备

下面是一套**替换第 7.2 节行为接入代码**的扩展示例，而不是在旧 `_initialize_behavior()`／旧信号连接之外再加一套。保留第 5 节角色动画入口；保留第 7.2 节的 `punch_input`、`controller`、`state_machine` 成员；`input_advancer` 改用下方游戏子类的类型声明。原 Idle／LightPunch 专用脚本不再用于本例，改用下方的可配置动作状态。

- 节点结构仍是 `Fighter/StateMachine/InputAdvancer`，推进器必须是状态机的直接子节点。给原 InputAdvancer 换挂第 7.8.2 节的游戏子类脚本，它仍继承 FrayBufferedInputAdvancer；不额外创建第二个推进器。
- 预先准备 `idle`、`light_punch`、`crouch_punch`、`heavy_punch`、`special` 的 AnimationPlayer 动画、同名 SpriteFrames 组及完整 HitState；后四个是非循环攻击。表中的名称不是插件自带资源。
- 按第 7.1 节桥接 `p1_left`、`p1_right`、`p1_up`、`p1_down`、`p1_punch` 和新增的 `p1_heavy`；P2 使用对应 `p2_*`。Controller.device 按第 7.7 节选定有效轮询通道。改键不改变这些逻辑名称。
- 示例包含站立／蹲姿轻拳、重拳、236P 和简单气量消耗，不包含完整移动、跳跃或命中结算。`grounded` 依赖实际移动／地面检测；`facing_sign` 必须由角色朝向系统更新为 +1（朝右）或 -1（朝左），不是插件自动提供的值。
- 使用平铺的根状态图，不同时执行 travel，也不在输入分发到推进器之间切换状态。候选预检调用公开 `root.get_next_state()`；嵌套状态机需要另行实现沿活动状态链的合法性查询，不能原样套用。
- 暂未制作新增动作时，从定义表和规则表同时删去相应行，不要用空白 FrayState 假装已经实现招式。

#### 7.8.2 可复用动作状态：不用每个招式复制生命周期代码

新建**游戏脚本** `res://fighters/common/timeline_action_state.gd`：

```gdscript
extends FrayState

var actor
var animation_name: StringName
var is_attack: bool
var meter_cost: int
var action_token: int = -1

func _init(animation: StringName = &"idle", attack: bool = false, cost: int = 0) -> void:
    animation_name = animation
    is_attack = attack
    meter_cost = cost

func _ready_impl(context: Dictionary) -> void:
    actor = context["actor"]

func _enter_impl(_args: Dictionary) -> void:
    actor.special_cancel_open = false
    actor.hit_confirmed = false
    actor.set_input_window(not is_attack)
    # 只有真实进入才扣气；条件查询和候选预检都不扣气。
    actor.special_meter -= meter_cost
    if is_attack:
        actor.attack_instance_id += 1
        actor.attack_segment_id = 0
    action_token = actor.begin_action(animation_name)

func _is_done_processing_impl() -> bool:
    # Idle 可以随时接受输入；攻击只在对应动作确实结束后完成。
    return not is_attack or actor.is_action_finished(action_token)

func _exit_impl() -> void:
    actor.set_input_window(false)
    actor.special_cancel_open = false
    actor.hit_confirmed = false
    actor.end_action()
```

进入攻击时关闭消费窗口；普通输入和指令候选仍被识别并保存在游戏层候选组队列，正常结束回到 Idle 后再选择一个请求交给推进器。气量下限由对应转移的 prereqs 保证；外部强制 goto 到付费招式必须自行检查资源，不应绕过这一约定。每个状态、每个角色都分别 `.new()`，不共享可变状态资源。蹲拳只是攻击动画不同，其待机蹲姿与移动仍需独立完善。

再新建游戏脚本 `res://fighters/common/empty_tick_transition.gd`，用于不吞掉玩家输入的自动完成边：

```gdscript
extends FrayStateMachineTransition

func _accepts_impl(sm_input: Dictionary) -> bool:
    return sm_input.is_empty()
```

这是继承插件公开基类的**游戏扩展**，不是修改插件。当前基础 `FrayStateMachineTransition` 默认接受所有字典；若把它用于“攻击结束 → Idle”，它也可能把 Advancer 传来的攻击请求当成这条边已成功消费。这里限定为状态机自动更新传入的空字典，玩家按键／序列字典不能借这条边返回 Idle。

还需新建游戏脚本 `res://fighters/common/coordinated_input_advancer.gd`：

```gdscript
extends FrayBufferedInputAdvancer

var before_advance: Callable

func _physics_process(delta: float) -> void:
    if advance_mode != AdvanceMode.PHYSICS:
        return
    if before_advance.is_valid():
        before_advance.call()
    super(delta)
```

它只在原推进器的 Physics 回调前增加一个游戏层钩子，然后调用父类原逻辑；不调用私有 `_advance()`，也不另建一套状态推进逻辑。钩子在消费前完成识别、候选选择与唯一入队，避免选择后又等到另一个异步回调才消费。不要再从其他脚本直接调用该推进器的 buffer 方法。

#### 7.8.3 角色接入：一张输入映射表、一张转移规则表

以下成员与方法加入 Fighter，并**替换**第 7.2 节同名初始化和输入回调；不要重复声明前述已有成员。第 5 节 `_ready()` 最后仍只调用一次 `_initialize_behavior()`。

```gdscript
const TimelineActionStateScript = preload("res://fighters/common/timeline_action_state.gd")
const EmptyTickTransitionScript = preload("res://fighters/common/empty_tick_transition.gd")
const CoordinatedAdvancerScript = preload("res://fighters/common/coordinated_input_advancer.gd")
const UnifiedInputScript = preload("res://fighters/common/unified_fighter_input.gd")

# 替换旧的 input_advancer 声明，不要重复定义。
@onready var input_advancer: CoordinatedAdvancerScript = $StateMachine/InputAdvancer

@export var left_input: StringName = &"p1_left"
@export var right_input: StringName = &"p1_right"
@export var up_input: StringName = &"p1_up"
@export var down_input: StringName = &"p1_down"
@export var heavy_input: StringName = &"p1_heavy"

var facing_sign: int = 1  # 由实际朝向系统维护。
var special_meter: int = 100
const SPECIAL_COST := 50

var accept_gameplay_input: bool = true
var special_cancel_open: bool = false
var hit_confirmed: bool = false
var _input_window_open: bool = true
var _unified_input: UnifiedInputScript

func _initialize_behavior() -> void:
    state_machine.active = false
    state_machine.advance_mode = FrayStateMachine.AdvanceMode.PHYSICS
    input_advancer.advance_mode = FrayBufferedInputAdvancer.AdvanceMode.PHYSICS
    input_advancer.max_buffer_time = 5.0 / 60.0
    input_advancer.clear_buffer()
    input_advancer.paused = true

    var definitions: Array[Dictionary] = [
        {"state": &"Idle", "animation": &"idle", "attack": false},
        {"state": &"LightPunch", "animation": &"light_punch", "attack": true},
        {"state": &"CrouchPunch", "animation": &"crouch_punch", "attack": true},
        {"state": &"HeavyPunch", "animation": &"heavy_punch", "attack": true},
        {"state": &"Special", "animation": &"special", "attack": true, "cost": SPECIAL_COST},
    ]
    var builder := FrayCompoundState.builder()
    # 当前 initialize 不保证调用初始叶状态的进入逻辑；用空 Boot 再显式进入 Idle。
    builder.add_state(&"Boot", FrayState.new()).start_at(&"Boot")
    for definition in definitions:
        builder.add_state(definition["state"], TimelineActionStateScript.new(
            definition["animation"], definition["attack"], definition.get("cost", 0)))

    builder.register_conditions({
        "grounded": func() -> bool: return is_on_floor(),
        "crouching": func() -> bool: return controller.is_pressed(down_input),
        "has_special_meter": func() -> bool: return special_meter >= SPECIAL_COST,
        "can_special_cancel": func() -> bool:
            return special_cancel_open and hit_confirmed,
    })

    # 同一 punch 请求由条件选择蹲拳或站拳；无需在输入回调里判断状态。
    var rules: Array[Dictionary] = [
        {"from": &"Idle", "to": &"CrouchPunch", "kind": "press",
            "config": {"input": &"punch", "prereqs": PackedStringArray(["grounded", "crouching"])}},
        {"from": &"Idle", "to": &"LightPunch", "kind": "press",
            "config": {"input": &"punch", "prereqs": PackedStringArray(["grounded", "!crouching"])}},
        {"from": &"Idle", "to": &"HeavyPunch", "kind": "press",
            "config": {"input": &"heavy", "prereqs": PackedStringArray(["grounded"])}},
        {"from": &"Idle", "to": &"Special", "kind": "sequence",
            "config": {"sequence": &"236P", "prereqs": PackedStringArray(["grounded", "has_special_meter"])}},
        {"from": &"LightPunch", "to": &"Special", "kind": "sequence",
            "config": {"sequence": &"236P", "prereqs": PackedStringArray(["grounded", "has_special_meter", "can_special_cancel"])}},
    ]
    for rule in rules:
        var config: Dictionary = rule["config"].duplicate(true)
        config["switch_mode"] = FrayStateMachineTransition.SwitchMode.IMMEDIATE
        match rule["kind"]:
            "press":
                builder.transition_press(rule["from"], rule["to"], config)
            "sequence":
                builder.transition_sequence(rule["from"], rule["to"], config)

    for definition in definitions:
        if definition["attack"]:
            builder.transition(definition["state"], &"Idle", {
                "auto_advance": true,
                "switch_mode": FrayStateMachineTransition.SwitchMode.AT_END,
            }, EmptyTickTransitionScript.new())

    state_machine.initialize({"actor": self, "input_advancer": input_advancer}, builder.build())
    state_machine.active = true
    state_machine.goto(&"Idle")  # Boot → Idle：执行真正的进入逻辑，开始待机动画。
    _unified_input = UnifiedInputScript.new(self)
    input_advancer.before_advance = _unified_input.step
    if not FrayInput.input_detected.is_connected(_on_input_detected):
        FrayInput.input_detected.connect(_on_input_detected)

# 全局事件只进这个入口；此处不直接向 Advancer 投递，也不直接 matcher.read()。
func _on_input_detected(event: FrayInputEvent) -> void:
    _unified_input.capture(event)

func set_input_window(open: bool) -> void:
    _input_window_open = open
    input_advancer.paused = not open or not accept_gameplay_input or controller.disabled

# 动画中的取消窗口方法轨调用；命中结算层负责设置 hit_confirmed。
func set_special_cancel_window(open: bool) -> void:
    special_cancel_open = open
    set_input_window(open)

# 设置菜单／断线时先关闭入口；恢复前仍须执行 7.7 节的中立等待与历史清理。
func set_gameplay_input_enabled(enabled: bool) -> void:
    accept_gameplay_input = enabled
    input_advancer.clear_buffer()
    if _unified_input != null:
        _unified_input.reset_history()
    set_input_window(_input_window_open)
```

这里的 `match kind` 只是规则类型的固定分派，不会随着新增 20 个招式而增长。新增普通招式通常只增加状态定义、输入映射和规则行；同输入的站／蹲／空中版本使用不同 `prereqs`。规则很多时可把表移到游戏层 Resource 或独立构建器脚本，Fray 接口不变。

条件 Callable 必须**无参数、返回 bool、无副作用**：只查询地面、资源、窗口等状态，不在条件中扣气、播放动画或切换状态。资源消耗应由成功进入目标状态后的游戏逻辑执行一次。`prereqs` 全部为真才允许转移；同一根状态注册的 `!crouching` 是已注册条件的取反，不是另建一个带感叹号的条件名称。

统一入口同时识别按下和释放；释放只会进入设置了 `is_triggered_on_release = true` 的按键规则，其他情况下候选预检不通过，不向推进器投递。不要把 Advancer 生成的 `time_held` 当成真实长按时长，见第 11.4 节。

本例在**消费请求时**查询当前蹲姿，而不是保存按下瞬间的蹲姿快照。若玩法要求“蹲下时预输入的拳始终是蹲拳”，应在游戏输入适配层将它归一为独立语义请求，或实现带上下文快照的自定义请求层；不要误以为改用规则表就自动保存了输入上下文。

#### 7.8.4 游戏层统一入口：识别分开、同次触发归组、消费时仲裁

新建 `res://fighters/common/unified_fighter_input.gd`。它是每个角色独立持有的 RefCounted，不需要再加场景节点。下面的 236P 示例采用“每物理步先采样一个八方向状态，再处理本步按钮边沿”的固定规则；左右／上下同时按下均中立。不要再额外把 Fray 的斜方向复合事件喂给它，否则会重复计数。

```gdscript
extends RefCounted

const DIRECTION_NAMES := {
    Vector2i(-1, -1): &"up_back", Vector2i(0, -1): &"up", Vector2i(1, -1): &"up_forward",
    Vector2i(-1, 0): &"back", Vector2i(0, 0): &"", Vector2i(1, 0): &"forward",
    Vector2i(-1, 1): &"down_back", Vector2i(0, 1): &"down", Vector2i(1, 1): &"down_forward",
}

var actor
var _press_routes: Dictionary
# rank 是游戏层候选优先级，数值越小越先尝试，不是 Fray 转移的 priority。
var _sequence_specs: Dictionary = {&"236P": {"rank": 0, "trigger": &"punch"}}
var _tree: FraySequenceTree
var _matcher: FraySequenceMatcher
var _events: Array[FrayInputEvent] = []
var _groups: Array[Dictionary] = []
var _matched: Array[StringName] = []
var _direction: StringName = &""
var _direction_started: int = 0
var _last_facing: int = 0

func _init(fighter) -> void:
    actor = fighter
    _press_routes = {actor.punch_input: &"punch", actor.heavy_input: &"heavy"}
    _tree = FraySequenceTree.new()
    _tree.add(&"236P", FraySequenceBranch.builder()
        .first(&"down").then(&"down_forward", 200)
        .then(&"forward", 200).then(&"punch", 200).build())
    reset_history()

func _enabled() -> bool:
    return actor.accept_gameplay_input and not actor.controller.disabled

func capture(raw: FrayInputEvent) -> void:
    if not _enabled() or raw.device != actor.controller.device:
        return
    if raw.is_echo() or raw.is_virtually_pressed():
        return
    var name := StringName(_press_routes.get(raw.input, &""))
    if name.is_empty():
        return  # 方向不从全局回调逐个转发，而在 step() 统一采样。
    var event := SemanticEvent.new(name, raw.is_pressed(), raw.time_pressed, raw.time_detected)
    event.device = raw.device
    event.physics_frame = raw.physics_frame
    event.process_frame = raw.process_frame
    _events.append(event)

func _new_matcher() -> void:
    _matcher = FraySequenceMatcher.new()
    _matcher.initialize(_tree)
    _matcher.match_found.connect(_on_match_found)
    _matched.clear()

func reset_history() -> void:
    _events.clear()
    _groups.clear()
    _direction = &""
    _last_facing = 0
    _new_matcher()  # 不依赖旧 matcher.initialize() 完整清除历史。

func _on_match_found(name: StringName) -> void:
    if _sequence_specs.has(name) and not _matched.has(name):
        _matched.append(name)  # 这里只收集结果，不能直接 buffer_sequence()。

func _sample_direction(now: int) -> void:
    var facing: int = 1 if actor.facing_sign >= 0 else -1
    if facing != _last_facing:
        # 本例换边就中断未完成指令；已形成的候选组保持原有生命周期。
        _new_matcher()
        _direction = &""
        _last_facing = facing
    var x := int(actor.controller.is_pressed(actor.right_input)) - int(actor.controller.is_pressed(actor.left_input))
    var y := int(actor.controller.is_pressed(actor.down_input)) - int(actor.controller.is_pressed(actor.up_input))
    var next_direction := StringName(DIRECTION_NAMES[Vector2i(x * facing, y)])
    if next_direction == _direction:
        return
    if not _direction.is_empty():
        _matcher.read(SemanticEvent.new(_direction, false, _direction_started, now))
    _direction = next_direction
    _direction_started = now
    if not _direction.is_empty():
        _matcher.read(SemanticEvent.new(_direction, true, now, now))
    # 本例只支持以按钮结尾的指令；方向变化本身不生成动作请求。
    _matched.clear()

func _collect_group(event: FrayInputEvent) -> void:
    _matched.clear()
    _matcher.read(event)  # read() 同步触发 match_found，先收集指令再生成普通候选。
    var candidates: Array[Dictionary] = []
    for name in _matched:
        var spec: Dictionary = _sequence_specs[name]
        if spec["trigger"] == event.input:
            candidates.append({"kind": "sequence", "name": name, "rank": spec["rank"]})
    candidates.append({"kind": "press", "name": event.input,
        "pressed": event.is_pressed(), "rank": 100})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["rank"] != b["rank"]:
            return a["rank"] < b["rank"]
        return String(a["name"]) < String(b["name"]))
    _groups.append({"time_stamp": event.time_detected, "candidates": candidates})

func _request(candidate: Dictionary) -> Dictionary:
    if candidate["kind"] == "sequence":
        return {"sequence": candidate["name"]}
    return {"input": candidate["name"], "is_pressed": candidate["pressed"]}

func step() -> void:
    if not _enabled():
        reset_history()
        actor.input_advancer.clear_buffer()
        actor.input_advancer.paused = true
        return
    var now := Time.get_ticks_msec()
    _sample_direction(now)
    # 同时按钮采用时间戳、语义名、按下先于释放的稳定顺序，不依赖信号连接顺序。
    _events.sort_custom(func(a: FrayInputEvent, b: FrayInputEvent) -> bool:
        if a.time_detected != b.time_detected:
            return a.time_detected < b.time_detected
        if a.input != b.input:
            return String(a.input) < String(b.input)
        return a.is_pressed() and not b.is_pressed())
    for event in _events:
        _collect_group(event)
    _events.clear()

    var ttl_msec: float = actor.input_advancer.max_buffer_time * 1000.0
    # 即使窗口关闭也回收过期组，不无限积累；原始时间从未因换队列而刷新。
    for i in range(_groups.size() - 1, -1, -1):
        if now - int(_groups[i]["time_stamp"]) > ttl_msec:
            _groups.remove_at(i)
    if not actor.state_machine.active or actor.input_advancer.paused:
        return
    if not actor.input_advancer.get_buffer().is_empty():
        push_error("统一入口之外发生了重复入队，请移除其他 buffer 调用")
        actor.input_advancer.paused = true
        return

    while not _groups.is_empty():
        var group: Dictionary = _groups.pop_front()
        for candidate in group["candidates"]:
            # 无副作用预检；使用同一状态图，而不是另写一套状态名 if/elif。
            var target: StringName = actor.state_machine.get_root().get_next_state(_request(candidate))
            if target.is_empty():
                continue
            _dispatch(candidate, int(group["time_stamp"]))
            return  # 整组已移除，失败／低优先候选不会遗留到后续动作。
        # 窗口已开放但该组没有合法候选：丢弃并尝试下一组。

func _dispatch(candidate: Dictionary, original_stamp: int) -> void:
    var advancer: FrayBufferedInputAdvancer = actor.input_advancer
    if candidate["kind"] == "sequence":
        advancer.buffer_sequence(candidate["name"])
    else:
        advancer.buffer_press(candidate["name"], candidate["pressed"])
    # 当前 get_buffer() 返回浅拷贝，BufferedInput.time_stamp 是公开字段。
    # 修改该对象的时间戳保留原始缓冲年龄，不操作插件的私有队列。
    var queued := advancer.get_buffer()
    queued[0].time_stamp = original_stamp

class SemanticEvent:
    extends FrayInputEvent

    var pressed: bool

    func _init(name: StringName, down: bool, started: int, detected: int) -> void:
        input = name
        pressed = down
        time_pressed = started
        time_detected = detected
        physics_frame = Engine.get_physics_frames()
        process_frame = Engine.get_process_frames()

    func is_pressed() -> bool:
        return pressed

    func is_distinct() -> bool:
        return true  # 这是已经归一化的独立语义流，不混入原始复合输入。
```

`SemanticEvent` 是游戏侧事件对象，复用 FrayInputEvent 的公开时间字段并覆写查询方法，不修改全局广播事件或插件的私有标记。持续方向只在改变时生成 matcher 事件；角色运动依然通过 Controller 查询左右状态，防御同理，**不会因为某条指令获胜而清掉按住方向的状态**。 跳跃、投技等需要缓冲的动作请求可增加独立 action／`_press_routes` 和转移规则；如果复用 up 作为跳跃键，也只把其按下边沿列入映射，不把每帧保持 up 都当成新请求。

候选分组以一次按钮边沿为边界，不是把同帧所有输入合成一组：同一次 P 的 `236P` 与 `punch` 互斥，另一次重拳请求仍是独立组。相同时间戳的不同按钮按语义名排序是本例的确定性约定；如果玩法要求同帧按键组合优先，应先识别组合、建立输入归属关系，再扩展仲裁，不能只修改这一排序函数。

**合法性与回退例子：**Idle 收到同组 `[236P, punch]` 时，有气则选择 Special；没气则尝试当前姿态对应的普通拳；LightPunch 取消窗口中如果指令不合法且没有普通拳取消边，则整组丢弃。候选优先级只在同组内比较；组之间按已收集的时间顺序消费，不让新必杀技无条件插队到旧请求之前。

#### 本例的适用边界

- 预检与真正消费使用同一根状态图、同一批无副作用条件，且在同一个推进器回调中连续执行。规则未配置 `min_input_delay`／按住时长限制；若加入这些依赖 Advancer 内部计时的条件，必须让预检与真实请求的时间字段一致，不能原样使用 `_request()`。
- 当前 `get_next_state()` 只检查所在层；本例不覆盖层级状态图或正在 travel 的状态机。自动返回边必须继续使用 EmptyTickTransition，避免预检把返回 Idle 当成“攻击请求合法”。
- 游戏层只长时间保存候选组；Advancer 每次只接收一个已经选好的请求并立即尝试，不形成两套各自续时的缓冲。原始时间戳仍传给推进器；到期边界若在调用间跨过，允许该请求过期丢弃，不重新生成它。
- 本例仅注册一个以 P 结尾的 236P。新增序列要同时配置树、`_sequence_specs` 和转移规则。单个 FraySequenceMatcher 未必会同时报告所有共享前缀／同叶冲突序列；需要多个独立识别器时可以在**同一次事件**处理期间汇总结果，再统一排序，不让识别器直接入队。
- 八方向逐步采样适用于本例搓招；没有覆盖单物理步内多个方向变化、复杂蓄力、按键和释放共享消费资格等全部规则。蓄力需另外保留其定义要求的持续分量／真实按住时刻；不要使用 Advancer 的 time_held 代替它。
- 本例按“消费时资源不足就退回普通拳”设计。若游戏要求识别到指令后即禁止普通拳回退，应在构造组时移除该普通候选，而不是让它以另一个队列项残留。

#### 7.8.5 物理顺序、缓冲与暂停：保证只有一个消费入口

统一入口每个物理步执行一次。工程必须固定并验证：**FrayInput 更新 → 本角色的动画／运动／朝向与状态机自动完成检查 → InputAdvancer 的 step 钩子 → 父类推进器消费**。 `step()` 应在本物理步的 Fray 事件全部收集后执行；否则方向快照与按钮事件可能来自不同步，不能靠候选排序补救。相关节点处于同一物理处理链时，按工程实际使用的 Godot 版本配置处理优先级／节点顺序，并记录日志验证；不要仅因为都选了 Physics 就认为顺序已保证。不得手动再调用 step 或私有 `_advance()` 形成第二次更新。

- Idle 打开消费窗口，攻击进入关闭。关闭期间仍识别基本输入与指令并保留候选组，按 `max_buffer_time`（秒、真实时间）过期；窗口开放后再决定序列优先还是普通拳回退。
- 在 LightPunch 动画合法帧用方法轨调用 `set_special_cancel_window(true)`，结束时调用 false；结算层维护 `hit_confirmed`。候选预检与状态机使用同一个 `can_special_cancel`，不用重复手写状态名判断。
- 窗口开放且所有候选均不合法时整组丢弃，不会继续等未来条件变化。若要求等待命中确认，先保持窗口关闭；若要求“开放时也保留失败候选”，需另行规定重试与阻塞后续请求的策略。
- 菜单／改键／断线时调用 `set_gameplay_input_enabled(false)`，清理候选组、按钮暂存、matcher 和 Advancer；恢复前按第 7.7 节等待中立及 Fray 完成采样，再调用 true。只清 Advancer 而不清候选组，会在恢复时出旧招。
- 外部改变 Controller.disabled／轮询 device 时也要走同一关闭、清理和恢复流程；不得只改 device 让旧通道的序列历史继续使用。暂停 SceneTree 时同样不能让全局输入持续收集而 step 停止回收。
- 各组保留最初的时间，不因窗口关闭／重新进入 Idle／提交给 Advancer 而续期。本例仍是毫秒时钟，命中停顿不冻结过期时间；动作帧缓冲需另外换成游戏时钟方案。
- 一个 step 最多投递一个获胜请求，但同物理帧中状态机可能先完成一次自动返回，再执行一次输入转移；本例不声称全系统每帧只能切换一次。

#### 7.8.6 大量相似取消边：可选的标签与全局转移

如果多个普通技共享同一取消规则，可在构建期间用标签声明，代替逐一添加“普通技 → Special”边。例如把上方 LightPunch → Special 的本地规则删掉，在 `builder.build()` 之前添加：

```gdscript
builder.tag_multi(PackedStringArray(["LightPunch", "CrouchPunch", "HeavyPunch"]),
    PackedStringArray(["normal_attack"]))
builder.tag(&"Special", PackedStringArray(["special_attack"]))
builder.add_rule(&"normal_attack", &"special_attack")
builder.transition_sequence_global(&"Special", {
    "sequence": &"236P",
    "prereqs": PackedStringArray(["grounded", "has_special_meter", "can_special_cancel"]),
    "switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
})
```

这不是“任意状态都可出必杀”：必须有源／目标标签和规则匹配，且满足 prereqs。给希望允许取消的各招式配置自己的窗口；不要给 Hurt／Knockdown 等强制状态随意加普通技标签。局部边与全局边有不同候选顺序，具体限制见第 11.8 节。

**结论：基本输入与序列招式分开识别、同次触发统一仲裁、胜出请求统一交给 Advancer；持续输入提供状态查询。用规则表表达合法转移，不用把状态机再手写成一份 if/elif 状态机。** 角色运动、战斗结算、输入仲裁与时钟控制仍属于游戏逻辑，不应靠不断增加转移分支混在同一个回调里。

## 8. 指令识别与取消

指令识别使用 `FraySequenceMatcher`、`FraySequenceTree` 和 `FraySequenceBranch`。一个玩家使用一个匹配器，不能混合读取双方事件。

以下只展示**已经转换为角色语义输入**后的注册方式：

```gdscript
var matcher := FraySequenceMatcher.new()
var sequence_tree := FraySequenceTree.new()

sequence_tree.add(&"236P", FraySequenceBranch.builder()
    .first(&"down")
    .then(&"down_forward", 200)
    .then(&"forward", 200)
    .then(&"punch", 200)
    .build()
)
matcher.initialize(sequence_tree)
matcher.match_found.connect(input_advancer.buffer_sequence)

# 在对应角色的输入适配层中调用：
# matcher.read(semantic_event)
```

上面的 `match_found → buffer_sequence` 直接连线只展示最小接入。采用第 7.8 节时，识别结果只由统一入口收集进候选组，最终通过其唯一 `_dispatch()` 投递；不要再保留这条直接连线或旧的 `submit_sequence()` 外部入队入口。

这里的 `semantic_event` 是游戏层完成玩家筛选、方向归一化后的 `FrayInputEvent`，不是插件自动生成的角色前后方向。不要原地修改广播给其他监听器的同一个输入事件。`down_forward` 需要注册复合输入或由适配层生成；字符串 `236P` 只是序列名。

时间单位特别注意：**`FraySequenceBranch.Builder.then(input, max_delay, min_time_held)` 的时长参数使用毫秒，注意最大间隔在最小持有时长之前。** 例如 `then(&"punch", 200)` 表示距前一输入最多 200 ms。蓄力输入的持有时长也以毫秒指定，并按当前实现的释放事件匹配规则处理。

匹配结果可以交给推进器，再由状态机定义：

```gdscript
# 在构建器上添加；Special 必须有对应的行为实现和完整 HitState。
builder.transition_sequence(&"Idle", &"Special", {"sequence": &"236P"})
```

这里配置键是 **`sequence`**，不是按钮转换中的 `input`。同时识别普通拳和必杀技时，应在适配层或统一输入仲裁中决定谁优先，并消费对应输入，不能依赖多个信号监听器的触发顺序。

取消还需要检查命中／防御确认、取消窗口、目标招式类别和资源消耗。可以用构建器 `register_conditions()` 注册 Callable，并在转换的 `prereqs` 中引用条件名称。不要用转移的 `priority` 数值保证普通攻击／必杀技优先级：当前 `advance()` 按候选枚举顺序取第一个合法转移，没有按该字段排序，见第 11.8 节；输入仲裁见第 7.8.4 节。`AT_END` 会等待当前状态完成，立即取消应明确选择 `IMMEDIATE` 并配置必要条件。

## 9. 命中防御与去重

### 9.1 从哪里收集接触

当前版本信号：

- 单框：`hitbox_entered(hitbox)`、`hitbox_exited(hitbox)`。
- HitState／管理器：`hitbox_intersected(detector_hitbox, detected_hitbox)`、`hitbox_separated(detector_hitbox, detected_hitbox)`。

两个参数依次是**主动检测框、被检测框**。通常只在唯一管理器监听 `hitbox_intersected`，避免每个框、状态和管理器各扣一次血。

> 当前根目录管理器已修正“离开”信号接线，进入与离开事件分别由 `hitbox_intersected`、`hitbox_separated` 转发，见第 11.1 节。持久接触表仍需验证框停用、状态切换、节点移除等生命周期；不要仅凭接线修正就假定所有接触记录都会自动清理。

把以下成员和方法加入角色脚本，并在 `_ready()` 中连接 `hit_manager.hitbox_intersected.connect(_on_hitbox_intersected)`：

```gdscript
var pending_contacts: Array[Dictionary] = []

func _on_hitbox_intersected(detector: FrayHitbox2D, detected: FrayHitbox2D) -> void:
    if detector.source != self or detected.source == null or detected.source == self:
        return
    var attack := detector.attribute as FightingBoxAttribute
    var target := detected.attribute as FightingBoxAttribute
    if attack == null or target == null:
        return
    if attack.kind != FightingBoxAttribute.Kind.ATTACK or target.kind != FightingBoxAttribute.Kind.HURT:
        return
    pending_contacts.append({
        "attacker": self,
        "defender": detected.source,
        "attack_box": detector,
        "hurt_box": detected,
        "attack_id": attack_instance_id,
        "segment_id": attack_segment_id,
    })
```

这段代码**仅收集事件，不会扣血**。对战控制器应在统一安全阶段消费并清空双方队列，检查引用有效性，并按规则使用接触时刻的状态快照。若需要延迟处理，补充接触帧、朝向、防御姿态及招式数据快照，防止之后状态改变导致误判。

### 9.2 推荐结算顺序

1. 汇总双方候选接触，排除无效对象、同 source、同队和已失效招式事件。
2. 按 **攻击者身份 + 招式实例 ID + 攻击段 ID + 受击角色身份** 分组，排除该段已结算的目标；同组多框候选按第 9.3 节选出有效结果，不能简单让第一个回调获胜。
3. 判断无敌、投技条件或属性免疫，再判断高低段和前后防御输入。
4. 在双方接触均收集完后决定同帧互击或优先级，不让回调先后决定胜负。
5. 应用伤害／削血、命中或防御硬直、击退、命中停顿、连段计数。
6. 切换受击／防御行为，并设置对应完整 HitState；被打断攻击的后续写入失效。
7. 记录该段对该目标的已结算结果、命中确认、资源变化以及可取消窗口，驱动音效和特效。

同次攻击命中同角色多个 Hurtbox 时仍只结算一次。不要因为受击方从 Stand 切到 Hurt、换了框实例，就认为是新的一击。

多段攻击必须显式增加 `attack_segment_id`。持续重叠不会因为改编号而自动产生新的 entered 事件；可在新段对当前有效攻击框主动检查重叠，或设计跨物理更新的关闭／重开周期。主动检查也必须走同一套去重与结算规则。

### 9.3 多攻击框 × 多受击框：组合轮廓不等于多次伤害

例如 HeavySlash 的两个攻击框同时接触对手的三个受击框，可能出现多组不同的框对接触。管理器只汇总转发信号，**不会自动合并这些接触或替游戏层去重**；即使只监听管理器一次，也仍需第 9.2 节的结算键。

- 同一击的 AttackNear、AttackTip 共享同一个招式实例 ID 和攻击段 ID。不要把攻击框／受击框节点 ID 放入“是否已经打过此角色”的键，否则组合区域会变成重复伤害。
- 去重记录应覆盖该攻击段的有效生命周期，而不是每帧清空。某个框离开、换到另一个框接触、受击方切换姿态，都不应允许同一段再次结算；离开信号不等于重置攻击资格。
- 如果近端和尖端属性不同，或头部与躯干有不同受击规则，先筛选有效候选，再按游戏定义的稳定优先级选出一个结果，例如“有效尖端优先于近端，相同优先级按固定框序”。不得依赖物理信号到达顺序。当前示例的 FightingBoxAttribute 没有部位／优先级字段，若有此需求应自行扩展；Fray 不会自动实现甜点伤害、头部倍率或护甲规则。
- 若玩法确实要求同一招式打两次，显式进入新的攻击段，而不是每增加一个几何框就增加段号。第 9.1 节示例的 `attack_segment_id` 是角色当前段号，适合同一时刻的一组攻击框；如果不同攻击段要同时存在，需在游戏层按框或攻击组记录段号，并把对应值写入接触快照，不能直接照搬这个单段号示例。
- 对持续重叠的新段补采样时，应检查**当前状态的所有有效攻击框**，不要只查询名为 Attackbox 的一个节点；重叠查询需等待物理更新反映新配置（G6），结果仍送入同一候选队列和去重流程。

## 10. 推挤框与角色分离

**Pushbox 是 Area2D 检测区域，不是实体阻挡。** 插件只告诉你发生交互，角色分离需要游戏实现。

建议对战控制器每个物理更新统一解算一次。对于轴对齐矩形推挤框，可按以下规则实现：

1. 从双方管理器当前状态获取启用的 Pushbox；关闭时不参与。
2. 计算世界空间矩形范围，先判断垂直区间是否相交。
3. 计算水平穿透量：`min(right_a, right_b) - max(left_a, left_b)`，非正则不分离。
4. 按中心左右关系选择分离方向。中心重合时保留上一帧左右关系或用稳定角色 ID 决定，避免抖动。
5. 双方均可移动时各承担一半位移；一方被墙限制时，把剩余可用分离量分配给另一方。
6. 用考虑场景碰撞和边界的移动方式应用修正，必要时有限次迭代，避免穿墙。

这是矩形水平分离的算法说明，不是任意形状的通用物理求解器。空中交叉、倒地压身、角落换边需要明确专用规则。

- 不要只在 entered 时推一次：持续重叠需要持续处理。
- 每对角色每帧只解算一次，避免双方各自把对方推走造成加倍。
- 切到 Crouch 后应使用 Crouch 的 Pushbox，而不是缓存 Stand 的尺寸。
- 手动位置修正后，Area2D 重叠缓存不会立即同步为新位置；本帧修正应使用自己的几何数据，后续检测结果要考虑物理更新时序。
- 世界碰撞、角色移动、推挤修正、接触采样和结算的先后顺序需要统一约定，不要由多个脚本各自自由执行。

## 11. 当前源码注意事项

以下是针对**当前根目录副本的静态检查结果**，不是声称所有 Fray 版本都有同样问题。2026-10-16 按用户修改后的源码复核；本次只更新文档，不修改插件。当前 PATH 与工作区未找到可用 Godot 可执行文件，以下“正确”表示静态代码／调用链核对通过，不代表已经通过引擎运行测试。Git HEAD 中部分文件属于旧版目录／接口，不能将其全部差异视为本次用户修改。

| 检查项 | 本次结论 |
| --- | --- |
| FrayHitStateManager2D 离开信号接线 | 已修正，进入／离开分别转发 |
| FrayHitState2D.set_hitbox_active | 原先从零开启失败的问题已移除；仍缺索引范围检查 |
| FrayInputMap.get_bind_names | 使用 `Array[StringName]` 加 `assign(keys())`，写法合理，调用处类型一致 |
| FrayAnimatorTracker.emit_anim_finished | 通用结束信号与按动画命名的结束信号转发正确；结束时机仍取决于具体 tracker |

### 11.1 `set_hitbox_active()`：已移除错误判断，合法索引检查代办

`src/hit/2d/hit_state_2d.gd` 已注释掉原来的 `flag > active_hitboxes` 检查。**移除这个错误判断是对的**：掩码为 0 时，现在可以通过合法索引开启框；但只注释掉检查并不是完整修复。

例如 Stand 实际只有 Hurtbox、Pushbox，合法索引为 0、1。调用 `set_hitbox_active(2, true)` 仍会写入 `4`：这个非零掩码没有对应的实际框，却会触发管理器选中 Stand 并停用其他状态，导致没有任何实际框启用。负索引也应在位移前拒绝。

建议把方法补成下面的形式（**建议代码，尚未写入插件**）：

```gdscript
func set_hitbox_active(index: int, enabled: bool) -> void:
    var hitbox_count := 0
    for child in get_children():
        if child is FrayHitbox2D:
            hitbox_count += 1
    if index < 0 or index >= hitbox_count:
        push_warning("Hitbox index out of bounds: %d" % index)
        return

    var flag := 1 << index
    if enabled:
        active_hitboxes |= flag
    else:
        active_hitboxes &= ~flag
```

计数必须只包含直接子 `FrayHitbox2D`，与第 3 节的实际位索引保持一致；不要用全部子节点数量代替。`is_hitbox_active(index)` 也建议采用相同的合法索引检查。整值赋值 `active_hitboxes = mask` 本身同样没有过滤不存在的位，因此动画轨仍必须按实际布局填写，不是任意非零数都合法。

另外，本文件的 `get_hitboxes() -> Array[FrayHitbox2D]` 内部仍声明 `var array: Array`，与返回类型不一致；建议改成 `var array: Array[FrayHitbox2D] = []`，避免返回未类型化数组的类型问题。不要把 FrayInputMap 的数组修正当作所有同类返回值都已修好。

本文继续用 `state.active_hitboxes = mask` 表达整套姿态；辅助方法补齐检查后，可用于明确的单框操作，但不能与动画轨同时争写同一个状态。

### 11.2 活动标记与实际监测不是同一件事

`deactivate()` 写入 0 会触发变化信号，而管理器回调又调用 `activate()`，因此状态活动标记可能再次被设为 true。掩码为 0 的框已经停用，但不能仅凭 `is_active()` 判定唯一有效状态。

管理器初始化前，某状态即使在场景中保存了非零掩码，也可能没有同步内部活动标记。第 5 节的“全部明确置零，再选 Stand”是必要的初始化步骤。

### 11.3 空属性与普通 Area2D 混入

`can_detect()` 在 attribute 为空时走放行分支；必须配置非空属性，并在结算层重复核验归属。

`get_overlapping_hitboxes()` 调用带 `FrayHitbox2D` 类型参数的 `can_detect()`，没有先筛掉所有普通 Area2D。战斗检测层应隔离普通区域；若需要混用，可自行遍历 `get_overlapping_areas()`，先判断 `area is FrayHitbox2D` 再继续。

### 11.4 输入持有时长的两种含义

`FrayInputTransitionPress` 的 `min_time_held`／`max_time_held` 文档按秒描述，但推进器构造输入时把“入队后的毫秒数”放入 `time_held`，并不是实际按住按钮的时长。

普通单次按键转换可不配置这两个持有时间条件。蓄力招式优先使用已明确定义毫秒时长的序列分支，或自行构造正确的转换输入并验证单位和语义；不要直接依赖推进器该字段实现蓄力。

### 11.5 其他调试现象

- 管理器切换代码包含 `print(child.name)`，控制台输出状态名称并不必然意味着报错。
- 管理器配置警告函数仍使用 `if get_children().any(func(node): node is FrayHitState2D)`，回调缺少显式返回，条件也没有表达“没有任何 HitState”。建议改为 `if not get_children().any(func(node): return node is FrayHitState2D):`；当前不要仅凭是否出现警告确认结构正确。
- 调用签名以当前脚本声明为准，示例中的资源名和状态名需与自己的场景一致。
- 这些源码问题需独立测试／修复；不能因为已经是 Godot 4 风格就把 Alpha 当作完成验证的战斗底座。

### 11.6 FrayInputMap：类型化名称列表正确，动态映射仍需约束

`src/input/autoloads/fray_input_map.gd` 当前 `get_bind_names()` 为：

```gdscript
func get_bind_names() -> Array[StringName]:
    var names: Array[StringName]
    names.assign(_input_bind_by_name.keys())
    return names
```

这个写法把字典键列表复制到目标类型数组，与返回签名一致；各注册入口使用 `StringName`，`FrayInput` 中名称遍历以及与 `get_composite_input_names()` 的列表拼接也与之匹配。这一处写法合理。当前 `remove_input()` 删除组合输入时也同时删除字典项和优先级列表项，没有只删其中一个的问题。以上是当前代码核对，不推断这些行全部属于本次改动。

仍需注意：

- `get_composite_input_names()` 直接返回内部 `_composites_sorted_by_priority` 数组。调用方目前主要读取它；对外应明确只读约定，或返回 `duplicate()` 副本，避免调用方修改列表后与字典失配。
- `add_bind_action(name, action)` 在 Godot InputMap 缺少 action 时仅警告，仍会注册绑定；必须事先创建对应 action，不能把警告当作自动修复。
- `remove_input()` 只负责映射表，不负责清除 FrayInput 的设备输入状态、依赖该绑定的组合输入、已缓冲输入或角色招式状态。若要运行时重绑，需另行约定安全更新点与缓存清理策略。
- 动态装备招式优先改变“输入槽位 → 招式资源”的映射，不必每次装备都删除／重建 Fray 的底层输入绑定。

### 11.7 `emit_anim_finished()`：转发正确，不等于结束时机已可靠

`src/state_mgmt/component/anim_tracker/animator_tracker.gd` 当前实现为：

```gdscript
func emit_anim_finished(animation: StringName) -> void:
    animation_finished.emit(animation)
    if has_user_signal(format_usignal_finished(animation)):
        emit_signal(format_usignal_finished(animation))
```

此处通用 `animation_finished` 携带动画名，按动画命名的 `_<动画名>_finished` 信号不带参数，与注册和 `AnimationObserver.usignal_finished()` 的约定一致；不会错误地检查或发送 started 信号。**这项转发修正是正确的，但此函数不负责判断结束时机，也不负责防止调用方重复报告。**

当前 `FrayAnimatorTrackerAnimationPlayer._process_impl(delta)` 仍通过 `current_animation_position + delta >= current_animation_length` 预测结束，尚未直接转发播放器的原生完成信号。它使用渲染更新的 delta，与本文 Physics 动画时间轴不一定同步，也未处理实际播放速度、倒放、循环和每次播放的去重。因此可能提前、重复或漏报结束，不能用这项基类修正证明它已经适合作为 60 Hz 战斗动作的结束依据。

第 5 节继续直接连接 `AnimationPlayer.animation_finished`，只记录完成标志，由行为状态消费；不改成依赖上述预测。如果以后完善 tracker，建议明确使用原生事件的转发与连接／释放生命周期，并验证循环、中断、重启动作、变速、暂停恢复和倒放。运行时添加动画库时，按动画命名的用户信号也需要额外注册；当前只在 tracker 的 `ready()` 中注册当时的动画列表。

### 11.8 状态转移与 Advancer：候选顺序、自动边与初始进入

第 7.8 节的表驱动示例已针对以下当前源码行为作出约束，不能只依据类注释或字段名称推断：

- **`priority` 不控制 `advance()` 的候选排序。** `get_next_transitions()` 先收集本地边，再追加可用全局边；`get_next_state()` 按该顺序找到第一条可转移边即返回。`priority` 在 `_get_transition_priority()` 中用于寻路成本，不等于 Advancer 的输入队列优先级。相同输入的多条边优先设计为互斥条件；确实要竞争时明确构建顺序并测试，不能只改 priority 数字。
- **`auto_advance = false` 不等于“自动更新绝不会走这条边”。** 状态机自动更新调用 `advance({})`，当前 `_can_advance()` 首先检查 `transition.accepts(input)`；auto_advance 为 true 时才额外检查 advance_conditions。基础转移默认接受所有字典，所以普通无条件边即使没有开启 auto_advance，也可能被空输入或玩家输入走通。必须正确配置 `prereqs`、转移类型与 accepts 语义；第 7.8 节用游戏层 EmptyTickTransition 限制自动完成边。
- **空输入自动边与输入消费不是同一件事。** Advancer 以 `state_machine.advance(sm_input)` 返回 true 作为已消费依据，不知道实际走的是否为期望的按键边。不要把“走到 Idle”误认为“预输入的拳成功执行”；暂停消费与空字典专用完成边需一起设计。
- **初始叶状态的进入逻辑需要核验。** `FrayStateMachine.initialize()` 调用根的 `_enter_impl()`，而当前根实现只递归进入复合子状态，没有对普通初始叶状态调用 `_enter_impl()`。对已经被设为当前的叶状态再 `goto()` 同一状态，也不保证重新进入。第 7.2／7.8 节用空 Boot 作为起点，再通过公开 `goto("Idle")` 触发实际进入，无需调用私有方法或修改插件。
- `register_conditions()` 设置的是整张条件表，多次调用会替换前一次注册内容；构建时合并一次传入。条件无副作用，资源消耗在进入目标状态后处理。
- 不要在开启 Advancer 自动 Physics 更新的同时，又手动反复调用同一输入的 `state_machine.advance()`；这会形成两个消费入口。若需要严格单步调度或按动作帧保存失败请求，应在游戏层设计统一调度，不把默认组件当成已实现回滚或严格单帧单转移保证。

## 12. 实施步骤与验收清单

推荐先完成一个最小闭环，再扩展复杂招式：

1. 安装插件并确认没有脚本解析错误，建立推荐节点树。
2. 创建三类属性资源和碰撞层，初始化只启用 Stand 的受击／推挤。
3. 在项目设置 → 输入映射中配置双方 action 和键位，初始化时用 `add_bind_action()` 桥接；再实现左右移动、蹲下、跳跃、朝向，检查框随姿势切换。
4. 建好 idle／light_punch 的图片帧、完整判定属性轨，再接入 Idle → LightPunch → Idle，验证 Stand 的掩码为 3，LightPunch 时间轴的掩码为 5 → 7 → 5，返回 idle 后恢复 Stand 的 3。
5. 连接管理器进入事件，先记录接触，再加入命中去重和统一结算。
6. 实现持续推挤和墙角处理，避免角色互相穿透或重复分离。
7. 增加防御、高低段、硬直、取消、倒地、起身和命中停顿。
8. 经过输入专项测试后，再加入必杀技、蓄力、多段攻击和弹体。

### 结构检查

- [ ] 每个角色只有一个 FrayHitStateManager2D。
- [ ] 每个 HitState 只包含所需的直接子框；非攻击姿态无需 Attackbox，掩码按各状态实际框顺序计算，增删／重排后已同步更新动画轨。
- [ ] 每个框都有有效形状、非空 attribute、正确 Layer／Mask。
- [ ] 已明确选择独立多框还是单框多形状；独立框均为 HitState 直接子节点，子形状不计入 active_hitboxes 位数。
- [ ] 多框布局的初始化、普通动画、RESET 与中断清理一致；六框 HeavySlash 的被动／全有效掩码为 39／63，未误用三框布局的 5／7。
- [ ] source 指向正确角色，双方没有误用同一个归属引用。
- [ ] 初始化先关闭全部框，再选 Stand；非当前状态不存在残留监测。
- [ ] 未用多个管理器分别维护受击、攻击、推挤。

### 战斗检查

- [ ] 前摇／后摇不能命中，有效帧才能命中；普通攻击有效帧仍可受击。
- [ ] 相同攻击段命中多个受击框只扣血一次，新招式可再次命中。
- [ ] 受击／取消后被中断动作不会重新开启攻击框。
- [ ] 防御产生防御结果，而不是靠关闭受击框实现“免疫”。
- [ ] 换向时图像、框和防御方向同步，蹲下时推挤尺寸随之改变。
- [ ] 同帧互击遵循明确规则，不依赖回调顺序。
- [ ] 推挤每对角色每帧只处理一次，墙角不穿墙，空中交叉符合规则。
- [ ] 输入不会串玩家；不合法阶段的缓存保留／丢弃符合设计。
- [ ] 命中停顿对状态、动画、移动、输入过期的影响均有明确测试。
- [ ] 已验证管理器进入／离开分别转发，停用框和切换状态后的接触记录不会残留。
- [ ] 单框辅助方法已覆盖从零开启、关闭、索引 -1 和索引等于实际框数；无效索引不得改变掩码或当前状态。
- [ ] 输入名称列表返回类型、注册／删除组合输入后的列表一致性、蓄力时长已覆盖第 11 节对应问题。
- [ ] tracker 的通用／按动画结束信号分别监听时参数正确；若启用具体 tracker，已验证播放速度、循环、暂停、中断和重复结束上报。

### 多框组合专项检查

- [ ] 六框 HeavySlash 的 `39 → 47 → 63 → 55 → 39` 依次只开启预期区域；返回 StandComposite 后掩码为 15，旧状态无残留攻击框。
- [ ] 两个攻击框同时碰到对方多个受击框，同一攻击段只结算一次；接触从近端移到尖端、受击方换姿态后也不会追加伤害。
- [ ] 新攻击段可再次命中；持续重叠时已验证补采样或跨物理更新的重开机制，未依赖自动重发 entered。
- [ ] 头部受击框关闭但躯干保留时，只按仍有效的几何区域受击；整身不可受击时所有受击位均关闭。
- [ ] 若有不同框属性／部位优先级，调换候选入队顺序不会改变结算结果，无效候选不会抢占有效候选的资格。
- [ ] 单框多形状方案下各形状都能贡献检测区域，整体开关正常；没有把框级事件误当成带部位索引的事件。

### 输入映射与缓冲专项检查

- [ ] 实际键位已配置在目标工程的项目设置 → 输入映射中，脚本只桥接 action；修改编辑器键位后无需修改键码脚本。
- [ ] 角色初始化前已完成 Fray 桥接；不存在旧 add_bind_key 同名注册，也不重复从 Godot Input 和 Fray 事件投递一次按下。
- [ ] p1_*／p2_* action 与角色输入名称正确，双手柄来源、同时按下和重连不会串控；未把 Controller.device 当作 action 绑定的原始设备过滤器。
- [ ] 推进器的失败出队、paused 期间继续入队、真实时间过期均符合设计；若要求按战斗帧计时，已使用自定义缓冲策略。
- [ ] 若试用 FrayInputBuffer，已测试到期前／后消费、持续按住、连按、设备 0／非 0、命中停顿及成功后的单次消费。
- [ ] 若试用 Window，已测试同帧其他输入、释放／echo、无后续事件的过期、重复开窗、can_start 持续为 true、can_end 未收到按键时的行为。
- [ ] 若动态移除缓冲或释放角色，已检查信号连接是否清理，不残留旧角色的回调。

### Advancer 表驱动专项检查

- [ ] 第 7.2 与第 7.8 节选择一套接入，事件只连接一次；没有同时从 Godot Input 和 Fray 重复入队。
- [ ] Boot → Idle 确实调用进入逻辑并播放待机；每次重新进入 Idle 都恢复输入窗口。
- [ ] 相同 punch 请求根据地面／蹲姿条件只选一个目标；新增招式只扩展映射与规则，不新增状态名称分支链。
- [ ] 攻击前摇不消费普通输入，合法窗口才尝试；失败请求会丢弃、暂停期间仍会过期的行为符合设计。
- [ ] 自动完成边只接受空字典，不把待执行攻击请求当作返回 Idle 的输入吞掉。
- [ ] 指令与普通拳经过唯一仲裁入口，236P 不会同时留下一个额外 punch；相同输入的竞争不依赖 priority 自动排序。
- [ ] 同组 236P 有气出必杀、无气退回合法普通拳，消费时只扣一次气；无合法候选时按策略丢弃。
- [ ] 关闭窗口时保留整组但不续期；转交 Advancer 后仍使用原时间戳，暂停／改键／换设备会清掉两层待处理记录。
- [ ] 持续移动／防御不逐帧入队；方向采样先于本步按钮、同时按键顺序与换边中断规则符合设计。
- [ ] 未命中确认／窗口外不能取消；合法取消只进入目标一次，退出旧状态时清理判定与旧窗口。
- [ ] 开启标签全局边后，仅允许被标记的源状态取消，受击／倒地不意外出招。
- [ ] 已记录并验证动画、状态机自动更新、Advancer 的物理执行顺序及同帧完成／预输入边界。

### 自定义按键专项检查

- [ ] 已按同目录《Fray_键盘与手柄自定义按键接入指南》第 9 节覆盖键盘、手柄按钮、摇杆方向、死区、冲突、保存／取消／恢复默认。
- [ ] 双人同键盘、键盘 + 手柄、双手柄互不串输入；仅连接非 0 手柄及拔插设备 0 时，Fray 采样与设备认领正常。
- [ ] 改键不删除其他绑定槽或重建 Fray 输入名称；重启加载与损坏配置回退正常。
- [ ] 菜单输入不会进入战斗队列；应用或切换通道后已完成物理采样、清理历史并确认中立，恢复对战不误触发攻击／蓄力。

### 动画专项检查

- [ ] 主角色采用 AnimationPlayer + AnimatedSprite2D；Sprite 不自行播放，两个 Autoplay 均关闭。
- [ ] 每个动作 t=0 都有显示帧和目标 HitState 非零掩码，图片组名称与 begin_action 参数一致。
- [ ] frame 和 active_hitboxes 轨均为 Discrete／Nearest；没有两套脚本逐帧争写判定。
- [ ] 初版使用 Physics 自动推进，没有同时每帧手动 advance(delta)。
- [ ] 轻拳时间轴在 0、5/60、8/60 设置 5、7、5，长度为 20/60，非循环。
- [ ] 记录物理帧号、动画位置、Sprite.frame、管理器当前状态、掩码、接触事件与消费时刻，确认有效段实际采样次数及结束交接，无意外首帧偏移或多一帧后摇。
- [ ] 30／60／144 渲染 FPS 下战斗时序一致，符合固定物理节拍的设计。
- [ ] 在前摇、有效段和后摇分别强制受击，原攻击框都被清理，目标动作首帧立即生效。
- [ ] 命中停顿同时冻结主时间轴和应冻结的逻辑，恢复时不从头播放、不跳过有效段。
- [ ] RESET 不是运行时回待机路径；循环 idle 不依赖 animation_finished 退出。
- [ ] 删除末尾清理事件后，中断清理仍有效，不把安全性建立在动画一定播完上。
### 常见问题速查

| 症状 | 优先检查 |
| --- | --- |
| 插件类名冲突或加载了非预期代码 | 目标工程是否扫描到多个 Fray 副本，实际资源路径是否正确 |
| 找不到框的属性资源入口 | 检查 FrayHitbox2D 的 attribute 属性，单数 |
| 只调用 activate 却没有框 | 应赋值 active_hitboxes，不是只显示状态 |
| 写 0 后没切到新状态 | 零掩码不会选中目标，动作开头应写入该状态的非零掩码 |
| 从全关状态无法逐个开启框 | 检查是否仍加载旧版边界判断；当前根目录已移除该判断，但仍需验证实际索引合法 |
| 刚进入就收到 separated | 当前根目录接线已修正；检查运行副本、重复连接以及同帧停用／切换状态 |
| 精灵跑得比判定快或被关键帧拉回 | 是否又调用了 AnimatedSprite2D.play，或者重复手动推进 AnimationPlayer |
| 攻击被打断后判定残留 | 是否执行 end_action；不能只依赖末尾关键帧或 stop |
| 动画正常但框反向或不翻转 | 是否只翻转图像、重复镜像或框不在统一变换子树 |
| 缓冲输入没有等到取消窗口 | 是否提前消费后被丢弃，是否 paused 或超时 |
| 编辑器里配了按键，但 Fray 查询无响应 | 是否用 add_bind_action 桥接、名称是否一致、初始化是否先于角色查询 |
| FrayInputBuffer 更换 device 后缓存不对 | 当前内部 device 未同步，不能只改节点属性；见第 7.5 节 |
| Window 中按过键却读不到／超时仍为 true | 后续事件覆盖、缺少过期清理和重启复位；不要作为可靠窗口直接使用 |
| 角色接触却不互相阻挡 | Pushbox 只检测，尚未实现持续分离 |
| 同次攻击反复扣血 | 是否按框而非角色去重，是否多层重复监听 |

## 13. 源码与参考资料

### 13.1 本地核验来源

以下路径相对于 **Git 仓库根目录**。插件调用签名以当前脚本声明为准；Demo 仅用于观察动画组织，不代替本项目的判定布局和战斗规则。

| 文件／目录 | 内容 |
| --- | --- |
| `addons/fray/plugin.cfg`、`addons/fray/plugin.gd` | 版本、自动加载注册 |
| `addons/fray/docs/introduction/installation.md` | 安装与 Alpha 说明 |
| `addons/fray/src/hit/2d/hit_state_manager_2d.gd` | 状态选择、source、信号转发 |
| `addons/fray/src/hit/2d/hit_state_2d.gd` | 位掩码、直接子框、启停逻辑 |
| `addons/fray/src/hit/2d/hitbox_2d.gd`、`addons/fray/src/hit/hitbox_attribute.gd` | 区域检测与属性 |
| `addons/fray/src/input/controller.gd`、`addons/fray/src/input/autoloads/` | 控制器、映射和事件 |
| `addons/fray/src/input/device/binds/input_bind_action.gd` | Godot action 桥接查询及设备限制 |
| `addons/fray/src/input/input_buffer.gd` | 实验性 Buffer／Window 接口、设备与生命周期问题 |
| `addons/fray/src/input/sequence_matcher.gd`、`addons/fray/src/input/sequence/sequence_branch.gd` | 指令匹配与时长参数 |
| `addons/fray/src/state_mgmt/state_machine.gd` | 初始化、推进、状态切换 |
| `addons/fray/src/state_mgmt/state/state.gd`、`addons/fray/src/state_mgmt/state/compound_state.gd` | 生命周期和构建器 |
| `addons/fray/src/state_mgmt/component/buffered_input_advancer.gd` | 输入消费、暂停与过期 |
| `addons/fray/src/state_mgmt/transition/input_transition_press.gd` | 按键转换时长条件 |
| `addons/fray/src/state_mgmt/transition/input_transition_sequence.gd` | 序列转换 |
| `addons/fray/src/state_mgmt/component/anim_tracker/animator_tracker.gd`、`animator_tracker_animation_player.gd` | 动画信号转发、AnimationPlayer 结束时机估算 |
| `addons/fray_demo/demos/example/2d/player/player.tscn` | 图片 animation／frame 轨，以及 RESET 中的 active_hitboxes 轨 |
| `addons/fray_demo/demos/example/2d/player/player.gd` | 行为切换时播放动作、观察动画完成 |

### 13.2 Godot 官方资料

以下资料用于核对节点分工、属性轨、播放和更新时间；本文的“单角色单管理器”“不混合判定”“中断时清理”等属于本项目方案。

- **G1：2D sprite animation** — 两种精灵动画方式、AnimationPlayer 与 AnimatedSprite2D 的组合，以及 play 后 advance(0) 的首帧更新。
- **G2：AnimatedSprite2D** — SpriteFrames、animation、frame、autoplay 与停止播放。
- **G3：Introduction to the animation features** — 属性轨、离散更新和插值。
- **G4：AnimationMixer** — Physics／Manual 处理方式、循环动画的完成信号语义。
- **G5：AnimationPlayer** — play、stop、混合参数和 seek 的事件行为；不要用逐帧 seek 模拟正常播放并假定它会触发所有事件。
- **G6：Area2D** — 一个区域可以由多个子形状组成；区域级与形状级信号不同，重叠查询随物理更新刷新。
- **G7：CollisionShape2D** — 形状为父 CollisionObject2D 提供碰撞区域；disabled 应通过 set_deferred() 修改。

```text
G1 https://docs.godotengine.org/en/stable/tutorials/2d/2d_sprite_animation.html
G2 https://docs.godotengine.org/en/4.2/classes/class_animatedsprite2d.html
G3 https://docs.godotengine.org/en/stable/tutorials/animation/introduction.html
G4 https://docs.godotengine.org/en/4.2/classes/class_animationmixer.html
G5 https://docs.godotengine.org/en/4.2/classes/class_animationplayer.html
G6 https://docs.godotengine.org/en/4.2/classes/class_area2d.html
G7 https://docs.godotengine.org/en/4.2/classes/class_collisionshape2d.html
```

**最终方案：Fray 行为状态选择动作，AnimationPlayer 统一控制画面帧和判定时序，AnimatedSprite2D 只显示帧图，唯一 HitStateManager 管理按需包含判定框的完整姿态，游戏层统一结算战斗结果。**

