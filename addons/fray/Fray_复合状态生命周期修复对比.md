# Fray 复合状态生命周期修复：修改前后对比

日期：2026-10-22

## 1. 本次范围与结论

本次只修改仓库根目录的 `addons/fray`，**没有修改 `module_codes/my fray demo`，没有删除 Demo 的 `FighterCompoundState`、bootstrap 或其中的插件副本**。

生产代码仅修改两个脚本：

1. `src/state_mgmt/state/compound_state.gd`
2. `src/state_mgmt/state_machine.gd`

新增独立测试：

- `tests/state_mgmt/test_lifecycle.gd`
- `tests/state_mgmt/run_headless.py`
- `tests/.gdignore`（让普通 Godot 项目不导入独立测试脚本）

“修改前”代码来自本次修改开始时的 Git HEAD；两个生产脚本修改前没有本地未提交变化。下面逐函数列出完整代码，不用省略号代替函数体；新增函数标记为“修改前不存在”。

## 2. 采用的语义

本补丁参考 SCXML 的**单活动分支层次进入/退出、默认初始子状态、后代规则优先和 external 自转移**，不是完整 SCXML 实现。

| 场景 | 修改后行为 |
| --- | --- |
| 两参数 initialize(context, root) | 使用根默认入口，正确进入最终叶子一次 |
| initialize(context, root, initial_path) | 直接进入指定目标；目标是组时才补默认分支 |
| goto("action") | 补全 action 默认路径，只进入真正需要的新状态 |
| goto("action/special/heavy") | 不进入无关的 startup 默认叶子 |
| goto(当前叶子) | 导航不重入；不启动一遍当前招式 |
| 普通规则 A→A | external 自转移：A 及其活动后代退出，再重新进入 |
| 同一父组内两个叶子切换 | 父组保持活动，只退出旧叶子、进入新叶子 |
| 子阶段规则与祖先公共规则同时可用 | 普通规则中后代优先；无匹配再回退祖先 |
| 最终需要进入空组/无效默认入口 | 报错，不退出现有活动状态 |
| 嵌套组直接 goto/advance | 根状态机收到最终完整叶子路径的变化通知 |

默认入口 `start_state` **保留**，其公开 setter 不改为接受空字符串；添加第一个子状态自动设为默认入口的行为也保留。空组可保留在状态骨架中，但不能成为成功进入的最终目标。

`is_persistent` 保留为 Fray 扩展：未指定该组后代时恢复已记录子状态；显式后代覆盖历史选择。它不是 SCXML 的显式 `<history>` 节点。

`goto()` 是 Fray 导航接口，不冒充 external transition；普通规则目前统一采用 external 语义，不新增 internal 模式。

### 2.1 支持延迟择派生的结构

```text
special_move (start_state = startup)
├─ startup
├─ choice_window
├─ light_followup
├─ heavy_followup
└─ recovery
```

先进入 startup；起手完成后进入 choice_window，再按输入进入 light/heavy，超时可以进入 recovery。父组从起手到派生保持活动，不重复执行进入副作用。等待窗口是明确子状态，不需要让父组在没有活动子状态时等待。

## 3. 新增内部状态及注释

脚本：`src/state_mgmt/state/compound_state.gd`

修改前没有同步切换锁；修改后新增：

```gdscript
# Lifecycle callbacks must not recursively execute another transition.
var _is_transitioning := false
```

该标志实际以根对象上的值为准。在 ready/enter/exit 期间不允许同步递归启动另一轮切换；请把后续转换放到下一次推进或延迟调用，不要在进入钩子里直接调用 goto/travel。此补丁不实现 SCXML 的事件队列。

同时明确 `is_persistent` 的注释，避免与规范 history 混淆。`goto()` 与 `initialize()` 的 API 注释也同步说明新语义。

## 4. 生产脚本逐函数完整对比
### 脚本：`src/state_mgmt/state/compound_state.gd`

