# 单角色单 Matcher 接入记录

> 2026-11-11 后续精简：Matcher 随角色输入创建一次，configure 才 initialize 新树；清历史调用公开 clear_history 保持对象／树和回调。两份插件同步公开内部重置，initialize 也完整清历史。此前“清理时重建／插件不改”属于旧阶段记录；当前边界见[FighterInput 首轮精简](FighterInput首轮精简与历史清理.md)。

> **2026-11-10 运行状态已扁平化：**分类不再生成运行分组；当前使用 selected_state_names／entry_state 和 idle、light_attack 等直接名称，删除 group_start_states。根直接使用 FrayCompoundState，命令／普通边由 Fray 原生执行。以下旧层级、旧路径及跨层桥接描述仅作历史；最新接口与迁移范围见[扁平状态机迁移说明](扁平状态机迁移说明.md)。

> 2026-11-09 实现。取代旧文中“每兼容域一个 matcher”“三个指令编译函数仍保留”的描述。只调整游戏输入接线；不修改 Fray 插件，不新增节点或配置兜底。

## 1. 前后条件输入只注册一次，不按角色身份或转向重注册

现有 FighterInputBindings.register_inputs() 已满足统一注册：基础 bind、game_forward／game_backward 条件输入、世界对角组合、装备按键组合，在 Fighter 构建时配置。定义已存在时复用原对象。

条件回调经 device 找角色已发布朝向。P1／P2／CPU 是控制身份，不能代替当前朝向；初始站位不同不要求两份招式资源。后续翻面只更新合法朝向，不重新调用注册入口、不覆盖 composite、不重编译序列。

本轮没有为这项行为另加一套输入注册。新增测试反复发布 1／-1 朝向，核对 FrayInputMap 名称列表及 forward composite 对象不变、matcher 实例不变。

## 2. Matcher 在哪里配置、在哪里保存

```text
Fighter._init_fighter()
  → loadout.resolve_selection()
  → Fighter._initialize_state_machine(..., selection)
  → fighter_input.configure(controller, selection.moves, advancer)
       → 统一注册输入
       → 相对 command 编译左右世界 branch，合成一棵树
       → 创建并初始化唯一 FraySequenceMatcher
       → matcher 保存到现有 FighterInput.matcher

运行时：
Fray 事件 → 同一套世界方向／按钮归一化 → matcher.read(event)
  → match_found → 完成朝向和命令要求复核 → 原生 advancer
```

所以：**配置动作属于角色构建阶段，代码位于 FighterInput.configure；运行实例也保存在 FighterInput。**不是每帧配置、不是每招一个，更不是新增 Matcher Node。即使当前只装备单键或没有序列，也保留一个空树 matcher，角色间实例彼此独立。

普通转向不重建。失焦、换设备、重配等明确清历史事件仍通过创建新的唯一实例来清理，释放旧引用；不是同时维护两个 matcher。

## 3. 三个函数缩成一个

FighterCommandDefinition 删除 get_world_steps、create_world_branch、get_sequence_domain，仅保留：

```gdscript
func create_branch(facing: int) -> FraySequenceBranch:
```

一次循环完成相对 dir_n 到世界方向转换，并写入相邻时间、首步蓄力和 negative edge 要求。作者仍写一套相对指令。FighterInput 在角色配置时各调用一次 facing=1／-1；去重路径直接从返回 branch.input_requirements 取得，不重复再算一次世界 steps。

两条世界路径存在于同一 tree，不表示向 FrayInputMap 注册两份招式，也不表示运行时换面向要重新注册。

## 4. 删除 matcher 分域，统一输入语义

- 移除 _groups、domain、每域 aliases／vertical／first_vertical 和按域创建 matcher 的循环。
- 所有序列接收同一套事件：方向先归一、再读按钮。没有某一招单独重排事件或忽略任意按钮的配置。
- 左右仍抵消。斜方向在同批水平分量确定后只生成一个世界方向变化，避免一次斜方向成为“下、前、斜下前”三步。
- 上下重叠：最后实际按下的垂直方向用于统一序列流。因此下未松开再按上仍产生 world_2 → world_8；松开当前一侧后恢复仍 held 的另一侧，但不伪造新物理来源 ID。
- 真正同一采样帧的上下固定下→上；不能再为“上→下”命令单独逆序喂同一批事件。不同帧则保留实际顺序。所有指令共享同一容错，不通过拆 matcher 让相反指令各自当成先发生。
- jump／crouch 默认方向别名不送 matcher；只要某个装备序列显式使用该行为按钮，就在该角色的共享事件流中启用。其他指令也会看到该按钮，按原生打断规则处理，不维持每招不同过滤域。
- 方向变化 release 使用原方向的按下时间与来源，蓄力时长和同源去重继续有效，不修改共享 Fray 事件。

## 5. 不同时间要求也使用一个 Matcher

- 不同世界路径可以在同一棵树配置不同 max_delay／蓄力要求，无需拆实例。
- 同一“输入名＋press/charge 结构”的路径只在原生树登记一个 route 终点，避免原生终点重名冲突。
- 同路径有不同时间／negative edge 要求时，共享 branch 只作宽范围识别；同步回调使用原生 FraySequenceMatcher.is_match 对各命令的精确 branch 复核，再检查终结时朝向。
- 这不是配置合法性验证或失败兜底，是保持“一实例＋不误接受严格指令”的实际识别步骤；没有新增通用解析器或重写 Fray。
- 完全同输入同时满足多条命令仍按现有作者顺序／来源认领处理，不因此获得任意最长前缀优先。要共用输入触发多条状态边，应共用同一 command_id，由转换条件决策。

## 6. 本轮改动文件

运行脚本：

1. scripts/input/fighter_command_definition.gd：三个函数合并为 create_branch(facing)。
2. scripts/input/fighter_input.gd：唯一 matcher 和树／路由表，统一方向流、合树与原生精确复核。
3. scripts/fighter/fighter.gd：配置入口职责注释，原有构建时 configure 顺序保留，运行逻辑未额外增加。

测试：

- 新增 tests/input/test_single_matcher.gd。
- 修改 test_direction_history.gd、test_input_registration.gd、test_command_dispatch.gd：更新单实例断言、转向不注册／不重建、角色实例隔离。
- 修改 tests/movement/run_headless.py：新增 matcher suite。

节点／场景／资源：本轮均未新增、删除或改挂；FighterInput、原生 FrayStateMachine／advancer 继续使用原有节点。插件源码无本轮改动。未添加新 Autoload、管理器、配置回退或默认参数兜底。

## 7. 验证

干净临时工程完整通过：输入注册 21 项、方向历史 16 项、单 Matcher 19 项、原生缓冲 10 项、命令转换 20 项、攻击时序 22 项、转换资源 158 项、招式转换 69 项、判定装配 205 项、基础移动 193 项、状态目录 21 项、SequenceTree 17 项。真实编辑器保存／运行时新进程重载各 186 项通过，默认场景冒烟通过。

重点新增混合场景：同一角色同时装备普通圆弧、下上、蓄力和不同时间指令；同路不同时间／蓄力阈值不误接受；press-only 与负边共用终点仍区分；上下相反指令采用同一顺序；跨转向续接仍按完成朝向；反复转向不重新注册条件输入。

测试只保存隔离副本，不覆盖正式转换条件。预期目录拒绝 4 条、SequenceTree 越界 8 条逐条计数，其余 ERROR／SCRIPT ERROR 判失败。
