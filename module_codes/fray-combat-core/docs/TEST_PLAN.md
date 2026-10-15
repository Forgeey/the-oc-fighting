# 02 Fray Combat Core 测试计划

> 当前机器没有可用的 `godot` / `godot4` PATH。本文件给出引擎可用后的手动验证步骤；当前实现阶段只执行静态检查。

## 启动

```powershell
<Godot可执行文件> --path "C:\Users\10720\Desktop\fray测试\codes\fray-combat-core"
<Godot可执行文件> --headless --path "C:\Users\10720\Desktop\fray测试\codes\fray-combat-core" --quit
```

## 测试用例

| ID | 步骤 | 预期 |
|---|---|---|
| COMBAT-001 基础命中 | P1 靠近 Training Dummy，按 `J` | strike 红框只在 active 帧出现；木偶扣血、播放 hurt 动画并进入 Fray hitstun；日志含 `stand_light` |
| COMBAT-002 木偶禁用输入 | 尝试按 P2 键 `F/H/T/G/N/M/,/B` | 木偶不移动、不攻击、不防御、不发射投射物，仍保持自动朝向 P1 |
| COMBAT-003 轻中重攻击 | P1 靠近木偶分别按 `J`、`K`、`L` | 分别进入轻、中、重攻击状态；K 与 L 均播放 `attack2_strip31.png`，L 的伤害与击退高于 K，且 L 将地面木偶明显浮空 |
| COMBAT-004 倒地起身 | P1 蹲下按 `L` 命中木偶 | 木偶进入 `knockdown`，倒地计时结束后自动经过 `wakeup` 回到中立 |
| COMBAT-005 数据化取消 | P1 贴近，提前拨号 `J → K → L`；再测试第二段 clean hit 后输入相对方向 `后 → 前 → J`，并在普通波启动窗口按 `;`；同时测试第二段挥空/被格挡 | J → K 在资源取消窗进入第二段；第二段 clean hit 可转入 L launcher 或普通波，普通波可继续 Amplify；挥空/格挡不可继续；L 命中后可跳起追击 |
| COMBAT-006 浮空/juggle | 用站立 `L` 浮空，跳起用空中 `J → K → L` 追击，再尝试用任意攻击命中低空目标 | 每次合资格空中命中读取该 attribute 的 `airborne_launch_y_velocity` 产生小幅续浮；HUD 显示 juggle；连续滞空时重力和最大下落速度逐渐提高；落地后重置；超过 `juggle_limit` 的接触被拒绝并记录 |
| COMBAT-007 近战去重 | 保持双方重叠，观察一次 active 窗口 | 同一 attack token 对木偶只结算一次，dedupe/log 可观察重复过滤 |
| COMBAT-008 普通/强化波 | 拉开距离；两种朝向执行相对方向 `后 → 前 → J`。分别在普通波施法第 `0F`、`11F`、`12F` 和投射物生成后按 `;`，并观察气条与动画 | `0..11F` 内且气条不少于 `1000` 时进入 `enhanced_projectile` 并扣除 1 格；`12F` 或生成后输入不强化也不扣气；Amplify 不重播动画、不重置施法计时，普通/强化波都在第 `14F` 生成；速度/伤害分别为 `360/8` 与 `520/12`，首次合资格接触后销毁 |
| COMBAT-009 受击中断 | 木偶处于 idle、wakeup 等可受击流程时命中 | 反应统一通过 Fray `goto()` 进入 hitstun/knockdown/KO，不产生平行状态系统 |
| COMBAT-010 KO | 持续攻击木偶到 0 HP | 木偶生命归零并进入 Fray `ko`，不再接受玩家控制 |
| COMBAT-011 hitstop | 观察命中后状态与 HUD hitstop F；让处于 J/K 首击中的角色在 hitstop 批次被打断 | 双方按 attribute 指定帧冻结；恢复后状态继续；P1 输入缓冲年龄冻结；攻击状态退出不会提前解除 hitstop 的输入暂停 |
| COMBAT-012 动画观察 | 切换 idle/attack/hurt/ko | Fray tracker 产生动画事件；所有图片序列按 34 FPS 播放，改变动画长度不改变 60 Hz strike active 帧 |
| COMBAT-013 换边转身 | 从训练木偶上方越过并落到另一侧 | 角色立即镜像，播放复用下蹲序列的 `turn`，结束后恢复当前状态动画 |
| COMBAT-014 换边攻击框 | 换边后分别执行 J/K/L 与蹲、空中攻击，并开启 Z 判定显示 | 红色 strike 框只出现在角色当前面朝方向，不发生双重镜像抵消 |
| COMBAT-015 中断清理 | 攻击 active 时按 `R` | 全部 strike 关闭、投射物清理、ledger/combo 清空、双方恢复 100 HP，木偶输入仍禁用 |
| COMBAT-016 长跑 | 连续攻击与发射投射物 10 分钟 | ledger 旧项回收，无重复信号增长和残留投射物 |
| COMBAT-017 上升穿越 | 从地面对手前方前跳或二段跳，并在上升阶段穿过其 pushbox | `jump` / `double_jump` 上升时不产生水平阻挡，可越过对手中心；空中框仍保持较小 profile |
| COMBAT-018 下落恢复 | 越过对手中心后等待进入 `fall` 并与其 pushbox 重叠 | 下落阶段恢复双方 pushbox 分离，落地后不会保持共位 |
| COMBAT-019 空中受击 | 让处于上升或空中的角色进入 `air_hitstun` 并与地面对手重叠 | `air_hitstun` 不享受主动穿越豁免，仍执行正常 pushbox 推挤 |
| COMBAT-020 空对空 | 让双方同时跳跃并使空中 pushbox 重叠 | 空对空始终执行 pushbox 分离，不因任一角色上升而互相穿透 |

