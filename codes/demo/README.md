# Fray Fighter Demo

默认场景：

```text
res://scenes/fray_fighter_demo.tscn
```

当前版本使用**固定键位、固定默认 loadout 和静止对手**。不提供 F1 自定义键位、招式安装/卸载、指令录制、配置存档或启用中的 CPU 对战逻辑。

## 设计与开发文档

- [文档中心](docs/index.md)：游戏项目常见文档清单与本 demo 阅读路径。
- [游戏设计文档](docs/game-design.md)：定位、核心循环、规则、控制、HUD 与范围。
- [战斗设计与数值规格](docs/combat-design.md)：指令、招式数据、格挡、连段、juggle 与接触顺序。
- [架构说明](docs/architecture.md)：Fray 输入、状态机、hitbox、buffer clock 与组件边界。
- [内容制作工作流](docs/content-workflow.md)：新增 melee/projectile move 的资源与校验流程。
- [测试与验收计划](docs/test-plan.md)：静态门禁、功能矩阵和发布检查。
- [路线图](docs/roadmap.md)：当前基线、缺口和后续优先级。

## 默认键位

| 动作 | 键位 |
|---|---|
| 左 / 右 | `A` / `D` |
| 跳跃 | `W` |
| 下蹲 | `S` |
| 轻击 | `J` |
| 重击 | `K` |
| 特殊攻击 | `L` |
| 防御 | `;` |
| 招式表 | `M` |
| 重新开始 | `R` |

键位直接来自 `project.godot` 的 `p1_*` InputMap action，运行时不会读取或保存用户自定义映射。

## 默认招式

按 `M` 可以在战斗中打开或关闭招式表。招式表直接读取当前 `DemoFighterLoadout` 的指令、组合父级和取消目标，不维护另一份 UI 专用招式数据。

### 基础攻击与组合技

| 招式 | Fray 指令 | 面向右时默认键位 |
|---|---|---|
| Light / Heavy / Special | 对应攻击输入 | `J` / `K` / `L` |
| Sweep | `down + heavy` | `S + K` |
| Launcher | `down + special` | `S + L` |
| Air Light / Heavy / Special | 对应攻击输入 | `J` / `K` / `L` |
| Two-Hit Verdict | `light -> heavy` | `J -> K` |
| Broken Oath | `light -> light -> heavy` | `J -> J -> K` |
| Forward Judgment | `forward + light -> heavy` | `D + J -> K` |

### 特殊技

| 招式 | Fray 指令 | 面向右时默认键位 |
|---|---|---|
| Rising Uppercut | `forward -> down -> down + forward + light` | `D -> S -> S + D + J` |
| Ground Wave | `down -> down + forward -> forward + special` | `S -> S + D -> D + L` |
| Shadow Kick | `back -> forward + heavy` | `A -> D + K` |

`forward` / `back` 是相对角色朝向的语义方向，换边后由 `FrayConditionalInput` 自动镜像。项目不使用松键小跳；跳跃高度固定。

### 组合技取消特殊技

在组合技当前段的取消窗口内完成特殊技指令，可以直接取消进入特殊技。例如面向右时：

- `J -> K ~ S -> S + D -> D + L`
- `J -> J -> K ~ D -> S -> S + D + J`
- `D + J -> K ~ A -> D + K`

其中 `~` 表示取消，不是额外按键。

## 战斗时序约定

- 攻击的 startup、active、cancel 和总时长都以 `FrayAttackAttribute` 的 gameplay frame 数据为准。
- `AnimationPlayer` 只负责攻击视觉，不再用动画结束信号提前结束攻击状态。
- 空中攻击接地时通过 Fray immediate transition 进入统一 `land` 状态；不会绕过落地恢复直接进入 `idle`。
- `FrayBufferedInputAdvancer` 使用随选定 process/physics `delta` 推进的 gameplay clock。hitstop 时只冻结 buffer aging，仍允许输入进入缓冲。
- 近战和 projectile 都通过 `DemoFighterAttackModule.try_resolve_contact()` 结算接触。只有 `receive_hit()` 成功后才记录命中目标；被 knockdown/recovery 无敌或 juggle 限制拒绝的接触不会提前消费目标，也不会让 projectile 消失。

## Fray 输入与命中链路

```text
project.godot InputMap p1_*
  -> FrayInputMap
  -> FrayController
  -> facing/composite inputs
  -> fixed DemoMoveCommand resources
  -> FraySequenceTree
  -> FrayBufferedInputAdvancer
  -> Fray press/sequence transition
  -> DemoMoveDefinition
  -> FrayHitbox2D.attribute
  -> FrayAttackAttribute
  -> DemoFighterAttackModule.try_resolve_contact()
  -> DemoFighter.receive_hit()
```

