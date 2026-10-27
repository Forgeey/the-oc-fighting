class_name FighterSMBuilder
extends RefCounted
## 从公共资源库装配本角色的状态与转换。

const GROUP_PARENTS = {
	&"neutral": &"",
	&"action": &"",
	&"action/basic_attack": &"action",
	&"action/special_attack": &"action",
	&"action/composite_attack": &"action",
	&"action/throw": &"action",
	&"reaction": &"",
}

## 构建与输入层共用解析后的招式集合。
var selected_moves: Array[FighterMoveDefinition] = []
## 保存本角色全部已选且端点已装配的转换定义。
var selected_transitions: Array[FighterTransitionDefinition] = []


## 收集装备依赖并创建本角色的状态树和转换。
func build(fighter: Fighter, loadout: FighterLoadout) -> FrayCompoundState:
	selected_moves.clear()
	selected_transitions.clear()
	
	# 读取所有状态
	var definitions: Dictionary = {}
	for item in loadout.state_library.states:
		var path := _child_path(item.group_path, item.state_name)
		definitions[path] = item
	# 读取所有招式 
	var moves: Dictionary = {}
	for move in loadout.move_library.moves:
		moves[move.move_id] = move

	# 读取选择的状态
	var selected_state_paths: Array[StringName] = []
	for path in loadout.selected_state_paths:
		selected_state_paths.append(path)
	# 读取选择的招式，并将招式的状态和基本状态合并
	for id in loadout.selected_move_ids:
		var move: FighterMoveDefinition = moves[id]
		selected_moves.append(move)
		for path in move.required_state_paths:
			if not path in selected_state_paths:
				selected_state_paths.append(path)

	# 构建状态树
	var root := FrayCompoundState.new()
	var groups: Dictionary = {&"": root}
	var children: Dictionary = {&"": []}
	for path in GROUP_PARENTS:
		_ensure_group(path, groups, children)
	var available: Dictionary[StringName, bool] = {}
	for path in selected_state_paths:
		var item: FighterStateDefinition = definitions[path]
		_ensure_group(item.group_path, groups, children)
		var group: FrayCompoundState = groups[item.group_path]
		var state := item.state_script.new() as FighterState
		state.state_definition = item
		group.add_state(item.state_name, state)
		children[item.group_path].append(item.state_name)
		available[path] = true
	_configure_group_entries(&"", groups, children, loadout.group_start_states, available)

	# 遵守全局规则库顺序，避免选招顺序改变规则优先级。
	for rule in loadout.transition_library.transitions:
		var from_path := rule.from_state
		var to_path := rule.to_state
		# 叶子或可进入分组均可作为端点，未装配端点正常筛除。
		if available.has(from_path) and available.has(to_path):
			if not rule.move_id.is_empty() and not rule.move_id in loadout.selected_move_ids:
				continue
			selected_transitions.append(rule)
			if rule.move_id.is_empty() and String(from_path).get_base_dir() == String(to_path).get_base_dir():
				_add_transition(rule, loadout.transition_library, fighter, groups)
			else:
				var expressions := rule.advance_conditions.duplicate()
				expressions.append_array(rule.prereqs)
				_bind_conditions(root, expressions, loadout.transition_library, fighter)
	for move in selected_moves:
		_bind_conditions(root, move.prereqs, loadout.transition_library, fighter)
	return root


## 递归创建状态路径需要的父分组。
func _ensure_group(path: StringName, groups: Dictionary, children: Dictionary) -> void:
	if groups.has(path):
		return
	var text := String(path)
	var split := text.rfind("/")
	var parent_path := StringName(text.left(split) if split >= 0 else "")
	var name := StringName(text.substr(split + 1))
	_ensure_group(parent_path, groups, children)
	var group := FrayCompoundState.new()
	groups[parent_path].add_state(name, group)
	groups[path] = group
	children[path] = []
	children[parent_path].append(name)


## 根据完整路径推导共同父组并注册同组普通转换。
func _add_transition(rule: FighterTransitionDefinition, library: FighterTransitionLibrary,
		fighter: Fighter, groups: Dictionary) -> void:
	var group: FrayCompoundState = groups[StringName(String(rule.from_state).get_base_dir())]
	var expressions := rule.advance_conditions.duplicate()
	expressions.append_array(rule.prereqs)
	_bind_conditions(group, expressions, library, fighter)
	var transition := FrayStateMachineTransition.new()
	transition.advance_conditions = rule.advance_conditions.duplicate()
	transition.prereqs = rule.prereqs.duplicate()
	transition.auto_advance = rule.auto_advance
	transition.switch_mode = rule.switch_mode
	transition.priority = rule.priority
	group.add_transition(StringName(String(rule.from_state).get_file()), StringName(String(rule.to_state).get_file()), transition)


## 将资源条件名绑定到角色方法。
func _bind_conditions(group: FrayCompoundState, expressions: PackedStringArray,
		library: FighterTransitionLibrary, fighter: Fighter) -> void:
	for expression in expressions:
		var name := StringName(expression.trim_prefix("!"))
		group.set_condition(name, Callable(fighter, library.condition_methods[name]))


## 拼接分组路径与子状态名称。
func _child_path(group_path: StringName, state_name: StringName) -> StringName:
	return StringName(String(state_name) if group_path.is_empty() else String(group_path) + "/" + String(state_name))


## 为包含已选状态的分组设置默认入口。
func _configure_group_entries(path: StringName, groups: Dictionary, children: Dictionary,
		starts: Dictionary[StringName, StringName], available: Dictionary[StringName, bool]) -> void:
	var valid_children: Array[StringName] = []
	for name in children[path]:
		var child := _child_path(path, name)
		if groups.has(child):
			_configure_group_entries(child, groups, children, starts, available)
		if available.has(child):
			valid_children.append(name)
	# 固定骨架允许未装备任何叶子的空组，不为它们选择默认入口。
	if valid_children.is_empty():
		return
	var group: FrayCompoundState = groups[path]
	var start: StringName = starts.get(path, valid_children[0])
	group.start_state = start
	available[path] = true
