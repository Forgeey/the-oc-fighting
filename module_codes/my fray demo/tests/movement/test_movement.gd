extends Node
const InputTest = preload("res://tests/input/input_test_support.gd")
## Loaded as a scene so Fray autoloads are available before Fighter compilation.

const ACTIONS: Array[StringName] = FighterInputBindings.ACTIONS
const STATE_INPUTS := {
	&"idle": [], &"fwalk": [&"move_right"], &"bwalk": [&"move_left"],
	&"crouch": [&"move_down", &"crouch"],
}
var checks := 0
var failures := 0
var fighter: Fighter


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		print("FAIL: ", description)


func _inputs(actions: Array) -> void:
	for action in ACTIONS:
		Input.action_release(action)
	for action in actions:
		Input.action_press(action)
	FrayInput._physics_process(1.0 / 60.0)
	fighter.fighter_input.sample()


func _path() -> StringName:
	return fighter.state_machine.get_root().get_active_states_info().path


func _expect(state_name: StringName, description: String) -> void:
	_check(_path() == StringName(state_name), description)


func _pause_actor(actor: Fighter, paused: bool) -> void:
	actor.set_physics_process(not paused)
	actor.fighter_input.set_physics_process(not paused)
	actor.state_machine.set_physics_process(not paused)
	actor.advancer.set_physics_process(not paused)
	if not paused:
		FighterInputBindings.bind_device(actor.controller.device, actor.fighter_input)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _spawn(paths: Array[StringName]) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = fighter.loadout.duplicate()
	actor.loadout.selected_state_names = paths
	actor.loadout.selected_move_ids = []
	actor.position = Vector2(700.0, 640.0)
	add_child(actor)
	_pause_actor(actor, true)
	return actor


