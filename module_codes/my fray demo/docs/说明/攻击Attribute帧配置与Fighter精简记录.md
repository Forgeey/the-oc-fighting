# 攻击 Attribute 帧配置与 Fighter 精简记录

> **2026-11-09 合并更新：**已删除 FighterAttackAttribute 脚本，帧配置统一放在 FighterHitboxAttribute，按 kind=ATTACK 选用。旧文提到派生攻击 Attribute 的段落为历史；一个 Matcher 和相对前后指令的简化条件见[统一 HitboxAttribute 与 Matcher 简化边界](统一HitboxAttribute与Matcher简化边界.md)。当前跨转向世界历史规则未改变。

> 2026-11-08 完成。本文优先于旧说明中“Move 保存帧数／Builder 绑定 move／Attribute 时间字段尚未迁移”的历史段落。只影响 `module_codes/my fray demo` 业务代码；Fray 的一行类型修复同时同步至根 `addons/fray`。

## 1. Move 不再保存动作时间

已从 `scripts/moves/fighter_move_definition.gd` 删除 startup_frames、active_frames、recovery_frames 及 total_frames()。它仍保存选招身份、固定 command、状态依赖和公共条件，不保存动作运行进度。

新增 `scripts/hit/fighter_attack_attribute.gd`／FighterAttackAttribute，继承现有 FighterHitboxAttribute，默认 kind=ATTACK，只保存只读时间配置。total_frames() 和 is_active_at(frame) 属于这份配置，不再属于 Move。

轻攻击判定场景的 Attackbox 使用该 Attribute，并显式配置 10／4／10。没有改 Hurt／Push 的类型或默认有效位。

## 2. 攻击状态自行查询、计时和开关框

BasicAttackState 进入时先 super-enter 选中本状态判定姿态，再从 context 的 hit_state_manager.get_current_state_obj() 取得框列表和实际 Attribute。无须 Fighter 传 move，也无须 Builder 把招式绑定到攻击状态。

- elapsed_frames 是本状态实例的字段，绝不写入共享 Attribute。
- 开启区间采用 `[startup, startup+active)`：当前轻攻击在 elapsed_frames=10 时开启，在 14 时关闭，在 24 时完成恢复。
- 每个攻击框按自己的 Attribute 开关对应位；默认 Hurt／Push 掩码一直保留，不在有效期结束时关闭整套姿态。
- 多攻击框时，动作总时长取所有属性完整起手＋有效＋恢复的最大值；没有打开的窗口不等于动作已经完成。需要更复杂整招时间轴以后另行定义，当前不引入另一份 Move 帧配置。
- 状态退出／中断依旧立即清理姿态；重入重新计时。计时配置共享不导致运行计时或掩码共享。
- 动作完成与朝向权限仍是玩法行为：恢复结束才允许正常转向。

## 3. hit_states 重命名

FighterHitStateBuilder.hit_state_by_definition 已统一改为 hit_states。Fighter 内原先的 _hit_state_definition 映射也改为 hit_states，含义仍是 `Dictionary[FighterHitStateDefinition, FrayHitState2D]`，不是仅保存名称的数组。

Builder 构建、Fighter 赋值／选择姿态和全部测试引用一起迁移；不保留双名字兼容别名。

## 4. Fighter 删除的初始化防御

- 删除 _initialized 以及 physics／publish／advance 中对它的重复检查。
- 删除 resolve_selection 失败后的重复停机／空配置兜底、configure 返回 false 后的重复停机分支。
- 删除重复的初始化前停用／禁用赋值和 set_facing 的正负值兜底；初始化信任既定资源和调用顺序，方向参数由调用方保证为 -1／1。
- 保留 advancer 初始化暂停、MANUAL 模式和激活顺序，这些是调度配置，不是故障回退。
- **保留 _last_transition_frame、动作转向权限、退出清框时的信号屏蔽。**它们分别保证同帧不重复推进、攻击锁向，以及避免原生 Manager 对零掩码又 activate；删除它们会改变运行行为，不属于去“护城河”。
- Loadout 自身的未知 ID 拒绝仍属于资源目录解析；本轮只移除 Fighter 重复兜底，不把未知 ID 变成有效状态。测试不再把非法 selection 送入已经约定信任配置的 Fighter，目录解析的四个拒绝用例继续保留。

## 5. FighterCommandDefinition 三个函数

| 函数 | 职责 | 是否注册输入 |
| --- | --- | --- |
| get_world_steps(facing) | 把作者相对 dir_n 编译成指定面向对应的世界步骤，按钮名保持不变 | 否，只返回步骤数组 |
| create_world_branch(facing) | 复用上述步骤，附加间隔／首步蓄力／negative edge，构造原生 FraySequenceBranch | 否，只构建分支 |
| get_sequence_domain() | 生成过滤／时间要求的兼容域标识，使兼容指令共享 Matcher，不兼容指令分域 | 否，不改变方向、不向 FrayInputMap 添加任何名称 |

真正注册在 FighterInputBindings.register_inputs()；合树和 matcher.initialize 在 FighterInput。左右路径在配置时各编译一次，普通转向不重建 matcher／不反复注册。

## 6. Fray 最小修复

以下两个文件各只改一行：

- `addons/fray/src/hit/2d/hit_state_2d.gd`（仓库根）。
- `module_codes/my fray demo/addons/fray/src/hit/2d/hit_state_2d.gd`（demo 实际加载副本）。

`get_hitboxes() -> Array[FrayHitbox2D]` 内部变量从 `var array: Array` 改成 `var array: Array[FrayHitbox2D]`。公开签名、元素筛选、顺序和生命周期均未变；修复返回实际类型与声明不一致的问题。不批量改其他 Fray 副本或 3D 未使用接口。

BasicAttackState 可以正常使用 `var boxes := _pose.get_hitboxes()`；新增 typed Array 赋值测试，避免靠调用端放宽类型掩盖插件声明问题。

## 7. 实际验证

| 套件 | 检查 | 失败 |
| --- | ---: | ---: |
| 注册／方向／原生 advancer／命令 | 18／16／10／20 | 0 |
| 攻击 Attribute 时序 | 20 | 0 |
| 转换资源／招式转换 | 158／69 | 0 |
| 判定装配／基础移动 | 205／193 | 0 |
| 状态目录／SequenceTree | 21／17 | 0 |
| 真实编辑器保存重载 | 186 | 0 |
| 新进程运行时保存重载 | 186 | 0 |

默认场景 headless 冒烟通过。四条目录拒绝和八条越界拒绝是精确计数的预期日志，其他 ERROR／SCRIPT ERROR 会使测试失败。

新增 test_attack_timing.gd 覆盖 typed Array、阶段边界、Hurt／Push 保留、中断清理、重入、多角色进度隔离及多个攻击框；序列化测试额外保存非默认 12／5／11 的 Attribute，再重载核对 28 帧和有效区间。所有保存仅发生在临时隔离项目，正式转换库条件没有被回归测试覆盖写入。
