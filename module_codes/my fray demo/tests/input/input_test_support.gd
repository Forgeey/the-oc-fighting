extends RefCounted
## 隔离测试共用的离线角色；不改变正式运行调度。

static func pause(actor: Fighter) -> void:
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.advancer.set_physics_process(false)
	actor.advancer.set_process(false)


static func spawn(parent: Node, moves: Array[FighterMoveDefinition] = []) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = actor.loadout.duplicate()
	if not moves.is_empty():
		actor.loadout.move_library = FighterMoveLibrary.new()
		actor.loadout.move_library.moves.assign(moves)
		actor.loadout.selected_move_ids.clear()
		actor.loadout.transition_library = actor.loadout.transition_library.duplicate(true)
		var rules: Array[FighterTransitionDefinition] = []
		for rule in actor.loadout.transition_library.transitions:
			if rule.command.is_empty():
				rules.append(rule)
			else:
				for move in moves:
					var launch := rule.duplicate() as FighterTransitionDefinition
					launch.command = move.command.command_id
					rules.append(launch)
		actor.loadout.transition_library.transitions = rules
		for move in moves:
			actor.loadout.selected_move_ids.append(move.move_id)
	parent.add_child(actor)
	pause(actor)
	actor.state_machine.get_root().set_condition(&"grounded", func() -> bool: return true)
	return actor


static func move(id: StringName, steps: Array[StringName] = []) -> FighterMoveDefinition:
	var result := (load("res://resource/moves/01010001_move.tres") as FighterMoveDefinition).duplicate() as FighterMoveDefinition
	result.move_id = id
	result.command = FighterCommandDefinition.new()
	result.command.command_id = StringName("test_input_" + String(id))
	if not steps.is_empty():
		result.command.input_kind = FighterCommandDefinition.InputKind.SEQUENCE
		result.command.steps.assign(steps)
	result.command.resolve_delay_frames = 0
	return result


static func inputs(actor: Fighter, actions: Array) -> void:
	for action in FighterInputBindings.ACTIONS:
		Input.action_release(action)
	for action in actions:
		Input.action_press(action)
	FrayInput._physics_process(1.0 / Engine.physics_ticks_per_second)
	actor.fighter_input.sample()


static func ordinary(actor: Fighter) -> bool:
	# 每次调用代表一个离线模拟 tick；正式代码绝不清此防重复标记。
	actor._last_transition_frame = -1
	return actor.advance_commands()


static func drive(actor: Fighter) -> void:
	# 测试原生 physics 回调，而非替换／重写 advancer._advance。
	actor._last_transition_frame = -1
	actor.advancer._physics_process(1.0 / Engine.physics_ticks_per_second)


static func turn(actor: Fighter, facing: int) -> void:
	actor.set_facing(facing)
	actor.publish_input_context()

## 测试只检查输入边，避免普通回退遮蔽“能否发动”的断言；调用原生条件与转换方法。
static func try_move(actor: Fighter, move: FighterMoveDefinition) -> bool:
	return try_input(actor.state_machine.get_root(), move.command.command_id)


static func try_input(root: FrayCompoundState, command: StringName) -> bool:
	var input := {"sequence": command}
	for edge in root.get_next_transitions(root.get_current_state_name()):
		var transition: FrayStateMachineTransition = edge.transition
		if transition is FrayInputTransitionSequence and transition.accepts(input) and root._can_transition(transition) and root._can_advance(transition, input):
			return root._transition_to(edge.to, {}, root.get_current_state())
	return false


## 仅隔离测试替换边集合，再调用正式 Builder 进行原生注册；无产品重试或适配逻辑。
static func set_rules(actor: Fighter, rules: Array[FighterTransitionDefinition]) -> void:
	var root := actor.state_machine.get_root()
	var conditions: Dictionary = root._condition_func_by_name.duplicate()
	root._transitions.clear()
	FighterSMBuilder.new().register_transitions(root, rules, actor.loadout.transition_library, actor)
	for name in conditions:
		root.set_condition(name, conditions[name])
	actor._selected_transitions = rules