func _run() -> void:
	var arena: Node2D = load("res://scenes/arena.tscn").instantiate()
	add_child(arena)
	fighter = arena.get_node("Fighter")
	_check(not fighter.has_node("AnimationPlayer"), "fighter has no unused AnimationPlayer node")
	_pause_actor(fighter, true)
	_expect(&"idle", "default entry is flat idle")
	var root := fighter.state_machine.get_root()
	_check(root.get_state(&"bwalk") is BWalkState, "bwalk is assembled from state library")
	_check(root.get_state(&"crouch") is CrouchState, "crouch is assembled from state library")
	_check(fighter.loadout.selected_move_ids == [&"01010001"], "default character equips light attack by ID")
	_check(root.get_state(&"light_attack") is BasicAttackState, "move dependency is assembled from state library")
	_check(fighter.state_machine.advance_mode == FrayStateMachine.AdvanceMode.MANUAL, "single manual transition scheduler is preserved")
	var standing_size: Vector2 = fighter.body_shape.shape.size
	var standing_pos := fighter.body_shape.position
	var feet := standing_pos.y + standing_size.y * 0.5

	# Every directed edge is checked with exactly one ordinary advance, no goto fallback.
	for source in STATE_INPUTS:
		for target in STATE_INPUTS:
			fighter.state_machine.goto(StringName(source))
			_inputs(STATE_INPUTS[target])
			var advanced := InputTest.ordinary(fighter)
			_expect(target, "%s -> %s in one advance" % [source, target])
			_check(advanced == (source != target), "%s -> %s does not re-enter held state" % [source, target])
			_check(fighter.sprite.animation == target, "%s selects its own animation" % target)
			_check(is_equal_approx(fighter.body_shape.position.y + fighter.body_shape.shape.size.y * 0.5, feet), "feet stay aligned after %s -> %s" % [source, target])
			var expected_height := standing_size.y * (0.5 if target == &"crouch" else 1.0)
			_check(is_equal_approx(fighter.body_shape.shape.size.y, expected_height), "body height matches %s" % target)

	for horizontal in [&"move_left", &"move_right"]:
		_inputs([horizontal, &"move_down", &"crouch"])
		InputTest.ordinary(fighter)
		_expect(&"crouch", "diagonal down overrides %s" % horizontal)
		_check(not fighter.fighter_input.has_intent(&"fwalk") and not fighter.fighter_input.has_intent(&"bwalk"), "crouch suppresses both walk intentions")
		_check(fighter.fighter_input.get_movement_axis(&"fwalk") == 0.0 and fighter.fighter_input.get_movement_axis(&"bwalk") == 0.0, "diagonal crouch has no horizontal movement axis")
	_inputs([&"move_left", &"move_right"])
	InputTest.ordinary(fighter)
	_expect(&"idle", "opposite horizontal inputs cancel")
	_inputs([&"move_down"])
	_check(fighter.fighter_input._direction == 2 and not fighter.fighter_input.has_intent(&"crouch"), "direction-only down stays separate from rebindable crouch")
	_inputs([&"crouch"])
	InputTest.ordinary(fighter)
	_expect(&"crouch", "independent crouch binding works")
	_check(fighter.fighter_input._direction == 5, "crouch alias does not manufacture a direction event")
	_inputs([&"move_down", &"move_left", &"crouch"])
	_check(fighter.fighter_input._direction == 1, "diagonal direction remains available to command matching")

	InputTest.turn(fighter, -1)
	_inputs([&"move_left"])
	InputTest.ordinary(fighter)
	_expect(&"fwalk", "facing left makes world-left forward")
	_check(fighter.fighter_input.get_movement_axis(&"fwalk") < 0.0 and not fighter.sprite.flip_h, "left-facing input and visual stay synchronized")
	_inputs([&"move_right"])
	InputTest.ordinary(fighter)
	_expect(&"bwalk", "facing left makes world-right backward")
	_check(fighter.fighter_input.get_movement_axis(&"bwalk") > 0.0, "backward movement uses world-right axis when facing left")
	InputTest.turn(fighter, 1)
	_inputs([&"move_right"])
	InputTest.ordinary(fighter)
	_expect(&"fwalk", "held input changes walk state after facing changes")

	_inputs([&"crouch"])
	InputTest.ordinary(fighter)
	fighter.controller.disabled = true
	fighter.fighter_input.sample()
	InputTest.ordinary(fighter)
	_expect(&"idle", "disabled controller exits crouch")
	_check(not fighter.fighter_input.has_intent(&"crouch") and fighter.fighter_input._horizontal_axis == 0.0, "disabled controller clears held intentions")
	fighter.controller.disabled = false
	_inputs([&"crouch"])
	InputTest.ordinary(fighter)
	fighter.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	InputTest.ordinary(fighter)
	_expect(&"idle", "focus loss clears crouch")
	fighter.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_inputs([])

	var second := _spawn([&"idle", &"fwalk", &"bwalk", &"crouch"])
	_check(second.loadout.state_library == fighter.loadout.state_library, "fighters share immutable state-library resources")
	_check(second.state_machine.get_root().get_state(&"crouch") != root.get_state(&"crouch"), "crouch runtime states are per-fighter")
	_check(second.body_shape.shape != fighter.body_shape.shape, "body shapes are per-fighter")
	fighter.state_machine.goto(&"crouch")
	_check(second.body_shape.shape.size == standing_size, "one fighter crouching cannot resize another")
	fighter.state_machine.goto(&"idle")
	second.free()

	# Endpoint filtering and old two-state loadouts must still work with the larger library.
	var minimal := _spawn([&"idle"])
	_check(not minimal.state_machine.get_root().has_state(&"bwalk"), "idle-only character does not instantiate bwalk")
	_check(not minimal.state_machine.get_root().has_state(&"crouch"), "idle-only character does not instantiate crouch")
	_check(minimal.state_machine.get_root().get_next_transitions(&"idle").is_empty(), "idle-only character has no dangling transitions")
	minimal.free()
	var old_loadout := _spawn([&"idle", &"fwalk"])
	FighterInputBindings.bind_device(old_loadout.controller.device, old_loadout.fighter_input)
	InputTest.inputs(old_loadout, [&"move_right"])
	InputTest.ordinary(old_loadout)
	_check(old_loadout.state_machine.get_root().get_active_states_info().path == &"fwalk", "old idle/fwalk loadout still enters forward walk")
	InputTest.inputs(old_loadout, [&"move_left"])
	InputTest.ordinary(old_loadout)
	_check(old_loadout.state_machine.get_root().get_active_states_info().path == &"idle", "unselected backward state falls back to idle")
	old_loadout.free()
	FighterInputBindings.bind_device(fighter.controller.device, fighter.fighter_input)

	# Resume the actual scheduling/physics pipeline for speed, friction and floor checks.
	_inputs([])
	fighter.state_machine.goto(&"idle")
	_pause_actor(fighter, false)
	await _frames(6)
	_check(fighter.is_on_floor(), "fighter settles on arena floor")
	await _test_live_idle_stability("initial idle")
	await _test_light_attack()
	var initial_x := fighter.position.x
	_inputs([&"move_left"])
	await _frames(20)
	_expect(&"bwalk", "live physics pipeline enters bwalk")
	_check(fighter.position.x < initial_x, "backward state actually moves left")
	_check(is_equal_approx(fighter.velocity.x, -float(fighter.move_env.bwalk_speed)), "backward speed uses configured bwalk_speed")
	_inputs([&"move_down", &"move_left", &"crouch"])
	await _frames(2)
	var crouch_x := fighter.position.x
	await _frames(10)
	_expect(&"crouch", "live diagonal down holds crouch")
	_check(is_zero_approx(fighter.velocity.x) and is_equal_approx(fighter.position.x, crouch_x), "crouch immediately stops residual walking velocity")
	_check(fighter.is_on_floor(), "crouch retains floor contact")
	_inputs([&"move_right"])
	await _frames(20)
	_expect(&"fwalk", "releasing crouch into forward moves directly to fwalk")
	_check(is_equal_approx(fighter.velocity.x, float(fighter.move_env.fwalk_speed)), "forward speed is unchanged")
	_check(fighter.body_shape.shape.size == standing_size and fighter.body_shape.position == standing_pos, "leaving crouch restores the standing shape exactly")
	_inputs([])
	await _frames(10)
	_expect(&"idle", "releasing walk enters idle")
	_check(is_zero_approx(fighter.velocity.x), "idle friction stops walking velocity")
	await _test_live_idle_stability("idle after releasing movement")
	InputTest.turn(fighter, -1)
	_inputs([&"move_right"])
	await _frames(20)
	_expect(&"bwalk", "live backward movement respects left facing")
	_check(is_equal_approx(fighter.velocity.x, float(fighter.move_env.bwalk_speed)), "left-facing backward speed is positive world velocity")
	fighter.position.x = fighter.move_env.arena_right - 1.0
	await _frames(5)
	_check(fighter.position.x <= fighter.move_env.arena_right and is_zero_approx(fighter.velocity.x), "backward walking respects arena boundary")
	_inputs([])
	arena.queue_free()
	await get_tree().process_frame
	print("MOVEMENT TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_light_attack() -> void:
	var attack: BasicAttackState = fighter.state_machine.get_root().get_state(&"light_attack")
	var duration := (fighter.hit_states[attack.state_definition.hit_state_definition].get_node("Attackbox").attribute as FighterHitboxAttribute).total_frames()
	_check(duration == 24, "light attack uses configured 24 logical frames")
	var has_j := false
	for event in InputMap.action_get_events(&"light_attack"):
		if event is InputEventKey and event.physical_keycode == KEY_J:
			has_j = true
	_check(has_j, "physical J is bound to light_attack")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_check(_path() == &"light_attack", "physical J enters equipped light attack")
	_check(fighter.sprite.animation == &"light_attack" and fighter.sprite.is_playing(), "attack animation plays independently of logical completion")
	_check(not fighter.state_machine.get_root().is_done_processing(), "parent completion cannot end attack before recovery")
	_check(fighter.advancer.get_buffer().is_empty(), "successful move consumes its candidate")
	_pause_actor(fighter, true)
	var initial := attack.elapsed_frames
	var initial_x := fighter.position.x
	for i in range(initial, duration):
		_check(not attack.is_done_processing(), "attack incomplete before logical frame %d" % i)
		attack._physics_process_impl(1.0 / 60.0)
		if i + 1 < duration:
			_check(not InputTest.ordinary(fighter), "no early normal exit at logical frame %d" % i)
	_check(attack.is_done_processing() and attack.get_phase() == BasicAttackState.Phase.DONE, "recovery completion marks attack done")
	_check(InputTest.ordinary(fighter), "completed attack takes selected return transition")
	_expect(&"idle", "attack returns directly to idle")
	_check(is_equal_approx(initial_x, fighter.position.x), "attack does not introduce horizontal movement")
	_pause_actor(fighter, false)
	await _frames(duration + 2)
	_expect(&"idle", "holding J does not automatically repeat attack")
	key = InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	# Re-press starts a fresh execution; interruption must not leak old progress.
	_inputs([&"light_attack"])
	await _frames(2)
	_check(_path() == &"light_attack" and attack.elapsed_frames < duration, "fresh press restarts attack from new progress")
	fighter.state_machine.goto(&"idle")
	_inputs([])
	await _frames(2)
	_pause_actor(fighter, true)
	var actor := _spawn([&"idle"])
	_check(not actor.state_machine.get_root().has_state(&"light_attack"), "unequipped move does not instantiate attack state")
	actor.fighter_input.sample()
	_check(actor.advancer.get_buffer().is_empty(), "unequipped move registers no input candidate")
	actor.free()
	_pause_actor(fighter, false)


## 通过真实采样与物理推进检查每次转换信号，避免偶数次循环被最终状态掩盖。
func _test_live_idle_stability(label: String) -> void:
	var root := fighter.state_machine.get_root()
	var transitions: Array[StringName] = []
	var record := func(_from: StringName, to: StringName) -> void:
		transitions.append(to)
	root.transitioned.connect(record)
	await _frames(12)
	root.transitioned.disconnect(record)
	_check(transitions.is_empty(), "%s has no unsolicited transitions over 12 live physics frames" % label)
	_check(_path() == &"idle" and fighter.sprite.animation == &"idle", "%s keeps state and configured animation stable" % label)
