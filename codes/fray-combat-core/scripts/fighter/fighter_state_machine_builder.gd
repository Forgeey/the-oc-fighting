class_name FighterStateMachineBuilder
extends RefCounted
## Fighter foundation 的唯一 Fray 状态拓扑构造器。
##
## 地面、空中、攻防、受击、倒地和 KO 拓扑全部集中于此，状态脚本不自行分发状态。

const SWITCH_IMMEDIATE := FrayStateMachineTransition.SwitchMode.IMMEDIATE

const CANCEL_PRESS_INPUT_SUFFIXES := {
	&"stand_combo_medium": "medium",
	&"stand_heavy": "heavy",
	&"air_medium": "medium",
	&"air_heavy": "heavy",
}
const CANCEL_SEQUENCE_INPUT_SUFFIXES := {
	&"projectile": "back_forward_light",
}

const TAG_GROUNDED: StringName = &"grounded"
const TAG_AIRBORNE: StringName = &"airborne"
const TAG_PUSHBOX_RISING_PASS: StringName = &"pushbox_rising_pass"
const TAG_NEUTRAL: StringName = &"neutral"
const TAG_STANDING_NEUTRAL: StringName = &"standing_neutral"
const TAG_WALK: StringName = &"walk"
const TAG_DASH: StringName = &"dash"
const TAG_DOUBLE_JUMP_SOURCE: StringName = &"double_jump_source"
const TAG_AIR_ATTACK_SOURCE: StringName = &"air_attack_source"
const TAG_GROUND_ATTACK: StringName = &"ground_attack"
const TAG_AIR_ATTACK: StringName = &"air_attack"
const TAG_CONTROLLABLE: StringName = &"controllable"
const TAG_DEFENSE: StringName = &"defense"
const TAG_REACTION: StringName = &"reaction"
const TAG_MOVEMENT_ACTION: StringName = &"movement_action"
const TAG_ATTACK: StringName = &"attack"
const TAG_TERMINAL: StringName = &"terminal"
const TAG_LOCKED: StringName = &"locked"

## 同步保存通过 _tag_states() 注册的分类，供构建阶段按 tag 展开 local transition。
var _state_tags: Dictionary = {}

## 当前 fighter 的 Fray 输入名命名空间，由构建 context 提供。
var _input_prefix: String = "p1_"


## 使用 FrayCompoundState.builder() 构造完整的 fighter Root 状态机。
func build_root(context: Dictionary) -> FrayCompoundState:
	# 不静态标注 FoundationFighter，避免角色脚本与 Builder 在解析阶段形成类型循环。
	var fighter = context.get("fighter")
	var movement := context.get("movement") as FoundationMovement
	var controller := context.get("controller") as FrayController
	if fighter == null or movement == null or controller == null:
		push_error("状态机 context 缺少 fighter、movement 或 controller。")
		return null
	_input_prefix = String(context.get("input_prefix", "p1_"))
	var input_forward := _input_name("forward")
	var input_back := _input_name("back")
	var input_down := _input_name("down")
	var input_guard := _input_name("guard")

	var projectile_cast_runtime := CombatCoreProjectileAttackState.create_cast_runtime()
	var projectile_state := CombatCoreProjectileAttackState.new(&"projectile", projectile_cast_runtime)
	var enhanced_projectile_state := CombatCoreProjectileAttackState.new(
		&"enhanced_projectile",
		projectile_cast_runtime
	)

	# Fray 的条件数组表达 AND；只有需要 OR/等价判断的复合条件才保留为局部 Callable。
	var horizontal_neutral := func() -> bool:
		return controller.is_pressed(input_forward) == controller.is_pressed(input_back)
	var guard_inactive := func() -> bool:
		return not movement.is_grounded() or not controller.is_pressed(input_guard)

	if not _validate_cancel_rules(fighter):
		return null
	var builder := FrayCompoundState.builder()
	var conditions := {
		&"forward": Callable(controller, "is_pressed").bind(input_forward),
		&"back": Callable(controller, "is_pressed").bind(input_back),
		&"down": Callable(controller, "is_pressed").bind(input_down),
		&"guard": Callable(controller, "is_pressed").bind(input_guard),
		&"horizontal_neutral": horizontal_neutral,
		&"guard_inactive": guard_inactive,
		&"is_grounded": Callable(movement, "is_grounded"),
		&"is_falling": Callable(fighter, "is_falling_for_transition"),
		&"can_double_jump": Callable(movement, "can_double_jump"),
		&"can_tech_roll": Callable(fighter, "can_tech_roll"),
		&"should_knockdown": Callable(fighter, "should_knockdown"),
		&"control_locked": Callable(fighter, "is_control_locked"),
		&"can_amplify_projectile": Callable(projectile_state, "can_amplify_to").bind(
			&"enhanced_projectile"
		),
	}
	_register_cancel_conditions(conditions, fighter)
	builder.register_conditions(conditions)

	_state_tags.clear()
	_add_states(builder, fighter, projectile_state, enhanced_projectile_state)
	_register_state_tags(builder)
	_register_ground_transitions(builder)
	_register_air_transitions(builder)
	_register_attack_transitions(builder, fighter)
	_register_reaction_transitions(builder)
	_register_lock_transition(builder)
	_register_global_transition_rules(builder)
	builder.start_at(&"idle")
	return builder.build()


