# 迁移清单

## 可复用

- `scripts/combat/combat_core_match.gd`：批量接触、稳定排序、去重、ComboContext、meter、KO。
- `scripts/fighter/combat_core_fighter.gd`：hurtbox 上报、集中反应、hitstop、只读快照，以及 Amplify 气条原子支付入口。
- `FrayAttackAttribute` 的 `amplify_target_state`、`amplify_start_frame`、`amplify_end_frame`、`amplify_meter_cost`：把状态内强化目标、窗口与消耗留在攻击唯一数据源。
- `scripts/projectile/combat_core_projectile.gd`：Fray projectile strike 与实例 token。
- `scripts/combat/combat_rule_set.gd` 与 `resources/combat/combat_rules.tres`。
- `scripts/debug/combat_hitbox_debug_draw.gd`：训练判定框显示。

## 依赖

- Fray 2.0.0-alpha：Controller、InputMap、BufferedInputAdvancer、StateMachine、HitState2D、Hitbox2D、AnimationObserver、AnimatorTrackerAnimationPlayer。
- InputMap：`p1_*`、`p2_*`、`combat_reset`、`debug_hitboxes`。
- Autoload：`FrayInputMap`、`FrayInput`。
- 物理层：World=1、Fighter=2、Strike=3、Hurtbox=4。

## 不直接迁移

- 当前按键布局和双人键盘测试夹具；
- `CombatDebugOverlay` 的学习型排版；
- 当前固定的 `后、前、轻拳` 波动指令、普通波启动 `0..11F` 内按防御的 Amplify 操作、地面/空中 `J → K → L` 字符串与 L launcher；正式项目可保留 Fray sequence、press transition、attribute window/cost 和 hit-confirm 结构，并替换具体招式资源与按键；
- 方块美术、空动画和当前数值样例。
