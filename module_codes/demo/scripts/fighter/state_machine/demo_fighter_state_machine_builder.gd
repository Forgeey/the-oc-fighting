class_name DemoFighterStateMachineBuilder
extends RefCounted

## 根据固定角色状态和已安装招式指令构建 Fray 状态机拓扑。

const IDLE_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_idle_state.gd")
const WALK_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_walk_state.gd")
const CROUCH_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_crouch_state.gd")
const DASH_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_dash_state.gd")
const JUMP_START_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_jump_start_state.gd")
const JUMP_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_jump_state.gd")
const DOUBLE_JUMP_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_double_jump_state.gd")
const FALL_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_fall_state.gd")
const LAND_STATE = preload("res://scripts/fighter/state_machine/states/locomotion/demo_fighter_land_state.gd")
const ATTACK_STATE = preload("res://scripts/fighter/state_machine/states/combat/demo_fighter_attack_state.gd")
const HITSTUN_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_hitstun_state.gd")
const BLOCKSTUN_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_blockstun_state.gd")
const KNOCKDOWN_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_knockdown_state.gd")
const WAKEUP_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_wakeup_state.gd")
const TECH_ROLL_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_tech_roll_state.gd")
const KO_STATE = preload("res://scripts/fighter/state_machine/states/reaction/demo_fighter_ko_state.gd")


## 使用 Fray builder 配置角色状态机拓扑。
static func configure(
	fighter,
	state_machine: FrayStateMachine,
	attack_module: DemoFighterAttackModule,
	loadout: DemoFighterLoadout
) -> void:
	var builder := FrayCompoundState.builder()
	_add_base_states(builder)
	for move_id in attack_module.get_move_ids():
		var attack := attack_module.get_attack(move_id)
		builder.add_state(StringName(move_id), ATTACK_STATE.new(attack))

	builder.start_at(&"idle")
	var conditions := {
		"wants_crouch": Callable(fighter, "wants_crouch"),
		"wants_walk": Callable(fighter, "wants_walk"),
		"wants_idle": Callable(fighter, "wants_idle"),
		"can_jump": Callable(fighter, "can_jump"),
		"can_double_jump": Callable(fighter, "can_double_jump"),
		"can_ground_dash": Callable(fighter, "can_ground_dash"),
		"can_tech_roll": Callable(fighter, "can_tech_roll"),
		"has_pending_knockdown": Callable(fighter, "has_pending_knockdown"),
		"can_cancel_move_now": Callable(fighter, "can_cancel_move_now"),
		"is_airborne": Callable(fighter, "is_airborne"),
	}
	_add_cancel_conditions(conditions, fighter, loadout)
	builder.register_conditions(conditions)

	_add_base_transitions(builder)
	_add_attack_completion_transitions(builder, attack_module)
	_add_cancel_transitions(builder, loadout, attack_module)
	_add_tags_and_rules(builder, attack_module)
	_add_movement_input_transitions(builder, fighter)
	_add_loadout_input_transitions(builder, fighter, loadout, attack_module)

	state_machine.initialize({"fighter": fighter}, builder.build())
	state_machine.active = true


## 添加基础状态。
static func _add_base_states(builder) -> void:
	builder.add_state(&"idle", IDLE_STATE.new())
	builder.add_state(&"walk", WALK_STATE.new())
	builder.add_state(&"crouch", CROUCH_STATE.new())
	builder.add_state(&"dash_forward", DASH_STATE.new(&"dash_forward", 1))
	builder.add_state(&"dash_back", DASH_STATE.new(&"dash_back", -1))
	builder.add_state(&"jump_start", JUMP_START_STATE.new())
	builder.add_state(&"jump", JUMP_STATE.new())
	builder.add_state(&"double_jump", DOUBLE_JUMP_STATE.new())
	builder.add_state(&"fall", FALL_STATE.new())
	builder.add_state(&"land", LAND_STATE.new())
	builder.add_state(&"hitstun", HITSTUN_STATE.new())
	builder.add_state(&"blockstun", BLOCKSTUN_STATE.new())
	builder.add_state(&"knockdown", KNOCKDOWN_STATE.new())
	builder.add_state(&"wakeup", WAKEUP_STATE.new())
	builder.add_state(&"tech_roll", TECH_ROLL_STATE.new())
	builder.add_state(&"ko", KO_STATE.new())


