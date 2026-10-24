class_name FighterSMBuilder
extends RefCounted
## 一次性装配基础状态与已装备招式；假设资源、路径、类型和条件映射均有效。

const GROUP_PARENTS = {
	&"neutral": &"",
	&"action": &"",
	&"action/basic_attack": &"action",
	&"action/special_attack": &"action",
	&"action/composite_attack": &"action",
	&"action/throw": &"action",
	&"reaction": &"",
}


func build(fighter: Fighter, loadout: FighterLoadout) -> FrayCompoundState:
	var root := FrayCompoundState.new()
	var groups: Dictionary = {&"": root}
	var children: Dictionary = {&"": []}
	for path in GROUP_PARENTS:
		_ensure_group(path, groups, children)

	var definitions: Dictionary = {}
	for item in loadout.state_library.states:
		definitions[_child_path(item.group_path, item.state_name)] = item

	var selected: Array[StringName] = loadout.selected_state_paths.duplicate()
	var rules: Array[FighterTransitionDefinition] = loadout.transition_library.transitions.duplicate()
	for move in loadout.selected_moves:
		for item in move.states:
			var path := _child_path(item.group_path, item.state_name)
			definitions[path] = item
			# 不同招式可以共享阶段和转换；同一依赖只装配一次。
			if not path in selected:
				selected.append(path)
		for rule in move.transitions:
			if not rule in rules:
				rules.append(rule)

	var available: Dictionary[StringName, bool] = {}
	for path in selected:
		var item: FighterStateDefinition = definitions[path]
		_ensure_group(item.group_path, groups, children)
		var group: FrayCompoundState = groups[item.group_path]
		group.add_state(item.state_name, item.state_script.new())
		children[item.group_path].append(item.state_name)
		available[path] = true

	_configure_group_entries(&"", groups, children, loadout.group_start_states, available)
	for rule in rules:
		var from_path := _child_path(rule.group_path, rule.from_state)
		var to_path := _child_path(rule.group_path, rule.to_state)
		# 公共库中的转换可以指向未装备状态，这属于正常装配筛选。
		if available.has(from_path) and available.has(to_path):
			_add_transition(rule, loadout.transition_library, fighter, groups)

	for move in loadout.selected_moves:
		_bind_conditions(root, move.prereqs, loadout.transition_library, fighter)
	return root


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


func _add_transition(rule: FighterTransitionDefinition, library: FighterTransitionLibrary,
		fighter: Fighter, groups: Dictionary) -> void:
	var group: FrayCompoundState = groups[rule.group_path]
	var expressions := rule.advance_conditions.duplicate()
	expressions.append_array(rule.prereqs)
	_bind_conditions(group, expressions, library, fighter)
	var transition := FrayStateMachineTransition.new()
	transition.advance_conditions = rule.advance_conditions.duplicate()
	transition.prereqs = rule.prereqs.duplicate()
	transition.auto_advance = rule.auto_advance
	transition.switch_mode = rule.switch_mode
	transition.priority = rule.priority
	group.add_transition(rule.from_state, rule.to_state, transition)


func _bind_conditions(group: FrayCompoundState, expressions: PackedStringArray,
		library: FighterTransitionLibrary, fighter: Fighter) -> void:
	for expression in expressions:
		var name := StringName(expression.trim_prefix("!"))
		group.set_condition(name, Callable(fighter, library.condition_methods[name]))


func _child_path(group_path: StringName, state_name: StringName) -> StringName:
	return StringName(String(state_name) if group_path.is_empty() else String(group_path) + "/" + String(state_name))


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