## 添加基础移动、攻防、受击、倒地与终止状态；攻击状态的取消序列由资源目标推导。
func _add_states(
	builder,
	fighter,
	projectile_state: CombatCoreProjectileAttackState,
	enhanced_projectile_state: CombatCoreProjectileAttackState
) -> void:
	builder.add_state(&"idle", FoundationIdleState.new())
	builder.add_state(&"walk_forward", FoundationWalkState.new())
	builder.add_state(&"walk_back", FoundationWalkState.new())
	builder.add_state(&"crouch", FoundationCrouchState.new())
	builder.add_state(&"stand_guard", FoundationGuardState.new(false))
	builder.add_state(&"crouch_guard", FoundationGuardState.new(true))
	builder.add_state(&"dash_forward", FoundationDashState.new(1))
	builder.add_state(&"dash_back", FoundationDashState.new(-1))
	builder.add_state(&"jump_start", FoundationJumpStartState.new())
	builder.add_state(&"jump", FoundationJumpState.new())
	builder.add_state(&"double_jump", FoundationDoubleJumpState.new())
	builder.add_state(&"fall", FoundationFallState.new())
	builder.add_state(&"land", FoundationLandState.new())
	builder.add_state(&"stand_light", _create_attack_state(fighter, &"stand_light", false))
	builder.add_state(&"stand_medium", _create_attack_state(fighter, &"stand_medium", false))
	builder.add_state(&"stand_heavy", _create_attack_state(fighter, &"stand_heavy", false))
	builder.add_state(&"stand_combo_medium", _create_attack_state(fighter, &"stand_combo_medium", false))
	builder.add_state(&"crouch_light", _create_attack_state(fighter, &"crouch_light", false))
	builder.add_state(&"crouch_medium", _create_attack_state(fighter, &"crouch_medium", false))
	builder.add_state(&"crouch_heavy", _create_attack_state(fighter, &"crouch_heavy", false))
	builder.add_state(&"air_light", _create_attack_state(fighter, &"air_light", true))
	builder.add_state(&"air_medium", _create_attack_state(fighter, &"air_medium", true))
	builder.add_state(&"air_heavy", _create_attack_state(fighter, &"air_heavy", true))
	builder.add_state(&"projectile", projectile_state)
	builder.add_state(&"enhanced_projectile", enhanced_projectile_state)
	builder.add_state(&"hitstun", FoundationHitstunState.new(false))
	builder.add_state(&"air_hitstun", FoundationHitstunState.new(true))
	builder.add_state(&"blockstun", FoundationBlockstunState.new())
	builder.add_state(&"knockdown", FoundationKnockdownState.new())
	builder.add_state(&"tech_roll", FoundationTechRollState.new())
	builder.add_state(&"wakeup", FoundationWakeupState.new())
	builder.add_state(&"ko", FoundationKOState.new())
	builder.add_state(&"locked", FoundationLockedState.new())