本脚本修改/新增函数：`_enter_impl()`、`advance()`、`travel()`、`goto()`、`add_transition()`、`remove_transition()`、`get_next_state()`、`ready()`、`_get_transition_priority()`、`_goto()`、`_resolve_entry_states()`、`_enter_states()`、`_get_next_transition()`、`_transition_to()`。
#### `_enter_impl()`

**对比说明：** 删除复合状态进入钩子中的默认分支递归。该钩子只表示状态自身进入；框架统一设置活动子状态并调用各层钩子，避免漏掉叶子或重复进入中间组。

**修改前：**

```gdscript
func _enter_impl(args: Dictionary) -> void:
	super(args)

	if not is_persistent or _current_state.is_empty():
		_current_state = start_state

	var cur_state := get_current_state()
	if cur_state is FrayCompoundState:
		cur_state._enter_impl(args)
```

**修改后：**

```gdscript
func _enter_impl(args: Dictionary) -> void:
	super(args)
```

#### `advance()`

**对比说明：** 普通规则先检查活动后代，未命中再回退本层；保留选中的规则及实际源状态，执行 external 转换，使叶子和复合状态自转移均能退出再进入。travel 仍保留为 Fray 扩展，并跳过 AStar 路径包含的起点。返回值现在正确反映实际 travel 推进。

**修改前：**

```gdscript
func advance(input: Dictionary = {}, args: Dictionary = {}) -> bool:
	var cur_state: FrayState = get_current_state()
	var has_substate_advanced := false

	if cur_state != null:
		if _astar.has_next_travel_point():
			#TODO: Traveling may need to be reapproach due to the _goto changes
			# further testing is required.
			var travel_state = cur_state
			while travel_state.is_done_processing() and _astar.has_next_travel_point():
				_goto(_astar.get_next_travel_point(), _travel_args)
				travel_state = get_state(_current_state)
		else:
			var next_state := get_next_state(input)

			if not next_state.is_empty():
				goto(next_state, args)
				return true

		if cur_state is FrayCompoundState:
			return cur_state.advance(input, args)

	return false
```

**修改后：**

```gdscript
func advance(input: Dictionary = {}, args: Dictionary = {}) -> bool:
	if get_root()._is_transitioning:
		return false

	var cur_state := get_current_state()
	if cur_state == null:
		return false

	# Explicit travel remains a Fray extension and takes priority at this level.
	if _astar.has_next_travel_point():
		var advanced := false
		while _astar.has_next_travel_point() and cur_state.is_done_processing():
			var next_point := _astar.get_next_travel_point()
			# AStar includes the origin; it is not an external self-transition.
			if next_point == _current_state:
				continue
			if not _transition_to(next_point, _travel_args, cur_state):
				_astar.clear_travel_path()
				return advanced
			advanced = true
			cur_state = get_current_state()
		if advanced:
			return true
		return cur_state.advance(input, args) if cur_state is FrayCompoundState else false

	# A descendant's matching rule wins over an ancestor's matching rule.
	if cur_state is FrayCompoundState and cur_state.advance(input, args):
		return true

	var next_transition := _get_next_transition(input)
	if next_transition == null:
		return false

	return _transition_to(next_transition.to, args, cur_state)
```

#### `travel()`

**对比说明：** 在进入/退出/初始化回调期间拒绝同步 travel，避免中途改写路径。其余仍使用原有 AStar 寻路接口。

**修改前：**

```gdscript
func travel(to: StringName, args: Dictionary = {}) -> void:
	if _ERR_INVALID_STATE(to):
		return

	if not _current_state.is_empty():
		_astar.compute_travel_path(_current_state, to)
		_travel_args = args

		if not _astar.has_next_travel_point():
			goto(to, args)
```

**修改后：**

```gdscript
func travel(to: StringName, args: Dictionary = {}) -> void:
	if get_root()._is_transitioning:
		push_error("Failed to travel during a lifecycle callback.")
		return
	if _ERR_INVALID_STATE(to):
		return

	if not _current_state.is_empty():
		_astar.compute_travel_path(_current_state, to)
		_travel_args = args

		if not _astar.has_next_travel_point():
			goto(to, args)
```

