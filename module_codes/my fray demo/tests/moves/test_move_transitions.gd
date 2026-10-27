extends Node
## 隔离输入采样，直接验证构建和招式发动许可，不掩盖或修改 Fray 输入插件错误。

var checks := 0
var failures := 0
var grounded_flag := true
const ATTACK := &"action/basic_attack/light_attack"


func _enter_tree() -> void:
	FrayInput.set_physics_process(false)


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)


func _spawn(remove_idle_rule: bool = false, equip: bool = true, cross_rules: bool = false) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = actor.loadout.duplicate()
	actor.loadout.state_library = actor.loadout.state_library.duplicate()
	actor.loadout.state_library.states = actor.loadout.state_library.states.duplicate()
	# 仅测试夹具增加 jump/medium_attack：两者虽已装配，但没有发动轻攻击的边。
	for path: String in ["neutral/jump", "action/basic_attack/medium_attack"]:
		var state := FighterStateDefinition.new()
		state.group_path = StringName(path.get_base_dir())
		state.state_name = StringName(path.get_file())
		state.state_script = load("res://scripts/states/fighterstates/neutral/idle_state.gd")
		actor.loadout.state_library.states.append(state)
	actor.loadout.selected_state_paths = actor.loadout.selected_state_paths.duplicate()
	actor.loadout.selected_state_paths.append_array([&"neutral/jump", &"action/basic_attack/medium_attack"])
	if not equip:
		actor.loadout.selected_move_ids = []
	# 使用实际规则条件；只复制库数组以隔离删边和新增边的专项夹具。
	actor.loadout.transition_library = actor.loadout.transition_library.duplicate()
	actor.loadout.transition_library.transitions = actor.loadout.transition_library.transitions.duplicate()
	if remove_idle_rule:
		actor.loadout.transition_library.transitions = actor.loadout.transition_library.transitions.filter(
			func(rule: FighterTransitionDefinition) -> bool:
				return rule.transition_id != &"idle_to_light_attack")
	if cross_rules:
		for paths in [[&"neutral/jump", &"action/basic_attack/medium_attack"], [&"action/basic_attack/medium_attack", &"neutral/jump"]]:
			var rule := FighterTransitionDefinition.new()
			rule.transition_id = StringName("test_" + String(paths[0]).get_file())
			rule.from_state = paths[0]
			rule.to_state = paths[1]
			rule.prereqs = ["grounded"]
			actor.loadout.transition_library.transitions.append(rule)
	add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.fighter_input.set_physics_process(false)
	actor.state_machine.get_root().set_condition(&"grounded", func() -> bool: return grounded_flag)
	return actor


func _candidate(actor: Fighter) -> Dictionary:
	return {"move": actor.loadout.move_library.moves[0], "created_frame": 0}


## 返回已选转换中的招式发动规则。
func _launch_rules(actor: Fighter) -> Array[FighterTransitionDefinition]:
	return actor._selected_transitions.filter(func(rule: FighterTransitionDefinition) -> bool:
		return not rule.move_id.is_empty())


