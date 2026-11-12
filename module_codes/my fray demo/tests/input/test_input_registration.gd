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
	check(actor.state_machine.get_script() == load("res://addons/fray/src/state_mgmt/state_machine.gd"), "existing state-machine node uses original Fray script")
	check(not actor.has_node("FighterInputContext"), "no input-context node added")
	check(FrayInputMap.has_input(&"move_left") and FrayInputMap.has_input(FighterInputBindings.FORWARD), "selection config registers base and relative inputs")
	check(FighterInputBindings.get_device_input(actor.controller.device) == actor.fighter_input, "device binding points to actor FighterInput")
	check(is_equal_approx(FighterInput.frames_to_seconds(6), 0.1), "six ticks convert to fractional seconds without integer truncation")
	check(Fray.msec_to_frame(100) == 6, "existing Fray millisecond helper reused")
	var before := FrayInputMap.get_bind_names().size()
	FighterInputBindings.register_inputs(FrayInputMap, actor.fighter_input._commands)
	check(FrayInputMap.get_bind_names().size() == before, "registration is idempotent")
	T.inputs(actor, [&"move_right"])
	check(actor.fighter_input.has_intent(&"fwalk"), "native conditional input maps facing-right forward")
	T.turn(actor, -1)
	T.inputs(actor, [&"move_right"])
	check(actor.fighter_input.has_intent(&"bwalk"), "same world-right maps facing-left backward")
	T.inputs(actor, [&"move_left", &"move_right"])
	check(actor.fighter_input.has_intent(&"idle"), "opposite horizontal inputs cancel")
	T.inputs(actor, [&"crouch", &"move_right"])
	check(actor.fighter_input.has_intent(&"crouch") and actor.fighter_input.get_movement_axis(&"fwalk") == 0.0, "crouch suppresses walking")
	var second: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	second.get_node("FrayController").device = 1
	add_child(second)
	T.pause(second)
	check(FighterInputBindings.get_device_input(0) == actor.fighter_input and FighterInputBindings.get_device_input(1) == second.fighter_input, "two device identities retain independent device ownership")
	T.turn(second, -1)
	check(actor.fighter_input.facing_dir == -1 and second.fighter_input.facing_dir == -1, "each device has its own published context object")
	check(actor.fighter_input.matcher != second.fighter_input.matcher, "different characters never share a matcher runtime instance")
	second.free()
	check(FighterInputBindings.get_device_input(0) == actor.fighter_input and FighterInputBindings.get_device_input(1) == null, "releasing second device binding does not unregister the first")
	var definitions := FrayInputMap.get_composite_input_names().duplicate()
	var forward_input := FrayInputMap.get_composite_input(FighterInputBindings.FORWARD)
	var original_matcher := actor.fighter_input.matcher
	for facing in [1, -1, 1, -1]:
		T.turn(actor, facing)
		T.inputs(actor, [&"move_right"])
	check(FrayInputMap.get_composite_input_names() == definitions and FrayInputMap.get_composite_input(FighterInputBindings.FORWARD) == forward_input, "repeated side/facing changes reuse registered conditional definitions without re-registration")
	check(actor.fighter_input.matcher == original_matcher, "ordinary turns do not rebuild the single character matcher")
	var node_count := actor.get_child_count()
	check(node_count == 6, "fighter retains five authored children plus existing runtime hit manager")
	actor.free()
	check(FighterInputBindings.get_device_input(0) == null, "destroying actor unregisters weak device binding")
	var empty: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	empty.loadout = empty.loadout.duplicate()
	empty.loadout.selected_move_ids = []
	add_child(empty)
	T.pause(empty)
	T.inputs(empty, [&"move_left"])
	check(empty.fighter_input.has_intent(&"bwalk") and empty.fighter_input._commands.is_empty(), "empty move selection still registers and samples movement")
	check(empty.advancer.get_buffer().is_empty(), "empty selection has no commands")
	empty.free()
	print("INPUT REGISTRATION TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