- 单键招式使用 `transition_press_global()`。
- 地面波、升龙和 dash 使用 `transition_sequence_global()`。
- 同一步组合继续使用 `FrayCombinationInput`。
- 攻击数值只读取 strike `FrayHitbox2D.attribute` 上的 `FrayAttackAttribute`，不维护第二套攻击数据。

## 目录组织

- `assets/sprites/`：demo 专用角色贴图；对应 `.import` 文件随源图保留。
- `scenes/fighters/`：角色主体场景。
- `scenes/hitboxes/`：固定招式使用的 Fray hit-state 场景，直接实例化在 fighter 场景中。
- `scripts/stage/core/`：舞台协调；`scripts/stage/ui/`：HUD 和招式表格式化。
- `scripts/fighter/`：按 `core`、`combat`、`input`、`movement`、`state_machine` 拆分角色功能；动画直接由 fighter 场景的 `AnimationPlayer` 轨道提供。
- `scripts/fighter/state_machine/states/`：按 `locomotion`、`combat`、`reaction` 分类并由 Fray 状态机统一注册的 `FrayState` 子类。
- `scripts/resources/`：按 `fighter`、`moves`、`combat` 分类的 demo Resource 类型定义。
- `resources/`：攻击、招式、固定角色 loadout 与环境参数实例。

## 主要文件

- `scripts/stage/core/demo_stage.gd`：创建固定配置的玩家和静止对手，并连接 HUD。
- `scenes/fighters/demo_fighter.tscn`：角色主体及 Fray controller/state/hit 组件节点。
- `scripts/fighter/core/demo_fighter.gd`：角色门面和组件装配。
- `scripts/fighter/input/demo_fighter_input_setup.gd`：将固定 InputMap action 接入 Fray，构建组合输入和序列树。
- `scripts/fighter/state_machine/demo_fighter_state_machine_builder.gd`：构建 Fray 状态、tag、rule 和 transition。
- `scripts/fighter/combat/demo_fighter_attack_module.gd`：直接安装招式、读取 strike 攻击属性，并统一管理 Fray 攻击框、接触过滤和目标缓存。
- `scripts/fighter/combat/demo_fighter_combat_resolver.gd`：根据 `FrayAttackAttribute` 处理格挡、伤害、连段、硬直、倒地、hitstop 和 KO。
- `resources/fighters/default_fighter_loadout.tres`：固定默认招式与固定指令。
- `scripts/stage/ui/demo_hud.gd`：显示血量、状态、连段、招式表和固定控制提示。

## 手动验证

在 Godot 中运行 `res://scenes/fray_fighter_demo.tscn`，至少验证：

1. `A/D/W/S` 移动、固定高度跳跃和下蹲正常；松开 `W` 不会触发小跳截断，离地后按左右也不能修正或反转既有水平轨迹。
2. `J/K/L` 与 `;` 分别触发轻击、重击、特殊攻击和防御。
3. 面向右时输入 `S -> S + D -> D + L` 可以触发 Ground Wave；在仍按住 `S + D` 时按 `L` 也应识别。
4. 面向右时输入 `D -> S -> S + D + J` 可以触发 Rising Uppercut；斜下前和 `J` 同帧按下或先到斜下前再按 `J` 都应识别。
5. 面向右时输入 `A -> D + K` 可以触发 Shadow Kick。
6. 角色换边后，三个特殊技的 `forward` / `back` 自动镜像。
7. `J -> K`、`J -> J -> K`、`D + J -> K` 三条组合技都能稳定派生，且后续段不能从 neutral 单独触发。
8. 三条组合技末段都能在取消窗口内取消到 Rising Uppercut、Ground Wave 或 Shadow Kick。
9. 在 hitstop 中提前输入取消指令，确认暂停结束后仍可在 gameplay cancel window 中消费，buffer 不因真实时间经过而过期。
10. 使用任一空中攻击落地，确认角色先进入 `land` 并完成统一落地恢复，而不是直接进入 `idle`。
11. 让 projectile 接触 knockdown/recovery 无敌或被 juggle 限制拒绝的目标，确认 projectile 不会因失败接触提前消失；成功结算后才消失。
12. `M` 可以打开/关闭招式表；`R` 可以重新开始场景；HUD 不显示 F1 自定义配置入口。
13. 让双方在舞台中央和墙角分别发生 pushbox 重叠，确认中央双方均分分离距离，墙角剩余位移由未被边界阻挡的一方承担。