#### `goto()`

**对比说明：** 不再在入口验证前清除 travel；成功验证后统一交给执行器处理。保留公开签名与路径存在性检查。goto 是导航，不等同于 SCXML external 规则。

**修改前：**

```gdscript
func goto(path: StringName, args: Dictionary = {}) -> void:
	if not has_state(path):
		return

	if _astar.has_next_travel_point():
		_astar.clear_travel_path()

	_goto(path, args)
```

**修改后：**

```gdscript
func goto(path: StringName, args: Dictionary = {}) -> void:
	if not has_state(path):
		return

	_goto(path, args)
```

#### `add_transition()`

**对比说明：** AStar 不允许节点连接自身，而 external 自转移是合法生命周期规则。自转移仅注册到规则列表，不添加无意义的 AStar 自边。

**修改前：**

```gdscript
func add_transition(
	from: StringName, to: StringName, transition: FrayStateMachineTransition
) -> void:
	if _ERR_INVALID_STATE(from):
		return
	if _ERR_INVALID_STATE(to):
		return

	var tr := _Transition.new()
	tr.from = from
	tr.to = to
	tr.transition = transition

	_astar.connect_points(from, to, has_transition(from, to))
	_transitions.append(tr)
```

**修改后：**

```gdscript
func add_transition(
	from: StringName, to: StringName, transition: FrayStateMachineTransition
) -> void:
	if _ERR_INVALID_STATE(from):
		return
	if _ERR_INVALID_STATE(to):
		return

	var tr := _Transition.new()
	tr.from = from
	tr.to = to
	tr.transition = transition

	# AStar rejects self-edges; self-transitions are lifecycle rules, not travel edges.
	if from != to:
		_astar.connect_points(from, to, has_transition(from, to))
	_transitions.append(tr)
```

#### `remove_transition()`

**对比说明：** 与添加时的处理对称，删除自转移规则时跳过 AStar 自边操作。普通边维持原逻辑。

**修改前：**

```gdscript
func remove_transition(from: StringName, to: StringName) -> void:
	if _ERR_INVALID_STATE(from):
		return
	if _ERR_INVALID_STATE(to):
		return

	_astar.disconnect_points(from, to, not has_transition(from, to))

	for transition in _transitions:
		if transition.from == from and transition.to == to:
			_transitions.erase(transition)
			return
```

**修改后：**

```gdscript
func remove_transition(from: StringName, to: StringName) -> void:
	if _ERR_INVALID_STATE(from):
		return
	if _ERR_INVALID_STATE(to):
		return

	if from != to:
		_astar.disconnect_points(from, to, not has_transition(from, to))

	for transition in _transitions:
		if transition.from == from and transition.to == to:
			_transitions.erase(transition)
			return
```

#### `get_next_state()`

**对比说明：** 维持原有返回目标名称的公开接口；把规则选择委托给 _get_next_transition()，避免 advance() 丢失选中的规则信息。

**修改前：**

```gdscript
func get_next_state(input: Dictionary = {}) -> StringName:
	if _current_state.is_empty():
		push_warning("No current state is set.")
		return ""

	for tr in get_next_transitions(_current_state):
		var transition: FrayStateMachineTransition = tr.transition
		if _can_transition(transition) and _can_advance(transition, input):
			return tr.to
	return ""
```

**修改后：**

```gdscript
func get_next_state(input: Dictionary = {}) -> StringName:
	var next_transition := _get_next_transition(input)
	return next_transition.to if next_transition != null else &""
```

#### `ready()`

**对比说明：** 初始化时自顶向下重新绑定每个子状态的根弱引用。否则先构建子树、再挂到父组的常见方式会留下旧根引用，新切换执行器可能误把局部组当成根、重复进入祖先或不通知真正的状态机。保留原有“子状态先 ready，父状态后 ready”的顺序。

