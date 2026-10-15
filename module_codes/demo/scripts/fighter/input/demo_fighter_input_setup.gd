class_name DemoFighterInputSetup
extends RefCounted

## 将项目固定的 InputMap 动作接入 Fray，并为每个已安装的复杂指令构建序列分支。
const BASE_INPUT_ACTIONS := [&"left", &"right", &"up", &"down", &"light", &"heavy", &"special", &"block"]

var fighter: DemoFighter


## 保存运行所需依赖并完成初始化。
func setup(p_fighter: DemoFighter) -> void:
	fighter = p_fighter


## 配置输入。
func setup_inputs() -> void:
	_register_global_inputs()
	clear_fighter_inputs()
	for action in BASE_INPUT_ACTIONS:
		var input := fighter.fray_input(action)
		_add_action_bind(input, input)
	_add_facing_axis_input(fighter.fray_input(&"forward"), fighter.fray_input(&"right"), fighter.fray_input(&"left"))
	_add_facing_axis_input(fighter.fray_input(&"back"), fighter.fray_input(&"left"), fighter.fray_input(&"right"))
	_add_down_forward_input()


## 清除角色输入。
func clear_fighter_inputs() -> void:
	var prefix := "%s_" % fighter.input_prefix
	for input_name in FrayInputMap.get_bind_names():
		if String(input_name).begins_with(prefix):
			FrayInputMap.remove_input(input_name)
	var composite_names: Array[StringName] = []
	composite_names.assign(FrayInputMap.get_composite_input_names())
	for input_name in composite_names:
		if String(input_name).begins_with(prefix):
			FrayInputMap.remove_input(input_name)


## 配置输入缓冲。
func setup_buffering(
	controller: FrayController,
	input_advancer: FrayBufferedInputAdvancer,
	loadout: DemoFighterLoadout
) -> void:
	_register_command_composites(loadout)
	input_advancer.listen_to_fray_input(
		controller,
		"%s_" % fighter.input_prefix,
		_build_sequence_tree(loadout)
	)


## 添加下前输入。
func _add_down_forward_input() -> void:
	var down_right := FrayCombinationInput.builder()
	down_right.add_component_simple(fighter.fray_input(&"down"))
	down_right.add_component_simple(fighter.fray_input(&"right"))
	down_right.mode_async()

	var down_left := FrayCombinationInput.builder()
	down_left.add_component_simple(fighter.fray_input(&"down"))
	down_left.add_component_simple(fighter.fray_input(&"left"))
	down_left.mode_async()

	var down_forward := FrayConditionalInput.builder()
	down_forward.add_component(down_right.build())
	down_forward.add_component(down_left.build())
	down_forward.use_condition(Callable(fighter, "is_on_right_side"))
	down_forward.is_virtual()
	down_forward.priority(20)
	_add_composite_once(fighter.fray_input(&"down_forward"), down_forward.build())


## 添加朝向轴向输入。
func _add_facing_axis_input(name: StringName, default_bind: StringName, when_on_right_bind: StringName) -> void:
	var composite := _build_facing_axis_component(default_bind, when_on_right_bind)
	composite.priority = 10
	_add_composite_once(name, composite)


## 构建朝向轴向组件。
func _build_facing_axis_component(
	default_bind: StringName,
	when_on_right_bind: StringName
) -> FrayConditionalInput:
	var builder := FrayConditionalInput.builder()
	builder.add_component_simple(default_bind)
	builder.add_component_simple(when_on_right_bind)
	builder.use_condition(Callable(fighter, "is_on_right_side"))
	return builder.build()


## 添加动作绑定。
func _add_action_bind(name: StringName, action: StringName) -> void:
	if not FrayInputMap.has_input(name):
		FrayInputMap.add_bind_action(name, action)


## 添加组合输入一次。
func _add_composite_once(name: StringName, composite: FrayCompositeInput) -> void:
	if not FrayInputMap.has_input(name):
		FrayInputMap.add_composite_input(name, composite)


## 注册全局输入。
func _register_global_inputs() -> void:
	_add_action_bind(&"restart_demo", &"restart_demo")
	_add_action_bind(&"move_list", &"move_list")


## 为已安装招式注册所需的组合输入。
func _register_command_composites(loadout: DemoFighterLoadout) -> void:
	for entry in loadout.get_installed_entries():
		for step in entry.command.steps:
			_register_command_combination(step)
		# A common quarter-circle finish presses attack while down-forward is
		# still held. Register a higher-priority overlap composite so Fray emits
		# one distinct event instead of masking the direction and attack parts.
		_register_command_combination(_get_held_down_forward_attack_step(entry.command), 20)


