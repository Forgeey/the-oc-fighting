extends Node
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
	_check(_path() == StringName("neutral/" + state_name), description)


func _pause_actor(actor: Fighter, paused: bool) -> void:
	actor.set_physics_process(not paused)
	actor.fighter_input.set_physics_process(not paused)
	actor.state_machine.set_physics_process(not paused)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _spawn(paths: Array[StringName]) -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = fighter.loadout.duplicate()
	actor.loadout.selected_state_paths = paths
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
	_expect(&"idle", "default entry remains neutral/idle")
	var root := fighter.state_machine.get_root()
	_check(root.get_state(&"neutral/bwalk") is BWalkState, "bwalk is assembled from state library")
	_check(root.get_state(&"neutral/crouch") is CrouchState, "crouch is assembled from state library")
	_check(fighter.loadout.selected_move_ids == [&"01010001"], "default character equips light attack by ID")
	_check(root.get_state(&"action/basic_attack/light_attack") is BasicAttackState, "move dependency is assembled from state library")
	_check(fighter.state_machine.advance_mode == FrayStateMachine.AdvanceMode.MANUAL, "single manual transition scheduler is preserved")
	var standing_size: Vector2 = fighter.body_shape.shape.size
	var standing_pos := fighter.body_shape.position
	var feet := standing_pos.y + standing_size.y * 0.5

	# Every directed edge is checked with exactly one ordinary advance, no goto fallback.
	for source in STATE_INPUTS:
		for target in STATE_INPUTS:
			fighter.state_machine.goto(StringName("neutral/" + source))
			_inputs(STATE_INPUTS[target])
			var advanced := fighter.advance_commands()
			_expect(target, "%s -> %s in one advance" % [source, target])
			_check(advanced == (source != target), "%s -> %s does not re-enter held state" % [source, target])
			_check(fighter.sprite.animation == target, "%s selects its own animation" % target)
			_check(is_equal_approx(fighter.body_shape.position.y + fighter.body_shape.shape.size.y * 0.5, feet), "feet stay aligned after %s -> %s" % [source, target])
			var expected_height := standing_size.y * (0.5 if target == &"crouch" else 1.0)
			_check(is_equal_approx(fighter.body_shape.shape.size.y, expected_height), "body height matches %s" % target)

	for horizontal in [&"move_left", &"move_right"]:
		_inputs([horizontal, &"move_down", &"crouch"])
		fighter.advance_commands()
		_expect(&"crouch", "diagonal down overrides %s" % horizontal)
		_check(not fighter.inputed_fwalk() and not fighter.inputed_bwalk(), "crouch suppresses both walk intentions")
		_check(fighter.get_forward_axis() == 0.0 and fighter.get_backward_axis() == 0.0, "diagonal crouch has no horizontal movement axis")
	_inputs([&"move_left", &"move_right"])
	fighter.advance_commands()
	_expect(&"idle", "opposite horizontal inputs cancel")
	_inputs([&"move_down"])
	_check(fighter.fighter_input.get_direction() == 2 and not fighter.inputed_crouch(), "direction-only down stays separate from rebindable crouch")
	_inputs([&"crouch"])
	fighter.advance_commands()
	_expect(&"crouch", "independent crouch binding works")
	_check(fighter.fighter_input.get_direction() == 5, "crouch alias does not manufacture a direction event")
	_inputs([&"move_down", &"move_left", &"crouch"])
	_check(fighter.fighter_input.get_direction() == 1, "diagonal direction remains available to command matching")

	fighter.set_facing(-1)
	_inputs([&"move_left"])
	fighter.advance_commands()
	_expect(&"fwalk", "facing left makes world-left forward")
	_check(fighter.get_forward_axis() < 0.0 and not fighter.sprite.flip_h, "left-facing input and visual stay synchronized")
	_inputs([&"move_right"])
	fighter.advance_commands()
	_expect(&"bwalk", "facing left makes world-right backward")
	_check(fighter.get_backward_axis() > 0.0, "backward movement uses world-right axis when facing left")
	fighter.set_facing(1)
	_inputs([&"move_right"])
	fighter.advance_commands()
	_expect(&"fwalk", "held input changes walk state after facing changes")

	_inputs([&"crouch"])
	fighter.advance_commands()
	fighter.controller.disabled = true
	fighter.fighter_input.sample()
	fighter.advance_commands()
	_expect(&"idle", "disabled controller exits crouch")
	_check(not fighter.inputed_crouch() and fighter.fighter_input.get_horizontal_axis() == 0.0, "disabled controller clears held intentions")
	fighter.controller.disabled = false
	_inputs([&"crouch"])
	fighter.advance_commands()
	fighter.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	fighter.advance_commands()
	_expect(&"idle", "focus loss clears crouch")
	fighter.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_inputs([])

	var second := _spawn([&"neutral/idle", &"neutral/fwalk", &"neutral/bwalk", &"neutral/crouch"])
	_check(second.loadout.state_library == fighter.loadout.state_library, "fighters share immutable state-library resources")
	_check(second.state_machine.get_root().get_state(&"neutral/crouch") != root.get_state(&"neutral/crouch"), "crouch runtime states are per-fighter")
	_check(second.body_shape.shape != fighter.body_shape.shape, "body shapes are per-fighter")
	fighter.state_machine.goto(&"neutral/crouch")
	_check(second.body_shape.shape.size == standing_size, "one fighter crouching cannot resize another")
	fighter.state_machine.goto(&"neutral/idle")
	second.free()

	# Endpoint filtering and old two-state loadouts must still work with the larger library.
	var minimal := _spawn([&"neutral/idle"])
	_check(not minimal.state_machine.get_root().has_state(&"neutral/bwalk"), "idle-only character does not instantiate bwalk")
	_check(not minimal.state_machine.get_root().has_state(&"neutral/crouch"), "idle-only character does not instantiate crouch")
	_check(minimal.state_machine.get_root().get_state(&"neutral").get_next_transitions(&"idle").is_empty(), "idle-only character has no dangling transitions")
	minimal.free()
	var old_loadout := _spawn([&"neutral/idle", &"neutral/fwalk"])
	_inputs([&"move_right"])
	old_loadout.fighter_input.sample()
	old_loadout.advance_commands()
	_check(old_loadout.state_machine.get_root().get_active_states_info().path == &"neutral/fwalk", "old idle/fwalk loadout still enters forward walk")
	_inputs([&"move_left"])
	old_loadout.fighter_input.sample()
	old_loadout.advance_commands()
	_check(old_loadout.state_machine.get_root().get_active_states_info().path == &"neutral/idle", "unselected backward state falls back to idle")
	old_loadout.free()

	# Resume the actual scheduling/physics pipeline for speed, friction and floor checks.
	_inputs([])
	fighter.state_machine.goto(&"neutral/idle")
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
	fighter.set_facing(-1)
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
	print("NEUTRAL TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_light_attack() -> void:
	var attack: BasicAttackState = fighter.state_machine.get_root().get_state(&"action/basic_attack/light_attack")
	var duration := fighter.loadout.move_library.moves[0].total_frames()
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
	_check(_path() == &"action/basic_attack/light_attack", "physical J enters equipped light attack")
	_check(fighter.sprite.animation == &"light_attack" and fighter.sprite.is_playing(), "attack animation plays independently of logical completion")
	_check(not fighter.active_leaf_done(), "parent completion cannot end attack before recovery")
	_check(fighter.fighter_input.get_candidates().is_empty(), "successful move consumes its candidate")
	_pause_actor(fighter, true)
	var initial := attack.elapsed_frames
	var initial_x := fighter.position.x
	for i in range(initial, duration):
		_check(not attack.is_done_processing(), "attack incomplete before logical frame %d" % i)
		attack._physics_process_impl(1.0 / 60.0)
		if i + 1 < duration:
			_check(not fighter.advance_commands(), "no early normal exit at logical frame %d" % i)
	_check(attack.is_done_processing() and attack.get_phase() == BasicAttackState.Phase.DONE, "recovery completion marks attack done")
	_check(fighter.advance_commands(), "completed attack takes selected return transition")
	_expect(&"idle", "attack returns to neutral/idle")
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
	_check(_path() == &"action/basic_attack/light_attack" and attack.elapsed_frames < duration, "fresh press restarts attack from new progress")
	fighter.state_machine.goto(&"neutral/idle")
	_inputs([])
	await _frames(2)
	var actor := _spawn([&"neutral/idle"])
	_check(not actor.state_machine.get_root().has_state(&"action/basic_attack/light_attack"), "unequipped move does not instantiate attack state")
	actor.fighter_input.sample()
	_check(actor.fighter_input.get_candidates().is_empty(), "unequipped move registers no input candidate")
	actor.free()


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
	_check(_path() == &"neutral/idle" and fighter.sprite.animation == &"idle", "%s keeps state and configured animation stable" % label)