**修改前：**

```gdscript
func ready(context: Dictionary) -> void:
	if not context.is_read_only():
		context.make_read_only()

	for state_name in _states:
		var state: FrayState = _states[state_name]

		if state is FrayCompoundState:
			state.ready(context)
		else:
			state._ready_impl(context)

	_ready_impl(context)
```

**修改后：**

```gdscript
func ready(context: Dictionary) -> void:
	if not context.is_read_only():
		context.make_read_only()

	for state_name in _states:
		var state: FrayState = _states[state_name]
		# A subtree may have been built before it was attached to this root.
		state._root_ref = weakref(get_root())

		if state is FrayCompoundState:
			state.ready(context)
		else:
			state._ready_impl(context)

	_ready_impl(context)
```

#### `_get_transition_priority()`

**对比说明：** get_transition() 返回的已经是 FrayStateMachineTransition，不是内部 _Transition 包装。因此应读取 tr.priority，而非 tr.transition.priority。此旧错误在 travel 回归中被实际触发。

**修改前：**

```gdscript
func _get_transition_priority(from: StringName, to: StringName) -> float:
	var tr := get_transition(from, to)
	return float(tr.transition.priority) if tr else 0.0
```

**修改后：**

```gdscript
func _get_transition_priority(from: StringName, to: StringName) -> float:
	var tr := get_transition(from, to)
	return float(tr.priority) if tr else 0.0
```

#### `_goto()`

**对比说明：** 原先按相对路径深度计算共同祖先并同时触发递归进入，容易冲突。现在只委托统一执行器；相对调用和根调用都使用完整对象路径计算进退范围。

**修改前：**

```gdscript
func _goto(path: StringName, args: Dictionary = {}) -> void:
	var target_state := get_state(path)

	if target_state == null:
		push_error("Failed to go to target state. State not found.")
		return

	# Find most common active ancestor of target and current active state.
	var active_path_info := get_active_states_info()
	var active_states: Array[FrayState] = active_path_info.states
	var common_active_ancestor: FrayState = target_state

	while common_active_ancestor != null and not common_active_ancestor in active_states:
		common_active_ancestor = common_active_ancestor.get_parent()

	# Exit all active states leading up to common ancestor excluding common ancestor
	for i in range(active_states.size() - 1, -1, -1):
		var state: FrayState = active_states[i]
		if state == common_active_ancestor:
			break

		state.exit()

	# Enter all states leading to target state excluding common ancestor
	var ancestor_path_index := active_states.find(common_active_ancestor)
	var new_active_state: FrayState = common_active_ancestor
	var state_paths := path.split("/")

	for i in range(ancestor_path_index, state_paths.size()):
		var next_state_name := state_paths[i]
		new_active_state._current_state = next_state_name
		new_active_state = new_active_state.get_state(next_state_name)
		new_active_state._enter_impl(args)

	transitioned.emit(active_path_info.path, path)
```

**修改后：**

```gdscript
func _goto(path: StringName, args: Dictionary = {}) -> void:
	_transition_to(path, args)
```

#### `_resolve_entry_states()`

**对比说明：** 新增：在任何进入/退出副作用之前解析完整 root→叶子对象路径。显式路径优先；只有最终目标仍是复合状态时才展开默认/持久入口。空组或无效入口返回失败，不破坏旧活动路径。

**修改前：**

不存在此函数。

**修改后：**

```gdscript
func _resolve_entry_states(path: StringName = &"") -> Array[FrayState]:
	var states: Array[FrayState] = []
	var target: FrayState = self if path.is_empty() else get_state_or_null(path)
	if target == null:
		push_error("Failed to enter state. Target path '%s' does not exist." % path)
		return states

	var ancestor: FrayState = target
	while ancestor != null:
		states.push_front(ancestor)
		ancestor = ancestor.get_parent()

	while target is FrayCompoundState:
		var group := target as FrayCompoundState
		var child_name := group._current_state if (
			group.is_persistent and not group._current_state.is_empty()
		) else group.start_state
		var child: FrayState = group._states.get(child_name)
		if child == null or child in states:
			push_error("Failed to enter compound state. Invalid default/history child '%s'." % child_name)
			return []
		states.append(child)
		target = child

	return states
```