## 注册指令组合输入。
func _register_command_combination(step: DemoMoveCommandStep, priority_bonus := 0) -> void:
	if step == null or step.inputs.size() <= 1 or _is_down_forward_step(step):
		return
	var builder := FrayCombinationInput.builder()
	for input_name in step.inputs:
		_add_command_component(builder, StringName(input_name))
	builder.mode_async()
	builder.is_virtual()
	builder.priority(40 + step.inputs.size() + priority_bonus)
	_add_composite_once(
		fighter.fray_input(DemoFighterLoadout.get_combination_input_name(step)),
		builder.build()
	)


## 添加指令组件。
func _add_command_component(builder, input_name: StringName) -> void:
	match input_name:
		&"forward":
			builder.add_component(_build_facing_axis_component(
				fighter.fray_input(&"right"),
				fighter.fray_input(&"left")
			))
		&"back":
			builder.add_component(_build_facing_axis_component(
				fighter.fray_input(&"left"),
				fighter.fray_input(&"right")
			))
		_:
			builder.add_component_simple(fighter.fray_input(input_name))


## 构建序列输入树。
func _build_sequence_tree(loadout: DemoFighterLoadout) -> FraySequenceTree:
	var tree := FraySequenceTree.new()
	_add_dash_sequence(tree, fighter.fray_input(&"dash_forward"), fighter.fray_input(&"forward"))
	_add_dash_sequence(tree, fighter.fray_input(&"dash_back"), fighter.fray_input(&"back"))
	for entry in loadout.get_installed_entries():
		if entry.command.is_simple_press():
			continue
		_add_move_sequence(tree, entry)
	return tree


## 添加招式序列输入。
func _add_move_sequence(tree: FraySequenceTree, entry: DemoMoveLoadoutEntry) -> void:
	var sequence_name := fighter.fray_input(DemoFighterLoadout.get_sequence_input_name(entry.move.id))
	tree.add(sequence_name, _build_command_branch(entry.command.steps))
	var overlap_branch := _build_down_forward_attack_overlap_branch(entry.command)
	if overlap_branch != null:
		tree.add(sequence_name, overlap_branch)
	for held_overlap_branch in _build_held_down_forward_attack_branches(entry.command):
		tree.add(sequence_name, held_overlap_branch)
	var forward_recovery_branch := _build_down_forward_release_branch(entry.command)
	if forward_recovery_branch != null:
		tree.add(sequence_name, forward_recovery_branch)


## 构建指令分支。
func _build_command_branch(steps: Array[DemoMoveCommandStep]) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for step_index in steps.size():
		var step := steps[step_index]
		var step_input := _get_command_step_input(step)
		if step_index == 0:
			branch.first(step_input)
		else:
			branch.then(step_input, step.max_delay_ms)
	return branch.build()


## 同时兼容快速输入末尾方向加攻击时产生的两种下前事件序列。
## 构建下前攻击重叠分支。
func _build_down_forward_attack_overlap_branch(command: DemoMoveCommand) -> FraySequenceBranch:
	if command.steps.size() < 2:
		return null
	var final_step := command.steps.back() as DemoMoveCommandStep
	if not _is_down_forward_attack_step(final_step):
		return null
	var previous_step := command.steps[command.steps.size() - 2] as DemoMoveCommandStep
	var previous_signature := previous_step.get_signature()
	if previous_signature == "down":
		return _build_command_branch_with_inserted_down_forward(command.steps)
	if previous_signature == "down+forward":
		return _build_command_branch_without_penultimate_step(command.steps)
	return null


## 构建指令分支带有插入下前。
func _build_command_branch_with_inserted_down_forward(
	steps: Array[DemoMoveCommandStep]
) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for step_index in steps.size():
		var step := steps[step_index]
		if step_index == 0:
			branch.first(_get_command_step_input(step))
		elif step_index == steps.size() - 1:
			branch.then(fighter.fray_input(&"down_forward"), step.max_delay_ms)
			branch.then(_get_command_step_input(step), step.max_delay_ms)
		else:
			branch.then(_get_command_step_input(step), step.max_delay_ms)
	return branch.build()


## 构建指令分支不含倒数第二步骤。
func _build_command_branch_without_penultimate_step(
	steps: Array[DemoMoveCommandStep]
) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for step_index in steps.size():
		if step_index == steps.size() - 2:
			continue
		var step := steps[step_index]
		if step_index == 0:
			branch.first(_get_command_step_input(step))
		else:
			branch.then(_get_command_step_input(step), step.max_delay_ms)
	return branch.build()


## 兼容尚未松开下方向时按下攻击的四分之一圈输入，并同时提供有无独立下前事件的分支。
## 构建按住下前攻击分支。
func _build_held_down_forward_attack_branches(
	command: DemoMoveCommand
) -> Array[FraySequenceBranch]:
	var result: Array[FraySequenceBranch] = []
	var overlap_step := _get_held_down_forward_attack_step(command)
	if overlap_step == null:
		return result
	result.append(_build_command_branch_with_replaced_final_step(command.steps, overlap_step))
	result.append(_build_command_branch_with_overlap_tail(command.steps, overlap_step))
	return result