## 添加基础转移。
static func _add_base_transitions(builder) -> void:
	builder.transition(&"idle", &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
	builder.transition(&"idle", &"walk", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_walk"])})
	builder.transition(&"walk", &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
	builder.transition(&"walk", &"idle", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_idle"])})
	builder.transition(&"crouch", &"idle", {"auto_advance": true, "advance_conditions": PackedStringArray(["!wants_crouch"])})
	builder.transition(&"jump_start", &"jump", {"auto_advance": true})
	builder.transition(&"jump", &"fall", {"auto_advance": true})
	builder.transition(&"double_jump", &"fall", {"auto_advance": true})
	builder.transition(&"fall", &"knockdown", {"auto_advance": true, "advance_conditions": PackedStringArray(["has_pending_knockdown"])})
	builder.transition(&"fall", &"land", {"auto_advance": true})
	builder.transition(&"land", &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
	builder.transition(&"land", &"walk", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_walk"])})
	builder.transition(&"land", &"idle", {"auto_advance": true})
	for dash_id in [&"dash_forward", &"dash_back"]:
		builder.transition(dash_id, &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
		builder.transition(dash_id, &"walk", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_walk"])})
		builder.transition(dash_id, &"idle", {"auto_advance": true})
	builder.transition(&"hitstun", &"knockdown", {"auto_advance": true, "advance_conditions": PackedStringArray(["has_pending_knockdown", "!is_airborne"])})
	builder.transition(&"hitstun", &"fall", {"auto_advance": true, "advance_conditions": PackedStringArray(["is_airborne"])})
	builder.transition(&"hitstun", &"idle", {"auto_advance": true})
	builder.transition(&"blockstun", &"fall", {"auto_advance": true, "advance_conditions": PackedStringArray(["is_airborne"])})
	builder.transition(&"blockstun", &"idle", {"auto_advance": true})
	builder.transition(&"knockdown", &"wakeup", {"auto_advance": true})
	builder.transition(&"wakeup", &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
	builder.transition(&"wakeup", &"walk", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_walk"])})
	builder.transition(&"wakeup", &"idle", {"auto_advance": true})
	builder.transition(&"tech_roll", &"crouch", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_crouch"])})
	builder.transition(&"tech_roll", &"walk", {"auto_advance": true, "advance_conditions": PackedStringArray(["wants_walk"])})
	builder.transition(&"tech_roll", &"idle", {"auto_advance": true})


## 添加攻击完成转移。
static func _add_attack_completion_transitions(builder, attack_module: DemoFighterAttackModule) -> void:
	for move_id in attack_module.get_move_ids():
		var attack_id := StringName(move_id)
		var move := attack_module.get_move(move_id)
		var is_air_attack := move.state_tags.has("air_attack")
		if is_air_attack:
			builder.transition(attack_id, &"land", {
				"auto_advance": true,
				"advance_conditions": PackedStringArray(["!is_airborne"]),
				"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
			})
			builder.transition(attack_id, &"fall", {
				"auto_advance": true,
				"advance_conditions": PackedStringArray(["is_airborne"]),
			})
			continue
		builder.transition(attack_id, &"fall", {"auto_advance": true, "advance_conditions": PackedStringArray(["is_airborne"])})
		builder.transition(attack_id, &"idle", {"auto_advance": true})


## 添加取消条件。
static func _add_cancel_conditions(conditions: Dictionary, fighter, loadout: DemoFighterLoadout) -> void:
	for entry in loadout.get_installed_entries():
		for target_id in loadout.get_cancel_target_ids(entry.move.id):
			var condition_name := _get_cancel_buffer_condition(StringName(target_id))
			if not conditions.has(condition_name):
				conditions[condition_name] = Callable(fighter, "has_buffered_cancel_to").bind(StringName(target_id))


## 添加取消转移。
static func _add_cancel_transitions(
	builder,
	loadout: DemoFighterLoadout,
	attack_module: DemoFighterAttackModule
) -> void:
	for entry in loadout.get_installed_entries():
		var source_id := entry.move.id
		if not attack_module.has_move(source_id):
			continue
		for target_text in loadout.get_cancel_target_ids(source_id):
			var target_id := StringName(target_text)
			if target_id == source_id or not attack_module.has_move(target_id):
				continue
			builder.transition(source_id, target_id, {
				"auto_advance": true,
				"advance_conditions": PackedStringArray([
					_get_cancel_buffer_condition(target_id),
					"can_cancel_move_now",
				]),
				"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
			})


## 返回取消缓冲条件。
static func _get_cancel_buffer_condition(target_id: StringName) -> String:
	return "has_buffered_cancel_to_%s" % target_id


## 添加标签与规则。
static func _add_tags_and_rules(builder, attack_module: DemoFighterAttackModule) -> void:
	builder.tag_multi(PackedStringArray([&"idle", &"walk", &"crouch"]), PackedStringArray(["neutral"]))
	builder.tag_multi(PackedStringArray([&"dash_forward", &"dash_back"]), PackedStringArray(["ground_dash"]))
	builder.tag(&"jump_start", PackedStringArray(["jump_start"]))
	builder.tag_multi(PackedStringArray([&"jump", &"double_jump", &"fall"]), PackedStringArray(["airborne"]))
	builder.tag(&"double_jump", PackedStringArray(["double_jump"]))
	builder.tag_multi(PackedStringArray([&"hitstun", &"blockstun", &"knockdown"]), PackedStringArray(["hit_reaction"]))
	builder.tag(&"knockdown", PackedStringArray(["knockdown"]))
	builder.tag_multi(PackedStringArray([&"wakeup", &"tech_roll"]), PackedStringArray(["recovery"]))
	builder.tag(&"tech_roll", PackedStringArray(["tech_roll"]))
	builder.tag(&"ko", PackedStringArray(["ko"]))
	builder.add_rule(&"neutral", &"jump_start")
	builder.add_rule(&"neutral", &"ground_dash")
	builder.add_rule(&"airborne", &"double_jump")
	builder.add_rule(&"knockdown", &"tech_roll")
	builder.add_rule(&"neutral", &"ground_attack")
	builder.add_rule(&"airborne", &"air_attack")
	for move_id in attack_module.get_move_ids():
		var move := attack_module.get_move(move_id)
		var tags := PackedStringArray(["attack", String(move.id)])
		for tag in move.state_tags:
			if not tags.has(tag):
				tags.append(tag)
		builder.tag(move.id, tags)


## 添加移动输入转移。
static func _add_movement_input_transitions(builder, fighter) -> void:
	builder.transition_press_global(&"jump_start", {
		"input": fighter.fray_input(&"up"),
		"prereqs": PackedStringArray(["can_jump"]),
		"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
	})
	builder.transition_press_global(&"double_jump", {
		"input": fighter.fray_input(&"up"),
		"prereqs": PackedStringArray(["can_double_jump"]),
		"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
	})
	builder.transition_press_global(&"tech_roll", {
		"input": fighter.fray_input(&"block"),
		"prereqs": PackedStringArray(["can_tech_roll"]),
		"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
	})
	builder.transition_sequence_global(&"dash_forward", {
		"sequence": fighter.fray_input(&"dash_forward"),
		"prereqs": PackedStringArray(["can_ground_dash", "!wants_crouch"]),
		"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
	})
	builder.transition_sequence_global(&"dash_back", {
		"sequence": fighter.fray_input(&"dash_back"),
		"prereqs": PackedStringArray(["can_ground_dash", "!wants_crouch"]),
		"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
	})


## 添加招式配置输入转移。
static func _add_loadout_input_transitions(
	builder,
	fighter,
	loadout: DemoFighterLoadout,
	attack_module: DemoFighterAttackModule
) -> void:
	for entry in loadout.get_installed_entries():
		var move := entry.move
		if not attack_module.has_move(move.id) or not move.neutral_available:
			continue
		var options := {
			"prereqs": move.get_input_prereqs(),
			"switch_mode": FrayStateMachineTransition.SwitchMode.IMMEDIATE,
		}
		if entry.command.is_simple_press():
			options["input"] = fighter.fray_input(entry.command.get_simple_input())
			builder.transition_press_global(move.id, options)
		else:
			options["sequence"] = fighter.fray_input(DemoFighterLoadout.get_sequence_input_name(move.id))
			builder.transition_sequence_global(move.id, options)