#### `_enter_states()`

**对比说明：** 新增：只进入目标路径中新激活的后缀，从外向内设置父级的当前子状态并调用进入钩子。复合状态进入时清除活动子指针，直到子状态被逐层真正进入。

**修改前：**

不存在此函数。

**修改后：**

```gdscript
func _enter_states(states: Array[FrayState], first_index: int, args: Dictionary) -> void:
	for i in range(first_index, states.size()):
		var state := states[i]
		if state is FrayCompoundState:
			# No descendant is active until its own entry is performed.
			state._current_state = &""
		if i > 0:
			var parent := states[i - 1] as FrayCompoundState
			parent._current_state = StringName(parent._states.find_key(state))
		state._enter_impl(args)
```

#### `_get_next_transition()`

**对比说明：** 新增：复用原有前置条件、完成条件和输入匹配逻辑，但返回选中的内部规则对象，而不是只返回目标名称。不额外改变本层规则排序。

**修改前：**

不存在此函数。

**修改后：**

```gdscript
func _get_next_transition(input: Dictionary = {}) -> _Transition:
	if _current_state.is_empty():
		return null
	for transition in get_next_transitions(_current_state):
		if _can_transition(transition.transition) and _can_advance(transition.transition, input):
			return transition
	return null
```

#### `_transition_to()`

**对比说明：** 新增：统一处理导航和 external 规则。先验证目标，再求对象路径公共前缀；external 规则排除源/目标本身，确保正确重入。由内向外退出、由外向内进入；完成后用完整最终叶子路径通知根，修复嵌套组切换未通知状态机的问题。

**修改前：**

不存在此函数。

**修改后：**

```gdscript
func _transition_to(path: StringName, args: Dictionary, source: FrayState = null) -> bool:
	var root := get_root()
	if root._is_transitioning:
		push_error("Failed to transition. Lifecycle callbacks cannot execute nested transitions.")
		return false

	var target := get_state_or_null(path)
	if target == null:
		push_error("Failed to transition. Target path '%s' does not exist." % path)
		return false
	var next_states := _resolve_entry_states(path)
	if next_states.is_empty():
		return false

	var active_info := root.get_active_states_info()
	var active_states: Array[FrayState] = active_info.states
	var common_count := 0
	while common_count < mini(active_states.size(), next_states.size()):
		if active_states[common_count] != next_states[common_count]:
			break
		common_count += 1

	if source != null:
		var source_index := active_states.find(source)
		if source_index < 0:
			push_error("Failed to transition. Source state is not active.")
			return false
		# External transitions retain only a proper common ancestor of source
		# and explicit target, even when default expansion selects the old leaf.
		common_count = mini(common_count, mini(source_index, next_states.find(target)))

	if _astar.has_next_travel_point() and source == null:
		_astar.clear_travel_path()
	root._is_transitioning = true
	for i in range(active_states.size() - 1, common_count - 1, -1):
		active_states[i].exit()
	root._enter_states(next_states, common_count, args)
	root._is_transitioning = false

	var next_path: StringName = root.get_active_states_info().path
	root.transitioned.emit(active_info.path, next_path)
	if self != root:
		transitioned.emit(active_info.path, next_path)
	return true
```

### 脚本：`src/state_mgmt/state_machine.gd`

本脚本修改/新增函数：`initialize()`。
#### `initialize()`

**对比说明：** 增加可选 initial_path，原有两参数调用继续使用根默认入口；初始化和普通切换共用相同的路径解析/进入流程。先验证入口，再 ready 和进入，因此真实目标可以直接初始化，不需要 bootstrap 或初始化后的第二次 goto。