## 创建近战攻击状态，并从攻击资源的序列取消目标推导接触失败时需要清理的 Fray sequence。
func _create_attack_state(fighter, state_id: StringName, airborne: bool) -> FoundationAttackState:
	var attribute := fighter.get_attack_attribute(state_id) as FrayAttackAttribute
	var discard_sequences := PackedStringArray()
	if attribute != null and attribute.cancel_requires_contact():
		for target_value in attribute.cancel_target_states:
			var target_state := StringName(target_value)
			if CANCEL_SEQUENCE_INPUT_SUFFIXES.has(target_state):
				discard_sequences.append(_input_name(String(CANCEL_SEQUENCE_INPUT_SUFFIXES[target_state])))
	return FoundationAttackState.new(state_id, airborne, discard_sequences)


## 校验每条资源取消目标都能映射到现有 Fray press/sequence 转移及实际目标攻击资源。
func _validate_cancel_rules(fighter) -> bool:
	for source_state in fighter.get_attack_state_ids():
		var attribute := fighter.get_attack_attribute(source_state) as FrayAttackAttribute
		if attribute == null:
			continue
		for target_value in attribute.cancel_target_states:
			var target_state := StringName(target_value)
			if CANCEL_PRESS_INPUT_SUFFIXES.has(target_state):
				if fighter.get_attack_attribute(target_state) == null:
					push_error("取消目标 %s 没有对应的 Fray 攻击 hit state。" % target_state)
					return false
				continue
			if CANCEL_SEQUENCE_INPUT_SUFFIXES.has(target_state):
				if fighter.get_projectile_attack_attribute(target_state) == null:
					push_error("取消目标 %s 没有对应的投射物攻击资源。" % target_state)
					return false
				continue
			push_error("攻击状态 %s 的取消目标 %s 没有 Fray 输入映射。" % [source_state, target_state])
			return false
	return true


## 为所有受资源控制的取消目标注册绑定 fighter 查询的 Fray condition。
func _register_cancel_conditions(conditions: Dictionary, fighter) -> void:
	var target_states := CANCEL_PRESS_INPUT_SUFFIXES.keys()
	target_states.append_array(CANCEL_SEQUENCE_INPUT_SUFFIXES.keys())
	for target_value in target_states:
		var target_state := StringName(target_value)
		conditions[_cancel_condition_name(target_state)] = Callable(
			fighter,
			"can_cancel_current_attack_to"
		).bind(target_state)


## 为攻击资源声明的目标生成 Fray local transition；序列取消优先于普通按键取消。
func _register_data_driven_cancel_transitions(builder, fighter) -> void:
	for source_state in fighter.get_attack_state_ids():
		var attribute := fighter.get_attack_attribute(source_state) as FrayAttackAttribute
		if attribute == null:
			continue
		for target_value in attribute.cancel_target_states:
			var sequence_target_state := StringName(target_value)
			if not CANCEL_SEQUENCE_INPUT_SUFFIXES.has(sequence_target_state):
				continue
			builder.transition_sequence(
				source_state,
				sequence_target_state,
				_sequence_config(
					_input_name(String(CANCEL_SEQUENCE_INPUT_SUFFIXES[sequence_target_state])),
					PackedStringArray([String(_cancel_condition_name(sequence_target_state))])
				)
			)
		for target_value in attribute.cancel_target_states:
			var press_target_state := StringName(target_value)
			if not CANCEL_PRESS_INPUT_SUFFIXES.has(press_target_state):
				continue
			builder.transition_press(
				source_state,
				press_target_state,
				_press_config(
					_input_name(String(CANCEL_PRESS_INPUT_SUFFIXES[press_target_state])),
					PackedStringArray([String(_cancel_condition_name(press_target_state))])
				)
			)


