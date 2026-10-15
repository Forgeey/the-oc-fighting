class_name FighterStateMachineBuilder
extends RefCounted
## Fighter foundation 的唯一 Fray 状态拓扑构造器。
##
## 地面、空中、攻防、受击、倒地和 KO 拓扑全部集中于此，状态脚本不自行分发状态。

const SWITCH_IMMEDIATE := FrayStateMachineTransition.SwitchMode.IMMEDIATE
const INPUT_FORWARD: StringName = &"p1_forward"
const INPUT_BACK: StringName = &"p1_back"
const INPUT_DOWN: StringName = &"p1_down"
const INPUT_UP: StringName = &"p1_up"
const INPUT_LIGHT: StringName = &"p1_light"
const INPUT_HEAVY: StringName = &"p1_heavy"
const INPUT_GUARD: StringName = &"p1_guard"
const SEQUENCE_DASH_FORWARD: StringName = &"p1_dash_forward"
const SEQUENCE_DASH_BACK: StringName = &"p1_dash_back"

const TAG_GROUNDED: StringName = &"grounded"
const TAG_AIRBORNE: StringName = &"airborne"
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


## 使用 FrayCompoundState.builder() 构造完整的 fighter Root 状态机。
func build_root(context: Dictionary) -> FrayCompoundState:
	# 不静态标注 FoundationFighter，避免角色脚本与 Builder 在解析阶段形成类型循环。
	var fighter = context.get("fighter")
	var movement := context.get("movement") as FoundationMovement
	var controller := context.get("controller") as FrayController
	if fighter == null or movement == null or controller == null:
		push_error("状态机 context 缺少 fighter、movement 或 controller。")
		return null

	# Fray 的条件数组表达 AND；只有需要 OR/等价判断的复合条件才保留为局部 Callable。
	var horizontal_neutral := func() -> bool:
		return controller.is_pressed(INPUT_FORWARD) == controller.is_pressed(INPUT_BACK)
	var guard_inactive := func() -> bool:
		return not movement.is_grounded() or not controller.is_pressed(INPUT_GUARD)

	var builder := FrayCompoundState.builder()
	builder.register_conditions({
		&"forward": Callable(controller, "is_pressed").bind(INPUT_FORWARD),
		&"back": Callable(controller, "is_pressed").bind(INPUT_BACK),
		&"down": Callable(controller, "is_pressed").bind(INPUT_DOWN),
		&"guard": Callable(controller, "is_pressed").bind(INPUT_GUARD),
		&"horizontal_neutral": horizontal_neutral,
		&"guard_inactive": guard_inactive,
		&"is_grounded": Callable(movement, "is_grounded"),
		&"is_falling": Callable(fighter, "is_falling_for_transition"),
		&"can_double_jump": Callable(movement, "can_double_jump"),
		&"can_tech_roll": Callable(fighter, "can_tech_roll"),
		&"should_knockdown": Callable(fighter, "should_knockdown"),
		&"control_locked": Callable(fighter, "is_control_locked"),
	})

	_state_tags.clear()
	_add_states(builder)
	_register_state_tags(builder)
	_register_ground_transitions(builder)
	_register_air_transitions(builder)
	_register_attack_transitions(builder)
	_register_reaction_transitions(builder)
	_register_lock_transition(builder)
	_register_global_transition_rules(builder)
	builder.start_at(&"idle")
	return builder.build()


## 添加基础移动、攻防、受击、倒地与终止状态。
func _add_states(builder) -> void:
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
	builder.add_state(&"stand_light", FoundationAttackState.new(&"stand_light", false))
	builder.add_state(&"stand_heavy", FoundationAttackState.new(&"stand_heavy", false))
	builder.add_state(&"crouch_light", FoundationAttackState.new(&"crouch_light", false))
	builder.add_state(&"crouch_heavy", FoundationAttackState.new(&"crouch_heavy", false))
	builder.add_state(&"air_light", FoundationAttackState.new(&"air_light", true))
	builder.add_state(&"air_heavy", FoundationAttackState.new(&"air_heavy", true))
	builder.add_state(&"hitstun", FoundationHitstunState.new(false))
	builder.add_state(&"air_hitstun", FoundationHitstunState.new(true))
	builder.add_state(&"blockstun", FoundationBlockstunState.new())
	builder.add_state(&"knockdown", FoundationKnockdownState.new())
	builder.add_state(&"tech_roll", FoundationTechRollState.new())
	builder.add_state(&"wakeup", FoundationWakeupState.new())
	builder.add_state(&"ko", FoundationKOState.new())
	builder.add_state(&"locked", FoundationLockedState.new())


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
		_press_config(INPUT_UP)
	)
	_register_sequence_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"dash_forward",
		_sequence_config(SEQUENCE_DASH_FORWARD)
	)
	_register_sequence_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"dash_back",
		_sequence_config(SEQUENCE_DASH_BACK)
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
		INPUT_UP,
		PackedStringArray(["can_double_jump"])
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_DOUBLE_JUMP_SOURCE,
		&"double_jump",
		double_jump_config
	)


## 注册全部地面和空中攻击的输入与收尾转移。
func _register_attack_transitions(builder) -> void:
	_register_ground_attack_input_transitions(builder)
	_register_air_attack_input_transitions(builder)
	_register_ground_attack_exit_transitions(builder)
	_register_air_attack_exit_transitions(builder)


## 注册站立移动状态和下蹲状态中的轻重攻击输入。
func _register_ground_attack_input_transitions(builder) -> void:
	_register_press_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"stand_light",
		_press_config(INPUT_LIGHT)
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_STANDING_NEUTRAL,
		&"stand_heavy",
		_press_config(INPUT_HEAVY)
	)
	builder.transition_press(&"crouch", &"crouch_light", _press_config(INPUT_LIGHT))
	builder.transition_press(&"crouch", &"crouch_heavy", _press_config(INPUT_HEAVY))


## 注册跳跃、二段跳和下落状态中的轻重攻击输入。
func _register_air_attack_input_transitions(builder) -> void:
	_register_press_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK_SOURCE,
		&"air_light",
		_press_config(INPUT_LIGHT)
	)
	_register_press_transitions_from_tag(
		builder,
		TAG_AIR_ATTACK_SOURCE,
		&"air_heavy",
		_press_config(INPUT_HEAVY)
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
		INPUT_GUARD,
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
		PackedStringArray(["stand_light", "stand_heavy", "crouch_light", "crouch_heavy"]),
		PackedStringArray([
			TAG_GROUNDED,
			TAG_GROUND_ATTACK,
			TAG_ATTACK,
			TAG_CONTROLLABLE,
		])
	)
	_tag_states(
		builder,
		PackedStringArray(["air_light", "air_heavy"]),
		PackedStringArray([
			TAG_AIRBORNE,
			TAG_AIR_ATTACK,
			TAG_ATTACK,
			TAG_CONTROLLABLE,
		])
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
