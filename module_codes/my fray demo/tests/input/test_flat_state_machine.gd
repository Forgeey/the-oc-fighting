extends Node
const T = preload("res://tests/input/input_test_support.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS: " if value else "FAIL: ", label)

func _run() -> void:
	FrayInput.set_physics_process(false)
	var actor := T.spawn(self)
	var root := actor.state_machine.get_root()
	check(root.get_script() == load("res://addons/fray/src/state_mgmt/state/compound_state.gd"), "Builder creates the original FrayCompoundState root directly")
	check(root.start_state == &"idle" and root.get_current_state_name() == &"idle", "one explicit root entry selects flat idle")
	check(root._states.size() == 5, "default loadout creates exactly five direct children")
	for name in [&"idle", &"fwalk", &"bwalk", &"crouch", &"light_attack"]:
		var state := root.get_state(name)
		check(state.get_parent() == root and not state is FrayCompoundState, "selected state is a direct leaf: " + String(name))
	check(root._states.values().all(func(state: FrayState) -> bool: return not state is FrayCompoundState), "default selection creates only explicit leaves, no implicit groups")
	var edges := root.get_next_transitions(&"idle")
	check(edges.size() == 4 and edges[0].transition is FrayInputTransitionSequence, "native input edges are registered before ordinary movement fallback")
	var input_edge := edges[0].transition as FrayInputTransitionSequence
	check(input_edge.sequence == &"light_attack" and input_edge.auto_advance, "native input edge checks advance gates without accepting empty sequence")
	check(not input_edge.accepts({}), "enabling input advance-condition checking does not cause idle auto-attack")
	check(root.has_transition(&"light_attack", &"idle"), "attack recovery uses an explicit native return edge")
	var attack_definition := (root.get_state(&"light_attack") as FighterState).state_definition
	check(attack_definition.state_name == &"light_attack" and root.get_state(&"light_attack").get_parent() == root, "root attack has only explicit runtime name and empty owner")
	var command := actor.loadout.move_library.moves[0].command.command_id
	actor.advancer.buffer_sequence(command)
	T.drive(actor)
	check(root.get_active_states_info().path == &"light_attack", "unchanged native advancer enters direct attack state")
	var attack := root.get_state(&"light_attack") as BasicAttackState
	check(not T.ordinary(actor), "native AT_END blocks return before direct attack leaf completes")
	attack.elapsed_frames = attack.total_frames()
	check(T.ordinary(actor) and root.get_current_state_name() == &"idle", "native AT_END completes return without parent-group condition workarounds")
	actor.free()

	print("FLAT STATE MACHINE TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