**修改前：**

```gdscript
func initialize(context: Dictionary, root: FrayCompoundState) -> void:
	if root.has_parent():
		push_error("Failed to initialize statemachine. Provided root has parent state.")
		return

	_root = root
	_root._fn_get_node = get_node
	_root._fn_get_node_of_type = get_node_of_type
	_root._fn_get_nodes_of_type = get_nodes_of_type
	_root.ready(context)
	_root._enter_impl({})
	_root.transitioned.connect(_on_RootState_transitioned)
```

**修改后：**

```gdscript
func initialize(context: Dictionary, root: FrayCompoundState, initial_path: StringName = &"") -> void:
	if root.has_parent():
		push_error("Failed to initialize statemachine. Provided root has parent state.")
		return
	if root._is_transitioning or (_root != null and _root._is_transitioning):
		push_error("Failed to initialize statemachine during a lifecycle callback.")
		return

	# Validate the complete entry before ready/enter or replacing the old root.
	var entry_states := root._resolve_entry_states(initial_path)
	if entry_states.is_empty():
		return

	if _root != null and _root.transitioned.is_connected(_on_RootState_transitioned):
		_root.transitioned.disconnect(_on_RootState_transitioned)
	_root = root
	_root._fn_get_node = get_node
	_root._fn_get_node_of_type = get_node_of_type
	_root._fn_get_nodes_of_type = get_nodes_of_type
	_root._is_transitioning = true
	_root.ready(context)
	_root._enter_states(entry_states, 0, {})
	_root._is_transitioning = false
	_root.transitioned.connect(_on_RootState_transitioned)
```

## 5. 与原实现的重要兼容性差异

1. **叶子进入回调现在会可靠执行。** 过去因为漏调用而没有触发的动画/判定/计时初始化，现在会执行；请排查业务层为补偿旧行为而增加的重复初始化。
2. **不要继续叠加旧入口兼容类。** 新执行器已经接管默认路径；旧 `FighterCompoundState` 仍重置子状态并改写路径，可能覆盖持久状态或约定。迁移项目时替换为原生 `FrayCompoundState`，而不是只复制插件后继续使用旧兼容类。
3. **同组叶子切换不重入父组。** 父组进入适合一次性资源消耗、开启整个招式标志；父组退出适合清理。分支窗口和阶段计时放在具体子状态。
4. **普通规则的后代优先是一项行为变更。** 若受击/死亡必须覆盖所有派生规则，需要通过条件或输入调度保证优先，不再依赖旧的祖先先检查顺序。本补丁不新增全局抢占模式。
5. **普通自转移会重入。** `goto(当前叶子)` 仍不重入。调用方必须区分规则转移与导航。
6. **变化信号现在使用根的完整实际叶子路径。** 例如目标传入 `action`，信号 `to` 可能是 `action/special/startup`，不再只是 `action`；直接在子组切换也会通知根 `state_changed`。初始化保持原约定：完成初始化后连接根信号，不额外发出初始变化事件。
7. **空组无法进入。** 显式骨架空组可以存在，但其默认分支不能出现在最终进入路径里。解析会先失败，保持旧状态不变。
8. **travel 仍是非 SCXML 扩展。** 保留本层显式 travel 优先、等待完成条件、忽略规则前置条件的行为；修复起点重复进入、优先级读取和推进返回值。不改变 AStar 路径的整体设计。
9. **不修改公开规则端点限制。** `add_transition()` 仍使用所属组的直接子状态名；不是任意完整路径边。如果需要跨层叶子间任意连边，需要另外设计。
10. **初始化重新绑定根引用。** 支持先构建子树再挂到父组；局部切换不会把原来的子树根误当成最终根。
11. **不修改 physics_process()、process() 和输入分发。** 状态仍是 Resource，活动路径由状态机统一更新；修复入口后才允许把相应叶子当作已经进入的活动状态。
12. **initialize 不是 reset/dispose API。** 本次没有新增正在运行的旧根的完整退出/销毁协议；重新装备运行中状态机时，应另外管理旧根生命周期，不把多次 initialize 当作自动清理保证。