## 返回目标状态对应的稳定 Fray condition 名称。
func _cancel_condition_name(target_state: StringName) -> StringName:
	return StringName("cancel_to_%s" % target_state)


## 注册全部地面相关转移，并按输入、离地、姿态和动作收尾分组。
func _register_ground_transitions(builder) -> void:
	_register_ground_input_transitions(builder)
	_register_ground_fall_transitions(builder)
	_register_idle_transitions(builder)
	_register_walk_transitions(builder)
	_register_crouch_and_guard_transitions(builder)
	_register_dash_exit_transitions(builder)


## 注册地面状态中的起跳和前后冲刺输入转移。
func _register_ground_input_transitions(builder) -> void:
	_register_press_transitions_from_tag(
		builder,
		TAG_NEUTRAL,
		&"jump_start",
		_press_config(_input_name("up"))
	)
	_register_sequence_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"dash_forward",
		_sequence_config(_input_name("dash_forward"))
	)
	_register_sequence_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"dash_back",
		_sequence_config(_input_name("dash_back"))
	)


## 注册地面中立状态意外离地后的统一下落转移。
func _register_ground_fall_transitions(builder) -> void:
	_register_transitions_from_tag(
		builder,
		TAG_NEUTRAL,
		&"fall",
		_auto_condition(&"!is_grounded")
	)


## 注册 idle 到防御、下蹲和行走状态的转移。
func _register_idle_transitions(builder) -> void:
	builder.transition(
		&"idle",
		&"stand_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "!down"]))
	)
	builder.transition(
		&"idle",
		&"crouch_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "down"]))
	)
	builder.transition(
		&"idle",
		&"crouch",
		_auto_conditions(PackedStringArray(["is_grounded", "down", "!guard"]))
	)
	builder.transition(
		&"idle",
		&"walk_forward",
		_auto_conditions(PackedStringArray(["is_grounded", "forward", "!back", "!down", "!guard"]))
	)
	builder.transition(
		&"idle",
		&"walk_back",
		_auto_conditions(PackedStringArray(["is_grounded", "back", "!forward", "!down", "!guard"]))
	)


## 注册行走状态之间，以及行走到防御、下蹲和 idle 的转移。
func _register_walk_transitions(builder) -> void:
	_register_transitions_from_tag(
		builder,
		TAG_WALK,
		&"stand_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "!down"]))
	)
	_register_transitions_from_tag(
		builder,
		TAG_WALK,
		&"crouch_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "down"]))
	)
	_register_transitions_from_tag(
		builder,
		TAG_WALK,
		&"crouch",
		_auto_conditions(PackedStringArray(["is_grounded", "down", "!guard"]))
	)

	builder.transition(
		&"walk_forward",
		&"walk_back",
		_auto_conditions(PackedStringArray(["is_grounded", "back", "!forward", "!down", "!guard"]))
	)
	builder.transition(
		&"walk_forward",
		&"idle",
		_auto_conditions(PackedStringArray(["is_grounded", "horizontal_neutral", "!down", "!guard"]))
	)
	builder.transition(
		&"walk_back",
		&"walk_forward",
		_auto_conditions(PackedStringArray(["is_grounded", "forward", "!back", "!down", "!guard"]))
	)
	builder.transition(
		&"walk_back",
		&"idle",
		_auto_conditions(PackedStringArray(["is_grounded", "horizontal_neutral", "!down", "!guard"]))
	)


