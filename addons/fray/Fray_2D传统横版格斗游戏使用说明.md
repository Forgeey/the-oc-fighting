# Fray（Godot 4）2D 传统横版格斗游戏使用说明

> **依据：仓库根目录 `addons/fray/` 当前源码，`plugin.cfg` 版本 `2.0.0-alpha`。**
> **核对日期：2026-10-16；输入映射、FrayInputBuffer、多框组合、自定义按键、Advancer 表驱动与统一输入仲裁补充核对：2026-10-17。** 插件随附安装说明标注 Godot 4.2+；本文示例使用 Godot 4 GDScript。
>
> 本文是面向本项目的推荐接入方案，不表示项目已经实现全部功能。插件接口以根目录 `addons/fray/` 为依据；Godot 3 Demo 仅作为历史参考，不作为当前战斗时序方案。示例尚未通过 Godot 引擎运行测试。
>
> **2026-10-25 修订：** 每个特殊技固定一套方向序列＋指定攻击按钮，每招一套明确基础数值，不自动派生轻中重版本；默认每招专用叶子与脚本，普通三阶段在叶子内部由逻辑帧推进。AnimatedSprite2D 显示，不使用 AnimationPlayer 节点或判定轨。固定输入与脚本复用是正交问题，公共基类／工具仍可复用。详见 [疑难解答](../../module_codes/my%20fray%20demo/docs/招式装配与判定时序疑难解答.md)。
>
> **核心约定：每个角色仅有一个 `FrayHitStateManager2D`。每个 `FrayHitState2D` 只包含该姿态实际需要的框，同类框可以有多个；idle、jump 等非攻击动作无需创建 Attackbox，也不按框的类别拆成多个管理器。**

## 目录