## 构建指令分支带有替换后的最后步骤。
func _build_command_branch_with_replaced_final_step(
	steps: Array[DemoMoveCommandStep], final_step: DemoMoveCommandStep
) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for step_index in steps.size():
		var step := final_step if step_index == steps.size() - 1 else steps[step_index]
		if step_index == 0:
			branch.first(_get_command_step_input(step))
		else:
			branch.then(_get_command_step_input(step), steps[step_index].max_delay_ms)
	return branch.build()


## 构建指令分支带有重叠尾部。
func _build_command_branch_with_overlap_tail(
	steps: Array[DemoMoveCommandStep], overlap_step: DemoMoveCommandStep
) -> FraySequenceBranch:
	var branch := FraySequenceBranch.builder()
	for step_index in steps.size():
		if step_index == steps.size() - 2:
			continue
		var step := overlap_step if step_index == steps.size() - 1 else steps[step_index]
		if step_index == 0:
			branch.first(_get_command_step_input(step))
		else:
			branch.then(_get_command_step_input(step), steps[step_index].max_delay_ms)
	return branch.build()


## 返回按住下前攻击步骤。
func _get_held_down_forward_attack_step(command: DemoMoveCommand) -> DemoMoveCommandStep:
	if command.steps.size() < 2:
		return null
	var final_step := command.steps.back() as DemoMoveCommandStep
	var previous_step := command.steps[command.steps.size() - 2] as DemoMoveCommandStep
	if (
		previous_step.get_signature() != "down+forward"
		or final_step.inputs.has("down")
		or not final_step.inputs.has("forward")
		or not _step_has_attack_input(final_step)
	):
		return null
	var overlap_step := DemoMoveCommandStep.new()
	overlap_step.inputs = final_step.inputs.duplicate()
	overlap_step.inputs.append("down")
	overlap_step.max_delay_ms = final_step.max_delay_ms
	return overlap_step


## 兼容松开下方向后 Fray 重新触发前方向，再输入前加攻击的恢复事件序列。
## 构建下前释放分支。
func _build_down_forward_release_branch(command: DemoMoveCommand) -> FraySequenceBranch:
	if command.steps.size() < 2:
		return null
	var final_step := command.steps.back() as DemoMoveCommandStep
	var previous_step := command.steps[command.steps.size() - 2] as DemoMoveCommandStep
	if (
		previous_step.get_signature() != "down+forward"
		or final_step.inputs.has("down")
		or not final_step.inputs.has("forward")
		or not _step_has_attack_input(final_step)
	):
		return null
	var branch := FraySequenceBranch.builder()
	for step_index in command.steps.size():
		var step := command.steps[step_index]
		if step_index == 0:
			branch.first(_get_command_step_input(step))
		elif step_index == command.steps.size() - 1:
			branch.then(fighter.fray_input(&"forward"), step.max_delay_ms)
			branch.then(_get_command_step_input(step), step.max_delay_ms)
		else:
			branch.then(_get_command_step_input(step), step.max_delay_ms)
	return branch.build()


## 判断是否下前攻击步骤。
func _is_down_forward_attack_step(step: DemoMoveCommandStep) -> bool:
	return (
		step.inputs.has("down")
		and step.inputs.has("forward")
		and _step_has_attack_input(step)
	)


## 判断指令步骤是否包含攻击输入。
func _step_has_attack_input(step: DemoMoveCommandStep) -> bool:
	for attack_input in DemoMoveCommand.ATTACK_INPUTS:
		if step.inputs.has(attack_input):
			return true
	return false


## 返回指令步骤输入。
func _get_command_step_input(step: DemoMoveCommandStep) -> StringName:
	if step.inputs.size() == 1:
		return fighter.fray_input(StringName(step.inputs[0]))
	if _is_down_forward_step(step):
		return fighter.fray_input(&"down_forward")
	return fighter.fray_input(DemoFighterLoadout.get_combination_input_name(step))


## 判断是否下前步骤。
func _is_down_forward_step(step: DemoMoveCommandStep) -> bool:
	return (
		step.inputs.size() == 2
		and step.inputs.has("down")
		and step.inputs.has("forward")
	)


## 添加冲刺序列输入。
func _add_dash_sequence(tree: FraySequenceTree, sequence_name: StringName, direction_input: StringName) -> void:
	var branch := FraySequenceBranch.builder()
	branch.first(direction_input)
	branch.then(direction_input, 220)
	tree.add(sequence_name, branch.build())
