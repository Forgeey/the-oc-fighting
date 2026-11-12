class_name FighterSMBuilder
extends RefCounted
## 按选择创建状态树，并将转换和条件注册到各自容器。

var selected_transitions: Array[FighterTransitionDefinition] = []


#region 状态树构建

## 创建根状态和局部组，并注册各容器的转换。
func build(fighter: Fighter, loadout: FighterLoadout, selection: Dictionary) -> FrayCompoundState:
	selected_transitions.clear()
	var root := FrayCompoundState.new()
	var definitions: Dictionary[StringName, FighterStateDefinition] = {}
	for item: FighterStateDefinition in selection.states:
		definitions[item.state_id] = item
	for item: FighterStateDefinition in selection.root_states:
		_add_leaf(root, item)
	for definition: FighterCompoundStateDefinition in selection.compound_states:
		var group := FrayCompoundState.new()
		for reference in definition.states:
			_add_leaf(group, definitions[reference.state_id])
		group.start_state = definition.start_state
		root.add_state(definition.state_name, group)
	root.start_state = loadout.entry_state
	_register_owner(root, loadout.transition_library.transitions, selection.moves, loadout.transition_library, fighter)
	for definition: FighterCompoundStateDefinition in selection.compound_states:
		var group := root.get_state(definition.state_name) as FrayCompoundState
		_register_owner(group, definition.transitions, selection.moves, loadout.transition_library, fighter)
	return root


## 创建独立的叶子实例，绑定定义并加入指定容器。
func _add_leaf(owner: FrayCompoundState, definition: FighterStateDefinition) -> void:
	var state := definition.state_script.new() as FighterState
	state.state_definition = definition
	owner.add_state(definition.state_name, state)


#endregion


#region 转换筛选与注册

## 筛选当前容器的有效转换，并合入招式入口条件。
func _register_owner(owner: FrayCompoundState, rules: Array[FighterTransitionDefinition],
		moves: Array[FighterMoveDefinition], library: FighterTransitionLibrary, fighter: Fighter) -> void:
	var selected: Array[FighterTransitionDefinition] = []
	for rule in rules:
		if not owner.has_state(rule.from_state) or not owner.has_state(rule.to_state):
			continue
		if not rule.command.is_empty():
			var extra := PackedStringArray()
			var target := owner.get_state(rule.to_state)
			for move: FighterMoveDefinition in moves:
				var is_entry := false
				if move.state is FighterCompoundStateDefinition and target is FrayCompoundState:
					is_entry = (move.state as FighterCompoundStateDefinition).state_name == rule.to_state
				elif move.state is FighterStateDefinition and target is FighterState:
					is_entry = (move.state as FighterStateDefinition).state_id == target.state_definition.state_id
				if is_entry:
					extra.append_array(move.prereqs)
			if not extra.is_empty():
				var prereqs := rule.prereqs.duplicate()
				prereqs.append_array(extra)
				rule = rule.duplicate() as FighterTransitionDefinition
				rule.prereqs = prereqs
		selected.append(rule)
	selected_transitions.append_array(selected)
	register_transitions(owner, selected, library, fighter)


## 按命令、优先级和资源顺序注册原生转换。
func register_transitions(owner: FrayCompoundState, rules: Array[FighterTransitionDefinition],
		library: FighterTransitionLibrary, fighter: Fighter) -> void:
	var ordered := rules.duplicate()
	ordered.sort_custom(func(a: FighterTransitionDefinition, b: FighterTransitionDefinition) -> bool:
		if a.command.is_empty() != b.command.is_empty():
			return not a.command.is_empty()
		if a.priority != b.priority:
			return a.priority < b.priority
		return rules.find(a) < rules.find(b))
	for rule: FighterTransitionDefinition in ordered:
		var expressions := rule.advance_conditions.duplicate()
		expressions.append_array(rule.prereqs)
		_bind_conditions(owner, expressions, library, fighter)
		var transition: FrayStateMachineTransition
		if rule.command.is_empty():
			transition = FrayStateMachineTransition.new()
			transition.auto_advance = rule.auto_advance
		else:
			var input_transition := FrayInputTransitionSequence.new()
			input_transition.sequence = rule.command
			transition = input_transition
			# 原生只有 auto_advance=true 才检查推进条件。输入类型仍必须接受
			# sequence，故开启条件检查不会让它在空输入时自行攻击。
			transition.auto_advance = true
		transition.prereqs = rule.prereqs.duplicate()
		transition.advance_conditions = rule.advance_conditions.duplicate()
		transition.switch_mode = rule.switch_mode
		transition.priority = rule.priority
		owner.add_transition(rule.from_state, rule.to_state, transition)


#endregion


#region 条件绑定

## 将移动意图和角色方法绑定到当前容器的条件。
func _bind_conditions(group: FrayCompoundState, expressions: PackedStringArray,
		library: FighterTransitionLibrary, fighter: Fighter) -> void:
	for expression in expressions:
		var name := StringName(expression.trim_prefix("!"))
		if String(name).begins_with("inputed_"):
			var intent := StringName(String(name).trim_prefix("inputed_"))
			group.set_condition(name, fighter.fighter_input.has_intent.bind(intent))
		else:
			group.set_condition(name, Callable(fighter, library.condition_methods[name]))


#endregion