1. [能力边界与安装](#1-能力边界与安装)
2. [推荐角色节点树](#2-推荐角色节点树)
3. [单管理器与位掩码](#3-单管理器与位掩码)
4. [三类框的属性和碰撞层](#4-三类框的属性和碰撞层)
5. [初始化与动作播放入口](#5-初始化与动作播放入口)
6. [动画与判定：逻辑帧主控，AnimatedSprite2D 显示](#6-动画与判定逻辑帧主控animatedsprite2d-显示)
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

角色模板只保留唯一管理器，按 Loadout 装配所需完整判定场景，不预建所有可装备招式。以下是职责示意，不表示当前 Demo 已有完整战斗功能：

    Fighter (CharacterBody2D)
      ├── WorldCollision (CollisionShape2D)
      ├── Controller (FrayController)
      ├── FighterInput（当前 Demo 的输入与候选）
      ├── StateMachine (FrayStateMachine，当前 Demo 使用 MANUAL)
      │   └── InputAdvancer（当前 Demo 保持 paused）
      ├── VisualRoot（示意：图像与判定统一换向）
      │   ├── Sprite (AnimatedSprite2D，负责显示)
      │   ├── EffectsRoot (Node2D)
      │   └── HitStateManager (FrayHitStateManager2D，唯一)
      │       └── 按最终状态定义装配的完整 FrayHitState2D
      └── Audio (AudioStreamPlayer2D)

实际 Demo 节点名和层级以 scenes/Fighter.tscn 为准，目前 Sprite 与管理器在根下，并非已经存在 VisualRoot。换向必须同时处理判定，不以翻转 Sprite 代替全部镜像。AnimationPlayer 空节点已移除。

单个装配姿态的布局示例：

    PunchHitState (FrayHitState2D，直接放到唯一管理器下)
      ├── Hurtbox (FrayHitbox2D) → CollisionShape2D
      ├── Attackbox (FrayHitbox2D) → CollisionShape2D
      └── Pushbox (FrayHitbox2D) → CollisionShape2D

非攻击姿态省略 Attackbox；同类框允许多个矩形，不预留无用空框。判定依赖只在 StateDefinition 声明一次，经 HitStateDefinition 引用 PackedScene；不在招式资源重复保存 Node 实例。详细装配时机见 [判定系统动态装配方案](../../module_codes/my%20fray%20demo/docs/判定系统动态装配方案.md)。

### 必须遵守的结构规则

- **一个角色一个管理器**，两名角色各一个，不是整场对战共用一个。
- 每个 HitState 只创建实际需要的框。Stand（供 idle／walk 使用）、Jump 等非攻击姿态不创建 Attackbox；Hurtbox、Pushbox 也按玩法需要保留，可以只有其中一种。上图的非攻击姿态以同时保留 Hurtbox、Pushbox 为例。
- HitState 是管理器的**直接子节点**；实际存在的判定框是 HitState 的**直接子节点**。不要增加中间分组节点，插件不会递归查找其中的框。
- 推荐已有框按 **所有 Hurtbox → 所有 Attackbox → 所有 Pushbox** 的相对顺序排列，缺少的框直接省略，**不保留空位**。每个状态的位索引按实际框顺序单独计算；增删／重排框后必须同步修改该状态的掩码和逻辑时序配置。不要在这些直接子节点之间混入装饰或工具节点，避免 Inspector 标号与位索引混淆。
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
- 上面的 StandComposite 是可选替代布局，不会自动替换主树的 Stand。如果实际替换，需同步修改初始化常量与 idle／walk 的姿态掩码配置；不能继续使用原两框布局的 `3`。

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

因此不能跨状态共用固定的 `HURT = 1`、`ATTACK = 2`、`PUSH = 4` 作为类别位值。建议使用带布局／状态前缀的常量，逻辑时序中的掩码也按目标状态分别填写：

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

### 5.1 装配与运行分开

当前 Demo 的 fighter.gd 通过 FighterSMBuilder 收集已选基础状态和招式叶子，注入 context，使用 MANUAL 推进。当前尚未有判定定义字段和绑定流程，本节为后续接口约定，不提供一套替换现有初始化的第二实现。

1. 在 Manager ready 前，按最终 Loadout 解析依赖并实例化根为 FrayHitState2D 的 PackedScene，所有框初始关闭。
2. Manager ready 连接完整子节点的掩码与接触信号，建立 source。
3. Fighter ready 绑定状态定义、判定运行实例与角色组件，再进入真实初始状态。
4. 后续进入行为仅选择已有完整姿态；退出清理旧攻击段，不反复创建节点。

当前 Manager 没有完整运行时热注册 API；在其 ready 后 add_child 不保证接线，不能把编辑器 ChildChangeDetector 当作运行期注册器。

### 5.2 唯一的显示入口与判定写入者

当前实际显示入口保持：

    func play_animation(animation_key: StringName) -> void:
        sprite.play(animation_key)

待机／行走可自主播放。招式专用叶子通过未来的判定运行绑定选择姿态并写 active_hitboxes；资源中保存 PackedScene 或只读定义，不保存已实例化节点。不要直接从招式 ID 猜动态场景节点名。

状态内部的计时与命中记录独立于显示。结束条件来自逻辑帧，不连接图像结束来代替恢复帧结束。若将来需要延迟表现事件，携带动作代次并在结果应用前核验。

## 6. 动画与判定：逻辑帧主控，AnimatedSprite2D 显示

### 6.1 不沿用 Godot 3 Demo 的判定轨

本地参考 player.tscn 有 HitStates/HitState2D:active_hitboxes 属性轨，说明动画轨方案可行；但本项目已明确不采用它。当前角色不需要 AnimationPlayer 节点，也不建设动态动画轨路径绑定。

插件的 AnimationPlayer／AnimationTree tracker 是通用可选支持，保留其源码不意味着必须在角色场景创建节点。本项目不将其完成预测作为战斗时钟。

### 6.2 每招一套明确规则，不按按钮自动变体

每个特殊技使用作者固定方向序列与一个指定攻击按钮；同一招式 ID 不因换轻中重按钮自动得到三套帧数／伤害。每招默认独立路径和脚本，不按类别进入通用 Attack 叶子。

这属于本项目可读性与内容维护选择，不是其他输入体系必然不可预测的结论。脚本复用本身不会自动产生数值变体；公共计时、Movement 与清理工具仍可共享。

### 6.3 普通三阶段在一个叶子内推进

以固定 60 Hz、起手 5 帧、有效 3 帧、恢复 12 帧为例：

| 动作帧索引 | 阶段 | LightPunch 掩码示例 |
| --- | --- | --- |
| [0, 5) | startup | 5：Hurt 与 Push |
| [5, 8) | active | 7：Hurt、Attack 与 Push |
| [8, 20) | recovery | 5：关闭 Attack，保留身体 |
| 完成最后一帧后 | done | 允许正常退出，进入目标完整姿态 |

5／7 是 Hurt→Attack→Push 三框布局的局部示例，不是全局类别常量。六框 HeavySlash 可以用 39→47→63→55→39 表达近端／两框／尖端有效变化，仍然只是同一招式内部时序，不必增加五个行为状态。

动作索引从 0 开始，明确应用、推进、接触汇总与安全结算顺序；首帧不能在应用前先自增。物理查询不是任意时刻立即刷新，要用日志验证真实有效采样数，不以计数表替代运行验证。

FrayState 默认完成返回 true，专用招式叶子必须覆盖 _is_done_processing_impl()，恢复结束才返回 true。父组 AT_END 不会自动递归等待深层叶子，需要明确完成条件。

### 6.4 显示不反向控制战斗

基础移动继续使用 AnimatedSprite2D.play()。后续若攻击必须精确同步，可用同一动作逻辑进度映射 SpriteFrames 的 animation／frame，并关闭该次显示的自主播放；这是待实现适配，不需要 AnimationPlayer。

不使用 frame_changed／animation_finished、渲染帧率或图片数量决定判定、取消和恢复。换素材不能意外改变招式战斗数值。角色实际移动仍只通过 Movement，每个物理帧提交一次，不直接修改 CharacterBody2D.position 模拟攻击位移。

### 6.5 中断、清理与 Hitstop

- 正常完成、被打断、取消、自重入和销毁都有明确清理路径，不依赖动画末帧。
- 关闭攻击段一般只清掉 Attack 位；完整姿态还需要保留 Hurt／Push，目标状态进入时选择它的完整姿态。
- 不在碰撞信号回调中直接切换监测属性或递归转状态；记录接触与请求，在安全结算阶段处理。
- Hitstop 要明确冻结逻辑帧、图像推进、移动及结算的范围，并约定输入收集／过期策略；不能只停图像或只暂停计时器。
- 旧动作的延迟事件必须验证动作代次；新发动重置计时、命中列表、窗口和生成标记。

判定、取消、生成事件只允许一个逻辑写入者，不保留“动画轨辅助开框”的双写方案。本次仅移除空节点和统一文档，尚未实现攻击时序、精确帧映射或 Hitstop。

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

### 7.2 当前 Demo 的基础状态与招式入口

当前接入以 module_codes/my fray demo/scripts/fighter/fighter.gd 为准：

    var root := FighterSMBuilder.new().build(self, loadout)
    fighter_input.configure(controller, loadout.selected_moves)
    state_machine.initialize(context, root, loadout.entry_path)
    state_machine.advance_mode = FrayStateMachine.AdvanceMode.MANUAL
    state_machine.active = true

上面 context 是概念占位，实际代码注入 fighter、controller、fighter_input、movement 与 hit_state_manager。初始真实路径直接由 initialize 第三个参数进入，不新增 Boot，不额外 goto，不手工补调用进入回调。

- 基础输入产生 neutral/idle、fwalk、bwalk、crouch 的持续条件，不伪造每帧 Move。
- selected_moves 默认空；后续每个招式引用自己的叶子定义与脚本，entry_path 指向具体叶子。
- FighterInput 只识别固定 command、维护候选；Fighter._try_move() 检查来源、前置条件及完成条件后才 external 转移，成功后消费输入。
- 普通三阶段在叶子内部用逻辑帧控制；Fray.advance() 负责必要行为转换，不负责自动生成 startup／active／recovery 三个状态。
- 同一招式允许再发动时，测试 external 自转移退出与重入；不把复用脚本与输入强度版本绑定。
- 强制受击由战斗规则在统一安全入口处理，不能等待普通恢复完成；先关闭旧攻击段再进入新姿态。

本节替代旧“AnimationPlayer 完成信号＋Boot＋自动 PHYSICS Advancer”的最小示例。第 7.3 节起的原生 Advancer、标签与候选仲裁属于插件接入备选／历史机制说明，不是让当前 Demo 重新启用暂停的推进器，也不替换现有固定指令候选规则。数值优先级示例不是当前输入模块的实现。

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

- **先实现最小战斗闭环：**沿用第 7.2／7.8 节当前 Demo 的 FighterInput 候选与 MANUAL 统一推进；不重新启用暂停的 Advancer，也不再串联另一套 FrayInputBuffer。
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

### 7.8 基本输入与序列招式：固定指令候选与专用叶子

#### 7.8.1 内容资源

当前 Demo 使用 FighterCommandDefinition 和 FighterMoveDefinition。每个特殊技一套固定方向序列＋一个指定逻辑攻击按钮；例如 fireball 只使用 236＋light_attack，不自动将 236＋medium_attack／heavy_attack 解释为同招强度版本。帧数、伤害和判定配置有明确的唯一来源。

#### 7.8.2 每招专用行为

每个招式的 states 引用专属叶子定义，state_script 指向其专用脚本；entry_path 指向具体完整路径。普通三阶段在叶子内部推进。公共 Movement、基类和计时／清理工具仍可复用，输入版本并不决定脚本是否能够复用。

不再提供“一个可配置动作状态执行全部招式”的默认示例，也不将 AnimationPlayer 动画名作为动作完成依据。当前 Builder 只创建叶子实例，后续判定定义／数值绑定需要明确实现。

#### 7.8.3 输入识别

FighterInput 为 selected_moves 建立识别，按设备过滤并清洗相对方向。序列由 FraySequenceMatcher 识别，候选记录 move、来源、创建／就绪／过期帧。普通按钮、方向别名与特殊序列不重复计入同一输入。

#### 7.8.4 唯一提交入口

当前 Fighter.advance_commands() 依次尝试就绪候选。_try_move() 验证 allowed_from_paths、prereqs 与 AT_END 完成要求，再由经来源检查的 external 执行器进入具体叶子；接受后才消费，且本帧不再普通推进一次。

序列确认先于普通单键，同源组合键可在等待窗接管。按键周期已经归属特殊指令后，即使暂不能发动也不回退普通攻击。完全重复模式与严格前缀等冲突由作者避免；本项目不新增数值优先级评分或另一套通用 _dispatch 调度器。

#### 7.8.5 物理节拍与暂停

保持现有 FrayInput(-100) → FighterInput(-50) → 状态物理更新(0) → Fighter 普通／指令推进(50) 的顺序，状态机为 MANUAL，已有 FrayBufferedInputAdvancer 保持 paused。MANUAL 不表示状态叶子不再物理更新。

后续加入判定、命中停顿与接触结算时，必须明确各阶段顺序、同帧转换上限、输入缓冲过期策略和延迟动作代次；不以删除动画播放器推断已具备确定性模拟。

#### 7.8.6 普通连接与组级规则

move.transitions 和公共转换库只提供必要行为连接，端点是所属组直接子状态。不同招式的专属路径不能靠同路径后写覆盖。全局受击／标签规则仍需战斗前置条件，不能把同一攻击组内所有动作无条件视为可打断。

资源例子、当前限制和完整调用边界见 [固定招式输入接入说明](../../module_codes/my%20fray%20demo/docs/固定招式输入接入说明.md)。本节替代旧自动 Advancer＋通用动画动作状态方案，不表示攻击内容已经实现。

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

上面的 `match_found → buffer_sequence` 只展示插件原生接口，不用于当前 Demo。当前识别结果进入 FighterInput 候选，由第 7.8 节的 Fighter.advance_commands() 唯一提交；不再并联直接入队或额外 submit_sequence 入口。

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

计数必须只包含直接子 `FrayHitbox2D`，与第 3 节的实际位索引保持一致；不要用全部子节点数量代替。`is_hitbox_active(index)` 也建议采用相同的合法索引检查。整值赋值 `active_hitboxes = mask` 本身同样没有过滤不存在的位，因此逻辑时序掩码仍必须按实际布局填写，不是任意非零数都合法。

另外，本文件的 `get_hitboxes() -> Array[FrayHitbox2D]` 内部仍声明 `var array: Array`，与返回类型不一致；建议改成 `var array: Array[FrayHitbox2D] = []`，避免返回未类型化数组的类型问题。不要把 FrayInputMap 的数组修正当作所有同类返回值都已修好。

本文继续用 `state.active_hitboxes = mask` 表达整套姿态；辅助方法补齐检查后，可用于明确的单框操作，同一属性仍只有招式执行逻辑这一处写入者。

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

当前 `FrayAnimatorTrackerAnimationPlayer._process_impl(delta)` 仍通过 `current_animation_position + delta >= current_animation_length` 预测结束，尚未直接转发播放器的原生完成信号。它使用渲染更新的 delta，与本项目动作逻辑帧不一定同步，也未处理实际播放速度、倒放、循环和每次播放的去重。因此可能提前、重复或漏报结束，不能用这项基类修正证明它已经适合作为 60 Hz 战斗动作的结束依据。

当前 Demo 不使用 AnimationPlayer 节点，也不连接其完成信号决定战斗阶段；完成条件由招式逻辑帧给出。此处仅说明插件通用 tracker 的边界。如果以后完善 tracker，建议明确使用原生事件的转发与连接／释放生命周期，并验证循环、中断、重启动作、变速、暂停恢复和倒放。运行时添加动画库时，按动画命名的用户信号也需要额外注册；当前只在 tracker 的 `ready()` 中注册当时的动画列表。

### 11.8 状态转移与 Advancer：候选顺序、自动边与初始进入

以下为原生转换与当前 Demo 接入边界，不能只依据类注释或字段名称推断：

- **`priority` 不控制 `advance()` 的候选排序。** `get_next_transitions()` 先收集本地边，再追加可用全局边；`get_next_state()` 按该顺序找到第一条可转移边即返回。`priority` 在 `_get_transition_priority()` 中用于寻路成本，不等于 Advancer 的输入队列优先级。相同输入的多条边优先设计为互斥条件；确实要竞争时明确构建顺序并测试，不能只改 priority 数字。
- **`auto_advance = false` 不等于“自动更新绝不会走这条边”。** 状态机自动更新调用 `advance({})`，当前 `_can_advance()` 首先检查 `transition.accepts(input)`；auto_advance 为 true 时才额外检查 advance_conditions。基础转移默认接受所有字典，所以普通无条件边即使没有开启 auto_advance，也可能被空输入或玩家输入走通。必须正确配置 `prereqs`、转移类型与 accepts 语义；当前 Demo 的 MANUAL 模式集中控制普通 advance 调用，具体规则仍需按 accepts 与条件语义配置。
- **空输入自动边与输入消费不是同一件事。** Advancer 以 `state_machine.advance(sm_input)` 返回 true 作为已消费依据，不知道实际走的是否为期望的按键边。不要把“走到 Idle”误认为“预输入的拳成功执行”；暂停消费与空字典专用完成边需一起设计。
- **使用修复后的真实入口初始化。** 当前源码支持 initialize(context, root, entry_path)，先 ready 再按目标路径进入，最终叶子进入一次。当前 Demo 不再使用 Boot＋goto 的兼容方案。同招 external 重入仍要验证计时、命中记录与退出清理。
- `register_conditions()` 设置的是整张条件表，多次调用会替换前一次注册内容；构建时合并一次传入。条件无副作用，资源消耗在进入目标状态后处理。
- 不要在开启 Advancer 自动 Physics 更新的同时，又手动反复调用同一输入的 `state_machine.advance()`；这会形成两个消费入口。若需要严格单步调度或按动作帧保存失败请求，应在游戏层设计统一调度，不把默认组件当成已实现回滚或严格单帧单转移保证。

## 12. 实施步骤与验收清单

推荐先完成一个最小闭环，再扩展复杂招式：

1. 安装插件并确认没有脚本解析错误，建立推荐节点树。
2. 创建三类属性资源和碰撞层，初始化只启用 Stand 的受击／推挤。
3. 在项目设置 → 输入映射中配置双方 action 和键位，初始化时用 `add_bind_action()` 桥接；再实现左右移动、蹲下、跳跃、朝向，检查框随姿势切换。
4. 建好 idle／punch 图片和完整判定场景，按 Loadout 装配；接入专用 PunchState，以逻辑帧驱动 5→7→5 掩码（对应三框布局），返回时选择 Stand 的 3，不制作判定属性轨。
5. 连接管理器进入事件，先记录接触，再加入命中去重和统一结算。
6. 实现持续推挤和墙角处理，避免角色互相穿透或重复分离。
7. 增加防御、高低段、硬直、取消、倒地、起身和命中停顿。
8. 经过输入专项测试后，再加入必杀技、蓄力、多段攻击和弹体。

### 结构检查

- [ ] 每个角色只有一个 FrayHitStateManager2D。
- [ ] 每个 HitState 只包含所需的直接子框；非攻击姿态无需 Attackbox，掩码按各状态实际框顺序计算，增删／重排后已同步更新逻辑掩码配置。
- [ ] 每个框都有有效形状、非空 attribute、正确 Layer／Mask。
- [ ] 已明确选择独立多框还是单框多形状；独立框均为 HitState 直接子节点，子形状不计入 active_hitboxes 位数。
- [ ] 多框布局的初始化、阶段逻辑与中断清理一致；六框 HeavySlash 的被动／全有效掩码为 39／63，未误用三框布局的 5／7。
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

- [ ] 第 7.2／7.8 节沿用同一套 FighterInput 候选接入，事件只连接一次，不从另一入口重复入队。
- [ ] initialize 的真实入口确实进入 neutral/idle 一次并播放待机，不保留 Boot 兼容步骤。
- [ ] 相同 punch 请求根据地面／蹲姿条件只选一个目标；新增招式只扩展映射与规则，不新增状态名称分支链。
- [ ] 攻击前摇不消费普通输入，合法窗口才尝试；失败请求会丢弃、暂停期间仍会过期的行为符合设计。
- [ ] 自动完成边只接受空字典，不把待执行攻击请求当作返回 Idle 的输入吞掉。
- [ ] 指令与普通拳经过唯一仲裁入口，236P 不会同时留下一个额外 punch；相同输入的竞争不依赖 priority 自动排序。
- [ ] 同组 236P 有气出必杀、无气退回合法普通拳，消费时只扣一次气；无合法候选时按策略丢弃。
- [ ] 关闭窗口时保留整组但不续期；转交 Advancer 后仍使用原时间戳，暂停／改键／换设备会清掉两层待处理记录。
- [ ] 持续移动／防御不逐帧入队；方向采样先于本步按钮、同时按键顺序与换边中断规则符合设计。
- [ ] 未命中确认／窗口外不能取消；合法取消只进入目标一次，退出旧状态时清理判定与旧窗口。
- [ ] 开启标签全局边后，仅允许被标记的源状态取消，受击／倒地不意外出招。
- [ ] 已记录并验证输入采样、叶子逻辑帧、MANUAL 转换与安全结算顺序，不启动第二个消费入口。

### 自定义按键专项检查

- [ ] 已按同目录《Fray_键盘与手柄自定义按键接入指南》第 9 节覆盖键盘、手柄按钮、摇杆方向、死区、冲突、保存／取消／恢复默认。
- [ ] 双人同键盘、键盘 + 手柄、双手柄互不串输入；仅连接非 0 手柄及拔插设备 0 时，Fray 采样与设备认领正常。
- [ ] 改键不删除其他绑定槽或重建 Fray 输入名称；重启加载与损坏配置回退正常。
- [ ] 菜单输入不会进入战斗队列；应用或切换通道后已完成物理采样、清理历史并确认中立，恢复对战不误触发攻击／蓄力。

### 动画与逻辑时间专项检查

- [ ] 当前角色没有未使用的 AnimationPlayer 节点及业务节点引用。
- [ ] 显示使用 AnimatedSprite2D；普通移动继续 sprite.play()，精确攻击显示适配若需要则明确实现。
- [ ] 每招固定 command、专用叶子／脚本和一套明确基础数值，不自动创建轻中重版本。
- [ ] 普通三阶段由单叶子逻辑帧推进，不依赖图片数或动画完成信号。
- [ ] 起手／恢复保留 Hurt／Push，active 按实际布局打开 Attack 位。
- [ ] 恢复结束前完成判定为 false；父组退出条件也已明确。
- [ ] 正常结束、中断、取消、自重入清理完整，旧延迟结果不能写入新动作。
- [ ] Hitstop 明确暂停逻辑与图像，并验证输入／接触策略。
- [ ] 判定定义按 Loadout 装配；Manager 在 ready 时完成子姿态接线，或有明确注册 API。

### 常见问题速查

| 症状 | 优先检查 |
| --- | --- |
| 插件类名冲突或加载了非预期代码 | 目标工程是否扫描到多个 Fray 副本，实际资源路径是否正确 |
| 找不到框的属性资源入口 | 检查 FrayHitbox2D 的 attribute 属性，单数 |
| 只调用 activate 却没有框 | 应赋值 active_hitboxes，不是只显示状态 |
| 写 0 后没切到新状态 | 零掩码不会选中目标，动作开头应写入该状态的非零掩码 |
| 从全关状态无法逐个开启框 | 检查是否仍加载旧版边界判断；当前根目录已移除该判断，但仍需验证实际索引合法 |
| 刚进入就收到 separated | 当前根目录接线已修正；检查运行副本、重复连接以及同帧停用／切换状态 |
| 精灵与判定不同步 | 是否把自主显示进度当作战斗时钟，Hitstop 是否只停一方，精确攻击是否已做逻辑帧映射 |
| 攻击被打断后判定残留 | 是否在专用叶子退出关闭攻击段／窗口；不能依赖图片末帧或只停止显示 |
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

**最终方案：每个招式固定输入与明确基础数值，默认专用行为叶子／脚本；叶子内部逻辑帧统一驱动阶段、判定与完成，AnimatedSprite2D 显示，唯一 HitStateManager 管理按 Loadout 装配的完整姿态，游戏层统一结算。当前 Demo 不使用 AnimationPlayer 节点。**