func _run() -> void:
	var actor := _spawn()
	var root := actor.state_machine.get_root()
	var candidate := _candidate(actor)
	_check(_launch_rules(actor).size() == 3, "three equipped source edges collected from transition library")
	_check(actor._selected_transitions.size() == 16, "selected_transitions includes native, return and move rules")
	_check(not actor.advance_commands(), "no move candidate means no automatic attack")
	for source in [&"neutral/idle", &"neutral/fwalk", &"neutral/bwalk"]:
		root.goto(source)
		_check(actor._try_move(candidate), "configured edge authorizes %s -> light_attack" % source)
		_check(root.get_active_states_info().path == ATTACK, "configured target entered")
		var attack := root.get_state(ATTACK) as BasicAttackState
		_check(attack.move == candidate.move and attack.elapsed_frames == 0, "move configuration is passed to a fresh execution")
		_check(not actor._try_move(candidate), "attack cannot restart without a self-edge")
	for source in [&"neutral/crouch", &"neutral/jump", &"action/basic_attack/medium_attack"]:
		root.goto(source)
		_check(not actor._try_move(candidate), "missing edge denies %s -> light_attack" % source)
		_check(root.get_active_states_info().path == source, "denied request keeps source state")
	root.goto(&"neutral/idle")
	grounded_flag = false
	_check(not actor._try_move(candidate), "transition grounded prereq is enforced")
	grounded_flag = true
	_check(actor._try_move(candidate), "transition becomes eligible when grounded")
	var attack := root.get_state(ATTACK) as BasicAttackState
	_check(not actor.advance_commands(), "normal return cannot skip unfinished attack")
	for i in candidate.move.total_frames():
		attack._physics_process_impl(1.0 / 60.0)
	_check(actor.advance_commands(), "completed attack uses ordinary return edge")
	_check(root.get_active_states_info().path == &"neutral/idle", "return destination remains idle")
	var idle_rule := _launch_rules(actor)[0].duplicate() as FighterTransitionDefinition
	actor._selected_transitions = [idle_rule]
	idle_rule.advance_conditions = ["grounded"]
	idle_rule.prereqs = []
	grounded_flag = false
	_check(not actor._try_move(candidate), "move-triggered rules also evaluate advance_conditions")
	grounded_flag = true
	root.goto(ATTACK, {"move": candidate.move})
	idle_rule.from_state = ATTACK
	_check(not actor._try_move(candidate), "AT_END edge waits for current leaf completion")
	idle_rule.switch_mode = FrayStateMachineTransition.SwitchMode.IMMEDIATE
	_check(actor._try_move(candidate), "IMMEDIATE edge can explicitly authorize cancellation")
	actor.free()
	actor = _spawn(true)
	_check(_launch_rules(actor).size() == 2, "removing a library edge removes the corresponding launch permission")
	_check(not actor._try_move(_candidate(actor)), "equipped move without idle edge cannot start from idle")
	actor.free()
	actor = _spawn(false, false)
	_check(_launch_rules(actor).is_empty(), "unequipped move has no launch edges")
	_check(actor._selected_transitions.size() == 13, "ordinary group return is selected because medium_attack makes action available")
	_check(not actor.state_machine.get_root().has_state(ATTACK), "unequipped move does not assemble attack state")
	_check(not actor._try_move(_candidate(actor)), "unequipped move request cannot bypass transition assembly")
	actor.free()
	actor = _spawn(false, true, true)
	root = actor.state_machine.get_root()
	root.goto(&"neutral/jump")
	grounded_flag = false
	_check(not actor.advance_commands(), "cross-group ordinary edge checks conditions")
	_check(root.get_active_states_info().path == &"neutral/jump", "failed cross-group edge retains its exact source")
	grounded_flag = true
	_check(actor.advance_commands(), "cross-group ordinary edge needs no move candidate")
	_check(root.get_active_states_info().path == &"action/basic_attack/medium_attack", "cross-group ordinary edge enters the exact deep destination")
	_check(actor.advance_commands(), "reverse cross-group ordinary edge is supported")
	_check(root.get_active_states_info().path == &"neutral/jump", "reverse edge uses its full target rather than the group's default")
	root.goto(&"neutral/idle")
	var neutral := root.get_state(&"neutral") as FrayCompoundState
	neutral.set_condition(&"inputed_fwalk", func() -> bool: return true)
	_check(neutral.has_transition(&"idle", &"fwalk"), "same-parent full paths infer the native Fray owner")
	_check(actor.advance_commands(), "same-group native edge still advances")
	_check(root.get_active_states_info().path == &"neutral/fwalk", "same-group edge preserves its full destination")
	actor.free()
	_test_endpoint_selection()
	print("MOVE TRANSITION TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 验证转换只由端点可用性和已装备招式决定，并保留库顺序与多条规则。
func _test_endpoint_selection() -> void:
	var actor := _spawn()
	var loadout := actor.loadout.duplicate() as FighterLoadout
	loadout.selected_state_paths = [&"neutral/idle"]
	loadout.selected_move_ids = []
	var builder := FighterSMBuilder.new()
	var root := builder.build(actor, loadout)
	_check(builder.selected_transitions.is_empty(), "idle alone has no eligible edges or empty-group return")
	_check(root.has_state(&"neutral/idle") and not root.has_state(ATTACK), "only selected leaf is assembled without moves")
	_check(not root.has_state(&"neutral/fwalk"), "unselected ordinary endpoints are not assembled")

	loadout.selected_move_ids = [&"01010001"]
	root = builder.build(actor, loadout)
	_check(root.has_state(ATTACK), "equipped move adds its required state without transition declarations")
	_check(builder.selected_transitions.size() == 2, "idle and light attack automatically select launch and group return")
	_check(builder.selected_transitions[0].transition_id == &"action_to_neutral", "eligible parent-group edge retains library order")
	_check(builder.selected_transitions[1].transition_id == &"idle_to_light_attack", "eligible launch edge retains library order")
	_check(not root.has_state(&"neutral/fwalk"), "equipped attack does not pull in other launch sources")

	loadout.selected_move_ids = []
	loadout.selected_state_paths = [&"neutral/idle", ATTACK]
	root = builder.build(actor, loadout)
	_check(root.has_state(ATTACK), "move state may also be explicitly assembled")
	_check(builder.selected_transitions.size() == 1 and builder.selected_transitions[0].move_id.is_empty(), "unequipped move launch is filtered even when both endpoints exist")

	loadout.selected_move_ids = [&"01010001"]
	loadout.transition_library = loadout.transition_library.duplicate()
	loadout.transition_library.transitions = loadout.transition_library.transitions.duplicate()
	var parallel_rule := actor._selected_transitions.filter(
		func(rule: FighterTransitionDefinition) -> bool:
			return rule.transition_id == &"idle_to_light_attack")[0].duplicate() as FighterTransitionDefinition
	parallel_rule.transition_id = &"test_parallel_launch"
	parallel_rule.prereqs = ["!grounded"]
	loadout.transition_library.transitions.append(parallel_rule)
	var self_rule := parallel_rule.duplicate() as FighterTransitionDefinition
	self_rule.transition_id = &"test_self_launch"
	self_rule.from_state = ATTACK
	loadout.transition_library.transitions.append(self_rule)
	var missing_rule := FighterTransitionDefinition.new()
	missing_rule.transition_id = &"test_missing_endpoint"
	missing_rule.from_state = &"neutral/idle"
	missing_rule.to_state = &"neutral/missing"
	missing_rule.prereqs = ["unmapped_filtered_condition"]
	loadout.transition_library.transitions.append(missing_rule)
	root = builder.build(actor, loadout)
	_check(builder.selected_transitions.size() == 4, "parallel and self rules are selected but missing endpoint is filtered")
	_check(builder.selected_transitions[2] == parallel_rule, "same endpoint pair does not collapse distinct rules")
	_check(builder.selected_transitions[3] == self_rule, "self-transition remains eligible without pair enumeration")
	loadout.selected_state_paths = [ATTACK, &"neutral/idle"]
	root = builder.build(actor, loadout)
	_check(builder.selected_transitions[0].transition_id == &"action_to_neutral" and builder.selected_transitions[2] == parallel_rule, "state selection order does not reorder the transition library")
	actor.free()