| COMBAT-021 HIGH 蹲姿闪避 | 将木偶暂时设为可控或通过调试入口保持主动蹲姿，用 P1 站立 `J`/`K` 攻击 | `HIGH` 不建立接触、不扣血、不进入格挡；若 active 帧内木偶站起，后续重叠仍可重新接触 |
| COMBAT-022 MID 防御 | 分别以站防和蹲防承受站立 `L`、普通波、强化波 | 三者均可被两种地面防御挡住，进入 blockstun |
| COMBAT-023 LOW 防御 | 分别以站防和蹲防承受任一下蹲攻击 | 站防被命中；蹲防成功格挡 |
| COMBAT-024 OVERHEAD 防御 | 分别以站防和蹲防承受任一空中攻击 | 站防成功格挡；蹲防被命中 |
| COMBAT-025 UNBLOCKABLE | 通过现有 debug knockdown 入口分别攻击站防与蹲防目标 | 两种防御都失败并按 clean hit 结算 |

## 静态验收

- fighter `CharacterBody2D` 只碰撞 World；Fighter/Fighter pushbox 由 `CombatCoreMatch` 统一解析，判定框覆盖层可显示 push/hurt/strike；
- 所有 `.gd/.tres/.tscn/.godot/.cfg` 为 UTF-8 无 BOM；
- `.tres/.tscn` 第一个字节是 `[`；
- strike 场景的 `attribute` 为 `FrayAttackAttribute` 资源；
- `GuardType` 数值迁移一致：HIGH=0、MID=1、LOW=2、OVERHEAD=3、THROW=4、UNBLOCKABLE=5；
- `stand_light` 仅声明 `stand_combo_medium`；`stand_combo_medium` 以 `ON_HIT` 声明 `stand_heavy` 与普通波 `projectile`，不直接声明 `enhanced_projectile`；
- 普通波 sequence 为 `后 → 前 → J`；`projectile -> enhanced_projectile` 由 Fray guard press transition 和普通波 attribute 的 `0..11F` Amplify 窗口表达；
- 普通波 attribute 声明 `amplify_target_state = enhanced_projectile`、窗口 `0..11F` 和消耗 `1000`；普通/强化资源共享 `36F` 施法时长与第 `14F` 生成帧；
- 初次进入和回合重置后双方 `meter == 1000`（HUD 显示 1 格）；气不足时 Amplify transition 不成立且不扣气；
- 所有 `res://` 引用存在；
- 项目层没有第二份 damage/hitstun/blockstun/knockback 表；
- `project.godot` 物理频率为 60 Hz，Fray autoload 与插件启用。
