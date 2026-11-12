extends Node
const InputTest = preload("res://tests/input/input_test_support.gd")
## 隔离输入采样，直接验证构建和招式发动许可，不掩盖或修改 Fray 输入插件错误。

var checks := 0
var failures := 0
var grounded_flag := true
const ATTACK := &"light_attack"


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
	for path: String in ["jump", "medium_attack"]:
		var state := FighterStateDefinition.new()
		state.state_id = &"0001000500" if path == "jump" else &"0101000200"

		state.state_name = StringName(path.get_file())
		state.state_script = load("res://scripts/states/fighterstates/idle_state.gd")
		state.animation_key = &"idle"  # 测试占位动画，仍走基类必播协议。
		state.hit_state_definition = actor.loadout.state_library.states[0].hit_state_definition
		actor.loadout.state_library.states.append(state)
	actor.loadout.selected_state_names = actor.loadout.selected_state_names.duplicate()
	actor.loadout.selected_state_names.append_array([&"jump", &"medium_attack"])
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
		for paths in [[&"jump", &"medium_attack"], [&"medium_attack", &"jump"]]:
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
	actor.advancer.set_physics_process(false)
	actor.state_machine.get_root().set_condition(&"grounded", func() -> bool: return grounded_flag)
	return actor


func _candidate(actor: Fighter) -> FighterMoveDefinition:
	return actor.loadout.move_library.moves[0]


## 返回已选转换中的招式发动规则。
func _launch_rules(actor: Fighter) -> Array[FighterTransitionDefinition]:
	return actor._selected_transitions.filter(func(rule: FighterTransitionDefinition) -> bool:
		return not rule.command.is_empty())


