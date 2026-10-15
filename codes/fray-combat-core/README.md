# 02 Fray Combat Core

这是 TDD 第 2 组（02、03、05）的独立 Godot 4.7 / Fray 2.0.0-alpha 学习项目。项目以第 1 组 Fray fighter 状态机为底座，新增固定 60 Hz 的双角色战斗闭环：命中、格挡、连段缩放、气条、hitstop、击退、浮空、倒地、投射物、KO、动画观察与判定诊断。

- 入口：`res://scenes/main.tscn`
- 唯一具体 Fighter 场景：`res://scenes/combat_core_fighter.tscn`
- Tick 协调器：`scripts/combat/combat_core_match.gd`
- Fighter 战斗薄层：`scripts/fighter/combat_core_fighter.gd`
- 共享规则：`resources/combat/combat_rules.tres`
- 攻击唯一来源：`resources/attacks/*.tres`，直接挂在 strike `FrayHitbox2D.attribute`
- 双时钟约束：动画图片序列统一按 34 FPS 播放；游戏逻辑与判定固定按 60 Hz 物理帧运行
- 投射物：`scenes/projectiles/combat_core_projectile.tscn`
- 软件设计与架构图：`docs/SDD.md`
- 实现设计与时序/状态图：`docs/TDD.md`
- 测试计划：`docs/TEST_PLAN.md`

## 操作

| 角色 | 移动/跳/蹲 | 轻/中/重 | 防御 | 普通波 / 强化波 |
|---|---|---|---|---|
| Player 1 | `A/D`、`W`、`S` | `J/K/L` | `;` | 普通波：相对方向 `后、前、J`；强化波：普通波启动 `0..11F` 内按 `;` |
| Training Dummy | 不可控制 | 不可控制 | 不可控制 | 不可控制 |

- Player 2 已配置为训练木偶：不读取玩家输入，但仍会正常受击、击退、浮空、倒地、起身和 KO。
- 初次进入和按 `R` 重置回合时，双方气条初始值均为 `1` 格（内部值 `1000`）。
- `R`：重置回合、生命、气条、连段、投射物和 Fray 状态，并让训练木偶回到初始位置。
- `Z`：显示/隐藏绿色 pushbox、蓝色 hurtbox 与红色 strike hitbox。

## 可验证规则

1. **攻击唯一来源**：damage、chip、hitstun、blockstun、hitstop、击退、浮空、juggle、倒地、气条收益、取消规则和投射物速度均来自实际 strike 上的 `FrayAttackAttribute`。
2. **批量结算**：strike 主动检测 hurtbox 后只把接触放入队列；`CombatCoreMatch` 按稳定键排序整个批次后分阶段提交，支持同帧互击与双 KO。
3. **重复命中过滤**：去重键为 attacker、defender、攻击实例 token 与 hit id；近战一次攻击实例和一枚投射物对同一目标最多结算一次。
4. **防御段位**：站防/蹲防由 Fray guard 状态表示。`HIGH` 可站防且会被主动蹲姿闪避；`MID` 可站防或蹲防；`LOW` 只能蹲防；`OVERHEAD`（越头）只能站防；`THROW` 与 `UNBLOCKABLE` 不可防御。当前下蹲攻击为 `LOW`，空中攻击为 `OVERHEAD`，站立重击与两种波为 `MID`。
5. **真人快打式字符串**：取消窗口、接触条件和目标状态仍来自 attribute。地面可提前拨号 `J → K → L`：J 进入固定 K 二段，第二段 clean hit 后可接 L 浮空重击或普通波 `后 → 前 → J`；普通波进入施法后可在 Amplify 窗口按 `;` 转为强化波。空中 clean hit 可按 `J → K → L` 续接。
6. **Amplify 强化波**：先以 `后 → 前 → J` 进入普通波施法，再于施法第 `0..11F` 按 `;`，支付 `1000` 气（1 格）后转为强化波；不要求攻击键与防御键同帧。状态切换不会重播动画或重置施法计时，两种波都在第 `14F` 生成投射物。普通波速度/伤害为 `360 / 8`，强化波为 `520 / 12`；除 ID、速度和伤害外沿用相同战斗字段，没有额外硬直、击倒、多段或特效。两种施放动画均复用 `attack2_strip31.png`。
7. **浮空连段**：站立 L 的地面 `launch_y_velocity` 提高为主力 launcher；每个攻击资源都配置 `airborne_launch_y_velocity`，对已浮空目标产生较小向上续浮。连续空中命中使用既有 `air_hitstun_decay` 缩短硬直，并按空中命中次数与持续滞空时间逐渐提高重力和最大下落速度，落地后重置。
8. **动画同步**：状态变化播放 34 FPS 的轻量 `AnimationPlayer` 图片序列；轻攻击使用 `attack1_strip24.png`，中/重攻击、中攻击组合技及两种波使用 `attack2_strip31.png`。`FrayAnimationObserver` 只发布表现事件；攻击判定仍按 60 Hz attribute 固定帧运行。
9. **KO**：生命降至 0 后通过 fighter 的集中反应网关进入 Fray `ko` 状态；同 tick 双方归零会发布双 KO 事件。
10. **Pushbox 穿越**：站立、蹲伏和空中使用不同矩形 profile；带 Fray `pushbox_rising_pass` tag 的主动空中状态仅在上升时忽略地面对手，下落、`air_hitstun` 与空对空恢复统一 pushbox 分离，不切换角色 collision layer/mask。

## 目录边界

- `scripts/combat/`、`scripts/projectile/`、`scripts/debug/`：第 2 组项目薄层。
- `scripts/fighter/`：复用并扩展第 1 组 Fray fighter 状态机。
- `addons/fray/`：同一 Fray addon；通用 `FrayAttackAttribute` 承载防御段位、取消规则、投射物速度及既有战斗字段，没有把项目私有结算器塞入 addon。
- `FOUNDATION_BASELINE.md`：第 1 组项目的历史快照；其中记录的独立 Foundation 演示场景不属于当前项目运行结构，当前只保留其基础脚本供 `CombatCoreFighter` 继承。

## 已知限制

- 本组不实现投技/拆投、精准防御、护甲、clash、舞台换场、回合计时、AI 或联网回滚。
- 当前工作区已注明 `godot`/`godot4` 不在 PATH，因此实现阶段只能做文本、引用和资源静态检查；需用户提供 Godot 可执行文件路径后再执行引擎启动验证。