## 注册下蹲、站防和蹲防之间的姿态转移。
func _register_crouch_and_guard_transitions(builder) -> void:
	builder.transition(
		&"crouch",
		&"crouch_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "down"]))
	)
	builder.transition(&"crouch", &"idle", _auto_condition(&"!down"))

	builder.transition(
		&"stand_guard",
		&"crouch_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "down"]))
	)
	builder.transition(&"stand_guard", &"idle", _auto_condition(&"guard_inactive"))

	builder.transition(
		&"crouch_guard",
		&"stand_guard",
		_auto_conditions(PackedStringArray(["is_grounded", "guard", "!down"]))
	)
	builder.transition(&"crouch_guard", &"idle", _auto_condition(&"guard_inactive"))


## 注册冲刺离地和冲刺自然结束后的转移。
func _register_dash_exit_transitions(builder) -> void:
	_register_transitions_from_tag(
		builder,
		TAG_DASH,
		&"fall",
		_auto_condition(&"!is_grounded")
	)
	_register_transitions_from_tag(
		builder,
		TAG_DASH,
		&"idle",
		_at_end(PackedStringArray(["is_grounded"]))
	)


## 注册起跳、上升、二段跳、下落和落地恢复流程。
func _register_air_transitions(builder) -> void:
	_register_jump_start_transitions(builder)
	_register_air_movement_transitions(builder)
	_register_landing_transitions(builder)
	_register_double_jump_input_transitions(builder)


## 注册起跳准备状态的离地与动画结束转移。
func _register_jump_start_transitions(builder) -> void:
	builder.transition(&"jump_start", &"fall", _auto_condition(&"!is_grounded"))
	builder.transition(&"jump_start", &"jump", _at_end())


## 注册跳跃和二段跳进入下落的转移。
func _register_air_movement_transitions(builder) -> void:
	builder.transition(&"jump", &"fall", _auto_condition(&"is_falling"))
	builder.transition(&"double_jump", &"fall", _auto_condition(&"is_falling"))


## 注册下落着地，以及落地状态的离地保护和自然结束转移。
func _register_landing_transitions(builder) -> void:
	builder.transition(&"fall", &"land", _auto_condition(&"is_grounded"))
	builder.transition(&"land", &"fall", _auto_condition(&"!is_grounded"))
	builder.transition(&"land", &"idle", _at_end())


## 注册跳跃和下落状态中的二段跳输入转移。
func _register_double_jump_input_transitions(builder) -> void:
	var double_jump_config := _press_config(
		_input_name("up"),
		PackedStringArray(["can_double_jump"])
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_DOUBLE_JUMP_SOURCE,
		&"double_jump",
		double_jump_config
	)


## 注册全部地面和空中攻击的输入与收尾转移。
func _register_attack_transitions(builder, fighter) -> void:
	_register_ground_attack_input_transitions(builder, fighter)
	_register_air_attack_input_transitions(builder)
	_register_ground_attack_exit_transitions(builder)
	_register_air_attack_exit_transitions(builder)


## 注册站立、下蹲攻击、普通波指令、状态内 Amplify，以及资源声明的数据化取消关系。
func _register_ground_attack_input_transitions(builder, fighter) -> void:
	# 普通波 sequence 先成立；随后在 attribute 窗口内由防御键 press 转入强化状态。
	_register_sequence_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"projectile",
		_sequence_config(_input_name("back_forward_light"))
	)
	# 若玩家在末尾攻击键附近先压到防御，guard 状态仍可消费已完成的普通波 sequence。
	builder.transition_sequence(
		&"stand_guard",
		&"projectile",
		_sequence_config(_input_name("back_forward_light"))
	)
	builder.transition_sequence(
		&"crouch_guard",
		&"projectile",
		_sequence_config(_input_name("back_forward_light"))
	)
	builder.transition_press(
		&"projectile",
		&"enhanced_projectile",
		_press_config(_input_name("guard"), PackedStringArray(["can_amplify_projectile"]))
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"stand_light",
		_press_config(_input_name("light"))
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"stand_medium",
		_press_config(_input_name("medium"))
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"stand_heavy",
		_press_config(_input_name("heavy"))
	)
	builder.transition_press(&"crouch", &"crouch_light", _press_config(_input_name("light")))
	builder.transition_press(&"crouch", &"crouch_medium", _press_config(_input_name("medium")))
	builder.transition_press(&"crouch", &"crouch_heavy", _press_config(_input_name("heavy")))
	_register_data_driven_cancel_transitions(builder, fighter)