## 6. 后续迁移 Demo（本次未执行）

在确认项目使用这份修复后的插件后：

1. 同步修改后的两个插件脚本到 Demo 的 `addons/fray` 副本。
2. 构建器将 `FighterCompoundState.new()` 改为 `FrayCompoundState.new()`。
3. 删除添加 bootstrap 和将根入口设为 bootstrap 的代码，保留默认入口配置。
4. 直接传入真实入口：

```gdscript
state_machine.initialize({
    "fighter": self,
    "controller": controller,
    "movement": _movement,
    "hit_state_manager": hit_state_manager,
}, root, loadout.entry_path)
```

5. 删除紧随初始化之后的 `state_machine.goto(loadout.entry_path)`。
6. 最后删除 `fighter_compound_state.gd` 及对应 `.uid`，更新 Demo 文档。

原有两参数 initialize 调用仍有效，不要求所有项目立即改成三参数；但要直接初始化到非默认叶子，需要使用第三个参数。

## 7. 测试与复现

### 7.1 运行方式

需要 Python 3 和可用的 Godot 4 可执行文件；Windows 推荐使用 `_console.exe`。

```powershell
python addons/fray/tests/state_mgmt/run_headless.py --godot "D:/Program Files/Godot/Godot_v4.7-stable_win64_console.exe"
```

请把示例路径改为自己安装的 Godot 路径。

Python 启动器把必要的真实插件源码复制到临时目录中的独立 Godot 项目，先注册脚本类，再执行 GDScript 测试，不修改 Demo、不向仓库创建 `.godot` 缓存。它检查引擎退出码、脚本错误、断言汇总和非预期 ERROR，避免只看退出码而漏掉 GDScript 运行错误。

### 7.2 本次实际结果

引擎：`Godot 4.7.stable.official.5b4e0cb0f`，headless 模式。

```text
RESULT: 53 checks; 0 failures
```

覆盖：

- 默认初始化、显式叶子初始化、复合目标初始化。
- 先构建子树再挂到父组时，根引用、局部切换和根信号仍然正确。
- 初始化后物理更新沿正确活动路径分发。
- 默认进入、显式深路径、参数传递、不误入默认分支。
- 同组切换、当前叶子导航、已活动父组的默认导航。
- 叶子及复合状态 external 自转移，以及自转移删除。
- 后代优先、祖先回退。
- 起手未完成时等待、选择窗口无按键时等待、重攻击输入选择重派生。
- 持久状态恢复、显式目标覆盖恢复。
- 空组入口和无效初始路径的无副作用失败。
- travel 起点跳过、等待和恢复推进。
- AT_END 完成条件、普通转换参数传递。
- 子组切换向根发出完整路径通知。
- 生命周期回调内同步递归转换被拒绝，外层切换保持完整。

测试会刻意触发三个带 `EXPECTED ERROR` 标识的错误分支（空组、无效初始路径、嵌套转换）；它们不是测试失败。当前系统上引擎另有 `Failed to read the root certificate store` 环境提示；本测试无网络依赖，该提示不影响本轮断言结果。

目前仅在上述 Godot 版本执行，未宣称覆盖全部 Godot 4 版本，也未测试整个战斗 Demo 的动画、输入缓冲与判定集成。

## 8. 未实现范围及参考

本轮不实现 SCXML XML 解析、parallel、显式 history 节点、internal 模式、完整事件队列、事件无关转换的完整 run-to-completion 调度、转换内容动作或完整冲突集算法。一次普通 advance 仍只选择当前单分支中的一条规则；不要把本补丁称为完整 SCXML 合规引擎。

规范参考：W3C SCXML 1.0，重点对应 state/initial、transition 的 external 语义、状态进入/退出与转换选择算法。

```text
https://www.w3.org/TR/scxml/
```
