# FighterInput 首轮精简与历史清理

> 2026-11-11 实施。本轮减少无调用接口、配置期持久字段和初始化兜底，不改变方向规则、单 Matcher、指令优先级、输入认领或原生 advancer 的失败丢弃行为。不新增节点、包装类或失败重试队列。

## 1. 保留的输入流程

~~~text
FrayInput 采样
→ 按 device、禁用／失焦和设备归属过滤事件
→ FighterInput.sample 按物理批次整理按下／松开来源
→ 规范世界方向事件
→ 单 Matcher 识别特殊序列
→ 多按钮组合
→ 普通单键及歧义等待
→ 来源认领
→ FrayBufferedInputAdvancer.buffer_sequence(command_id)
→ FrayStateMachine 根据当前活动状态的转换裁决
~~~

组合技仍是状态接续，不是整串 Sequence。特殊技 SEQUENCE 使用世界方向历史，完成时按合法朝向解释；转向不清历史。方向＋攻击仍为触发时方向快照，本轮不将其改造成新复合树。

## 2. 删除与简化

- 删除无人连接的 command_buffered 信号与发射。
- 删除成员 _command_by_id；configure 内部用局部 command_ids 去重，运行仅保留 _commands。
- 删除 milliseconds_to_frames 纯转发；需要换算的测试直接调用 Fray.msec_to_frame。
- 删除仅测试使用的 get_world_direction／get_horizontal_axis 观察包装；正式移动继续使用 has_intent／get_movement_axis。
- 删除 _configured、提前未配置 return、推进器 null 后静默丢输入、来源不存在时返回空记录等配置／初始化兜底。
- configure 返回 void，不再维护第二个配置成功标记；设备占用失败仍由真实绑定结果控制采样，事件仍检查实际归属。
- publish_context 信任 Fighter 提供的 -1／1 朝向，不将非法配置悄悄夹成合法值。
- 将 sample 和事件回调共有的运行权限判断收敛到 _can_receive_input；这是设备／焦点业务规则，不是配置预检。
- 移除 Bindings 中未被当前识别链消费的 WORLD_COMPONENTS／game_world_* 斜向复合注册。Matcher 继续读取规范化生成的 world_1～world_9，不改变方向识别规则。
- 共享序列宽包络复用 Command.create_branch 创建独立数据，删除手写逐字段复制；不能修改用于精确校验的原分支。
- 来源弱引用回收和 live ID 收集合并为一次遍历；保留真实消费和释放逻辑。

FrayInputMap.has_input 的注册去重、同设备活动占用检查、按键来源为空／已认领判断仍保留：它们分别实现全局输入幂等注册和真实运行规则，不作为配置兜底删除。

## 3. Matcher 只在配置变化时重新编译

此前 clear_history 每次 new Matcher，再 initialize 整棵树；持续禁用会每帧重复创建，离场也会创建马上丢弃的新对象。

现在 Matcher 随 FighterInput 创建一次；ready 连接一次匹配回调，configure 才 initialize 新配置。clear_history 仅清运行记录和推进器缓冲，不改变 Matcher 身份或编译树。

两份插件同步新增：

~~~gdscript
func clear_history() -> void:
    _reset()
~~~

这是公开已有内部重置，不重新实现匹配算法。FraySequenceMatcher.initialize 结束时也调用 _reset，确保复用同一 Matcher 配置新树时，旧匹配分支／当前帧／已命中节点不残留。

清理会清空当前分支、输入帧队列、当前帧、最后命中标记并回到已编译根；不会 new Matcher、new 匹配树或重复连接信号。禁用期间仍按运行权限清空输入，重复清理是幂等的，不增加“是否已经清过”的状态旗标。

API 前提：先 configure／initialize，再采样、清历史或离场。Fighter 按既有父子 ready 顺序在首个物理采样前配置依赖；不支持把未配置节点当作合法运行对象，不为此增加 null 回退。

## 4. 不删除的游戏逻辑

- 左右抵消、上下顺序／同帧下上、斜方向规范化。
- 世界方向历史和终结时朝向过滤。
- 同一路径多时间／蓄力／松键规则的宽包络＋原生精确复核。
- 按键来源、同源认领、普通单键歧义等待及多按钮帧容错。
- 失焦、设备断开、禁用、设备换绑及离场时清理。
- 识别并入队时消费输入，而不是成功执行后消费；失败命令继续遵循原生 advancer 出队丢弃，不恢复成普通攻击。

## 5. 文件与验证

正式脚本：scripts/input/fighter_input.gd、fighter_input_bindings.gd。
插件：根与 Demo 的 addons/fray/src/input/sequence_matcher.gd 内容同步。
测试：新增 tests/input/test_input_cleanup.gd，并更新现有注册、方向、单 Matcher、移动、资源断言和 run_headless 的 cleanup suite。

专项覆盖：纯插件 prefix reset／再匹配／再次 initialize，字符 Matcher 身份与树不变，半条历史清理，连续禁用／失焦／断连／失去设备绑定，设备切换，再配置命令去重与一次信号连接，离场不分配对象。原有完整输入与状态回归继续运行。

节点、场景、正式资源、FrayBufferedInputAdvancer、状态生命周期插件均不改。

配套：[FighterInput与FrayInput的职责说明](FighterInput与FrayInput的职责说明.md)、[输入系统设计方案](../方案/输入系统设计方案.md)。