## 注册跳跃、二段跳和下落状态中的轻中重攻击输入。
func _register_air_attack_input_transitions(builder) -> void:
	_register_press_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK_SOURCE,
		&"air_light",
		_press_config(_input_name("light"))
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK_SOURCE,
		&"air_medium",
		_press_config(_input_name("medium"))
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK_SOURCE,
		&"air_heavy",
		_press_config(_input_name("heavy"))
	)


## 注册地面攻击离地和自然结束后的转移。
func _register_ground_attack_exit_transitions(builder) -> void:
	_register_transitions_from_tag(
		builder,
		TAG_GROUND_ATTACK,
		&"fall",
		_auto_condition(&"!is_grounded")
	)
	_register_transitions_from_tag(
		builder,
		TAG_GROUND_ATTACK,
		&"idle",
		_at_end(PackedStringArray(["is_grounded"]))
	)


## 注册空中攻击着地和自然结束后的转移。
func _register_air_attack_exit_transitions(builder) -> void:
	_register_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK,
		&"land",
		_auto_condition(&"is_grounded")
	)
	_register_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK,
		&"fall",
		_at_end(PackedStringArray(["!is_grounded"]))
	)


## 注册硬直、倒地、受身、起身和 KO 周边流程。
func _register_reaction_transitions(builder) -> void:
	_register_hitstun_transitions(builder)
	_register_blockstun_transitions(builder)
	_register_recovery_transitions(builder)


## 注册地面与空中受击硬直结束后的去向。
func _register_hitstun_transitions(builder) -> void:
	builder.transition(&"hitstun", &"knockdown", _at_end(PackedStringArray(["should_knockdown"])))
	builder.transition(&"hitstun", &"idle", _at_end(PackedStringArray(["is_grounded", "!should_knockdown"])))
	builder.transition(&"hitstun", &"fall", _at_end(PackedStringArray(["!is_grounded"])))

	builder.transition(&"air_hitstun", &"knockdown", _auto_condition(&"is_grounded"))
	builder.transition(&"air_hitstun", &"fall", _at_end(PackedStringArray(["!is_grounded"])))


## 注册防御硬直结束后继续防御或回到 idle 的转移。
func _register_blockstun_transitions(builder) -> void:
	builder.transition(
		&"blockstun",
		&"crouch_guard",
		_at_end(PackedStringArray(["is_grounded", "guard", "down"]))
	)
	builder.transition(
		&"blockstun",
		&"stand_guard",
		_at_end(PackedStringArray(["is_grounded", "guard", "!down"]))
	)
	builder.transition(&"blockstun", &"idle", _at_end(PackedStringArray(["guard_inactive"])))


## 注册倒地受身输入，以及倒地、受身和起身状态的自然结束转移。
func _register_recovery_transitions(builder) -> void:
	var tech_roll_config := _press_config(
		_input_name("guard"),
		PackedStringArray(["can_tech_roll"])
	)
	builder.transition_press(&"knockdown", &"tech_roll", tech_roll_config)
	builder.transition(&"knockdown", &"wakeup", _at_end())
	builder.transition(&"tech_roll", &"idle", _at_end())
	builder.transition(&"wakeup", &"idle", _at_end())


## 注册由集中生命周期条件驱动的 Fray global transition。
func _register_lock_transition(builder) -> void:
	builder.transition_global(&"locked", {
		"auto_advance": true,
		"advance_conditions": PackedStringArray(["control_locked"]),
		"switch_mode": SWITCH_IMMEDIATE,
	})