func _run() -> void:
	var actor := _spawn()
	var root := actor.state_machine.get_root()
	var candidate := _candidate(actor)
	_check(_launch_rules(actor).size() == 3, "three equipped source edges collected from transition library")
	_check(actor._selected_transitions.size() == 16, "selected_transitions includes native, return and move rules")
	_check(not InputTest.ordinary(actor), "no move candidate means no automatic attack")
	for source in [&"idle", &"fwalk", &"bwalk"]:
		root.goto(source)
		_check(InputTest.try_move(actor, candidate), "configured edge authorizes %s -> light_attack" % source)
		_check(root.get_active_states_info().path == ATTACK, "configured target entered")
		var attack := root.get_state(ATTACK) as BasicAttackState
		_check(not attack.attack_attributes.is_empty() and attack.elapsed_frames == 0, "attack reads its Attribute configuration on entry without move data")
		_check(not InputTest.try_move(actor, candidate), "attack cannot restart without a self-edge")
	for source in [&"crouch", &"jump", &"medium_attack"]:
		root.goto(source)
		_check(not InputTest.try_move(actor, candidate), "missing edge denies %s -> light_attack" % source)
		_check(root.get_active_states_info().path == source, "denied request keeps source state")
	root.goto(&"idle")
	grounded_flag = false
	_check(not InputTest.try_move(actor, candidate), "transition grounded prereq is enforced")
	grounded_flag = true
	_check(InputTest.try_move(actor, candidate), "transition becomes eligible when grounded")
	var attack := root.get_state(ATTACK) as BasicAttackState
	_check(not InputTest.ordinary(actor), "normal return cannot skip unfinished attack")
	for i in attack.total_frames():
		attack._physics_process_impl(1.0 / 60.0)
	_check(InputTest.ordinary(actor), "completed attack uses ordinary return edge")
	_check(root.get_active_states_info().path == &"idle", "return destination remains idle")
	var idle_rule := _launch_rules(actor)[0].duplicate() as FighterTransitionDefinition
	InputTest.set_rules(actor, [idle_rule])
	idle_rule.advance_conditions = ["grounded"]
	idle_rule.prereqs = []
	InputTest.set_rules(actor, [idle_rule])
	grounded_flag = false
	_check(not InputTest.try_move(actor, candidate), "move-triggered rules also evaluate advance_conditions")
	grounded_flag = true
	root.goto(ATTACK, {"move": candidate})
	idle_rule.from_state = ATTACK
	InputTest.set_rules(actor, [idle_rule])
	_check(not InputTest.try_move(actor, candidate), "AT_END edge waits for current leaf completion")
	idle_rule.switch_mode = FrayStateMachineTransition.SwitchMode.IMMEDIATE
	InputTest.set_rules(actor, [idle_rule])
	_check(InputTest.try_move(actor, candidate), "IMMEDIATE edge can explicitly authorize cancellation")
	actor.free()
	actor = _spawn(true)
	_check(_launch_rules(actor).size() == 2, "removing a library edge removes the corresponding launch permission")
	_check(not InputTest.try_move(actor, _candidate(actor)), "equipped move without idle edge cannot start from idle")
	actor.free()
	actor = _spawn(false, false)
	_check(_launch_rules(actor).is_empty(), "unequipped move has no launch edges")
	_check(actor._selected_transitions.size() == 12, "unselected light attack filters its explicit return even if another attack state exists")
	_check(not actor.state_machine.get_root().has_state(ATTACK), "unequipped move does not assemble attack state")
	_check(not InputTest.try_move(actor, _candidate(actor)), "unequipped move request cannot bypass transition assembly")
	actor.free()
	actor = _spawn(false, true, true)
	root = actor.state_machine.get_root()
	root.goto(&"jump")
	grounded_flag = false
	_check(not InputTest.ordinary(actor), "native flat ordinary edge checks conditions")
	_check(root.get_active_states_info().path == &"jump", "failed flat edge retains its exact source")
	grounded_flag = true
	_check(InputTest.ordinary(actor), "native flat ordinary edge needs no move candidate")
	_check(root.get_active_states_info().path == &"medium_attack", "native flat ordinary edge enters the exact direct destination")
	_check(InputTest.ordinary(actor), "reverse native flat ordinary edge is supported")
	_check(root.get_active_states_info().path == &"jump", "reverse edge uses its direct target without group defaults")
	root.goto(&"idle")
	var native_root := root
	native_root.set_condition(&"inputed_fwalk", func() -> bool: return true)
	_check(native_root.has_transition(&"idle", &"fwalk"), "all movement edges belong to the single native root")
	_check(InputTest.ordinary(actor), "flat native edge still advances")
	_check(root.get_active_states_info().path == &"fwalk", "flat edge preserves its direct destination")
	actor.free()
	_test_launch_target_contract()
	_test_endpoint_selection()
	print("MOVE TRANSITION TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## 目标一致性由内容作者保证，在测试中检查资源，不在发动热路径重复检查。
func _test_launch_target_contract() -> void:
	var loadout := load("res://resource/characters/demo_loadout.tres") as FighterLoadout
	var moves: Dictionary[StringName, FighterMoveDefinition] = {}
	for move in loadout.move_library.moves:
		moves[move.command.command_id] = move
	for rule in loadout.transition_library.transitions:
		if not rule.command.is_empty():
			_check(rule.to_state == (moves[rule.command].state as FighterStateDefinition).state_name, "authored launch target matches move entry: " + String(rule.transition_id))


## 默认装配只有根入口；未装配端点照常过滤。
func _test_endpoint_selection() -> void:
	var actor := _spawn()
	var loadout := actor.loadout.duplicate() as FighterLoadout
	loadout.selected_state_names = [&"idle"]
	loadout.selected_move_ids = []
	var builder := FighterSMBuilder.new()
	var root := builder.build(actor, loadout, loadout.resolve_selection())
	_check(builder.selected_transitions.is_empty(), "idle-only selection contains no dangling launch or return edges")
	_check(root.has_state(&"idle") and not root.has_state(ATTACK), "only selected direct state exists")
	_check(root._states.size() == 1, "idle-only selection creates no implicit owner groups")
	_check(root.start_state == &"idle", "one explicit root entry replaces per-group starts")
	loadout.selected_move_ids = [&"01010001"]
	root = builder.build(actor, loadout, loadout.resolve_selection())
	_check(root.has_state(ATTACK) and root.get_state(ATTACK).get_parent() == root, "equipped attack is a direct root child")
	_check(not root.get_state(ATTACK) is FrayCompoundState, "attack leaf has no unnecessary compound wrapper")
	_check(builder.selected_transitions.size() == 2, "idle plus attack selects one launch and one explicit return")
	_check(builder.selected_transitions[0].transition_id == &"light_attack_to_idle", "explicit return keeps authored identity/order")
	_check(root.has_transition(ATTACK, &"idle") and root.has_transition(&"idle", ATTACK), "launch and return both use native direct transitions")
	_check(not root.has_state(&"fwalk"), "attack selection does not pull in extra launch sources")
	loadout.selected_move_ids = []
	loadout.selected_state_names = [&"idle", ATTACK]
	root = builder.build(actor, loadout, loadout.resolve_selection())
	_check(builder.selected_transitions.size() == 2, "input edges depend on installed endpoints, not move identity")
	loadout.selected_move_ids = [&"01010001"]
	loadout.transition_library = loadout.transition_library.duplicate()
	loadout.transition_library.transitions = loadout.transition_library.transitions.duplicate()
	var parallel := actor._selected_transitions.filter(func(rule: FighterTransitionDefinition) -> bool:
		return rule.transition_id == &"idle_to_light_attack")[0].duplicate() as FighterTransitionDefinition
	parallel.transition_id = &"test_parallel_launch"
	parallel.prereqs = PackedStringArray(["!grounded"])
	loadout.transition_library.transitions.append(parallel)
	var self_rule := parallel.duplicate() as FighterTransitionDefinition
	self_rule.transition_id = &"test_self_launch"
	self_rule.from_state = ATTACK
	loadout.transition_library.transitions.append(self_rule)
	var missing := FighterTransitionDefinition.new()
	missing.from_state = &"idle"
	missing.to_state = &"missing"
	missing.prereqs = PackedStringArray(["unmapped_filtered_condition"])
	loadout.transition_library.transitions.append(missing)
	root = builder.build(actor, loadout, loadout.resolve_selection())
	_check(builder.selected_transitions.size() == 4, "parallel and self edges preserved; absent target filtered")
	_check(builder.selected_transitions[2] == parallel and builder.selected_transitions[3] == self_rule, "resource order and distinct parallel identities preserved")
	_check(root.get_next_transitions(&"idle").size() == 2 and root.has_transition(ATTACK, ATTACK), "native graph registers parallel and self edges without collapsing")
	loadout.selected_state_names = [ATTACK, &"idle"]
	root = builder.build(actor, loadout, loadout.resolve_selection())
	_check(root.start_state == &"idle", "selection ordering does not choose a different root entry")
	loadout.selected_state_names = [ATTACK]
	loadout.selected_move_ids = []
	loadout.entry_state = ATTACK
	root = builder.build(actor, loadout, loadout.resolve_selection())
	_check(root.start_state == ATTACK and not root.has_state(&"idle"), "attack-only flat selection has its own explicit entry")
	_check(builder.selected_transitions.size() == 1 and builder.selected_transitions[0] == self_rule, "only authored self edge remains when other endpoints are absent")
	actor.free()