## 集中注册状态分类 tag，并同步项目层查询表供 local transition 展开使用。
func _register_state_tags(builder) -> void:
	_tag_states(
		builder,
		PackedStringArray(["idle", "walk_forward", "walk_back"]),
		PackedStringArray([
			TAG_GROUNDED,
			TAG_NEUTRAL,
			TAG_STANDING_NEUTRAL,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["walk_forward", "walk_back"]),
		PackedStringArray([TAG_WALK])
	)
	_tag_states(
		builder,
		PackedStringArray(["crouch"]),
		PackedStringArray([TAG_GROUNDED, TAG_NEUTRAL, TAG_CONTROLLABLE])
	)
	_tag_states(
		builder,
		PackedStringArray(["stand_guard", "crouch_guard"]),
		PackedStringArray([TAG_GROUNDED, TAG_DEFENSE, TAG_CONTROLLABLE])
	)
	_tag_states(
		builder,
		PackedStringArray(["blockstun"]),
		PackedStringArray([TAG_GROUNDED, TAG_DEFENSE, TAG_REACTION])
	)
	_tag_states(
		builder,
		PackedStringArray(["dash_forward", "dash_back"]),
		PackedStringArray([
			TAG_GROUNDED,
			TAG_DASH,
			TAG_MOVEMENT_ACTION,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["jump_start", "land"]),
		PackedStringArray([TAG_GROUNDED, TAG_MOVEMENT_ACTION, TAG_CONTROLLABLE])
	)
	_tag_states(
		builder,
		PackedStringArray(["jump", "fall"]),
		PackedStringArray([
			TAG_AIRBORNE,
			TAG_DOUBLE_JUMP_SOURCE,
			TAG_AIR_ATTACK_SOURCE,
			TAG_MOVEMENT_ACTION,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["double_jump"]),
		PackedStringArray([
			TAG_AIRBORNE,
			TAG_AIR_ATTACK_SOURCE,
			TAG_MOVEMENT_ACTION,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["stand_light", "stand_medium", "stand_heavy", "stand_combo_medium", "crouch_light", "crouch_medium", "crouch_heavy", "projectile", "enhanced_projectile"]),
		PackedStringArray([
			TAG_GROUNDED,
			TAG_GROUND_ATTACK,
			TAG_ATTACK,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["air_light", "air_medium", "air_heavy"]),
		PackedStringArray([
			TAG_AIRBORNE,
			TAG_AIR_ATTACK,
			TAG_ATTACK,
			TAG_CONTROLLABLE,
		])
	)
	# 穿越资格属于主动状态；速度方向由 fighter 在运行时判定，因此下落空中攻击会恢复推挤。
	_tag_states(
		builder,
		PackedStringArray(["jump", "double_jump", "air_light", "air_medium", "air_heavy"]),
		PackedStringArray([TAG_PUSHBOX_RISING_PASS])
	)
	_tag_states(
		builder,
		PackedStringArray(["hitstun", "air_hitstun", "knockdown", "tech_roll", "wakeup"]),
		PackedStringArray([TAG_REACTION])
	)
	_tag_states(builder, PackedStringArray(["ko"]), PackedStringArray([TAG_TERMINAL]))
	_tag_states(builder, PackedStringArray(["locked"]), PackedStringArray([TAG_LOCKED]))


## 注册只用于 Fray global transition 的跨状态规则。
func _register_global_transition_rules(builder) -> void:
	builder.add_rule(TAG_CONTROLLABLE, TAG_LOCKED)
	builder.add_rule(TAG_REACTION, TAG_LOCKED)


## 为带有指定 tag 的来源状态展开相同的普通 Fray local transition。
func _register_transitions_from_tag(
	builder,
	source_tag: StringName,
	target_state: StringName,
	config: Dictionary
) -> void:
	for source_state in _get_states_with_tag(source_tag):
		builder.transition(source_state, target_state, config)


## 为带有指定 tag 的来源状态展开相同的 Fray press local transition。
func _register_press_transitions_from_tag(
	builder,
	source_tag: StringName,
	target_state: StringName,
	config: Dictionary
) -> void:
	for source_state in _get_states_with_tag(source_tag):
		builder.transition_press(source_state, target_state, config)


## 为带有指定 tag 的来源状态展开相同的 Fray sequence local transition。
func _register_sequence_transitions_from_tag(
	builder,
	source_tag: StringName,
	target_state: StringName,
	config: Dictionary
) -> void:
	for source_state in _get_states_with_tag(source_tag):
		builder.transition_sequence(source_state, target_state, config)


## 同时向 Fray builder 和项目层 tag 查询表注册一组状态分类。
func _tag_states(
	builder,
	states: PackedStringArray,
	tags: PackedStringArray
) -> void:
	builder.tag_multi(states, tags)
	for state_name_value in states:
		var state_name := StringName(state_name_value)
		var registered_tags := PackedStringArray()
		if _state_tags.has(state_name):
			registered_tags = _state_tags[state_name]
		for tag_name in tags:
			if not registered_tags.has(tag_name):
				registered_tags.append(tag_name)
		_state_tags[state_name] = registered_tags


## 返回所有带有指定 tag 的状态，用于在构建阶段展开普通 local transition。
func _get_states_with_tag(tag_name: StringName) -> Array[StringName]:
	var matched_states: Array[StringName] = []
	for state_name_value in _state_tags:
		var state_name := StringName(state_name_value)
		var registered_tags: PackedStringArray = _state_tags[state_name]
		if registered_tags.has(tag_name):
			matched_states.append(state_name)
	if matched_states.is_empty():
		push_error("没有找到带有 tag '%s' 的状态。" % tag_name)
	return matched_states


## 使用当前 fighter 的输入前缀构造 Fray bind、composite 或 sequence 名。
func _input_name(suffix: String) -> StringName:
	return StringName(_input_prefix + suffix)


## 创建普通按键输入转移配置，并统一附加控制未锁定条件。
func _press_config(
	input_name: StringName,
	prereqs: PackedStringArray = PackedStringArray()
) -> Dictionary:
	return {
		"input": input_name,
		"switch_mode": SWITCH_IMMEDIATE,
		"prereqs": _with_control_unlocked(prereqs),
	}


## 创建序列输入转移配置，并统一附加控制未锁定条件。
func _sequence_config(
	sequence_name: StringName,
	prereqs: PackedStringArray = PackedStringArray()
) -> Dictionary:
	return {
		"sequence": sequence_name,
		"switch_mode": SWITCH_IMMEDIATE,
		"prereqs": _with_control_unlocked(prereqs),
	}


## 创建单个 Fray condition 驱动的自动转移配置。
func _auto_condition(condition: StringName) -> Dictionary:
	return _auto_conditions(PackedStringArray([condition]))


## 创建由全部 Fray conditions 共同驱动的自动转移配置。
func _auto_conditions(conditions: PackedStringArray) -> Dictionary:
	return {
		"auto_advance": true,
		"advance_conditions": conditions,
		"prereqs": _with_control_unlocked(),
		"switch_mode": SWITCH_IMMEDIATE,
	}


## 创建状态完成后触发的 AT_END transition，可追加 Fray condition 前置条件。
func _at_end(prereqs: PackedStringArray = PackedStringArray()) -> Dictionary:
	return {
		"auto_advance": true,
		"prereqs": _with_control_unlocked(prereqs),
	}


## 复制前置条件并统一附加控制未锁定条件，避免各类转移重复维护该约束。
func _with_control_unlocked(
	prereqs: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var combined: PackedStringArray = prereqs.duplicate()
	combined.append("!control_locked")
	return combined
