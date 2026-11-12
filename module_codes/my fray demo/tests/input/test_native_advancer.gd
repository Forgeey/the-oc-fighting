extends Node
const T = preload("res://tests/input/input_test_support.gd")
var checks := 0
var failures := 0
func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS: " if value else "FAIL: ", label)
func _run() -> void:
	FrayInput.set_physics_process(false)
	var actor := T.spawn(self)
	var root := actor.state_machine.get_root()
	var token := actor.loadout.move_library.moves[0].command.command_id
	root.set_condition(&"grounded", func() -> bool: return false)
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(actor.advancer.get_buffer().is_empty() and root.get_active_states_info().path == &"idle", "failed input is popped and discarded")
	root.set_condition(&"grounded", func() -> bool: return true)
	T.drive(actor)
	check(root.get_active_states_info().path == &"idle", "discarded input is not retried later")
	actor.advancer.paused = true
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(actor.advancer.get_buffer().size() == 1, "paused native advancer leaves queue untouched")
	actor.advancer.get_buffer()[0].time_stamp = Time.get_ticks_msec() - 1000
	actor.advancer.paused = false
	T.drive(actor)
	check(actor.advancer.get_buffer().is_empty() and root.get_active_states_info().path == &"idle", "paused time continues and expired input is discarded on resume")
	actor.advancer.buffer_sequence(&"unknown_command")
	actor.advancer.buffer_sequence(token)
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(root.get_active_states_info().path == &"light_attack", "FIFO skips failed entry then accepts valid command")
	check(actor.advancer.get_buffer().size() == 1, "native loop stops after first true and leaves remaining input")
	T.drive(actor)
	check(actor.advancer.get_buffer().is_empty(), "remaining attack request is discarded when current attack has no matching launch edge")
	check(is_equal_approx(actor.advancer.max_buffer_time, 0.1), "one native advancer has one shared configured expiry")
	root.goto(&"idle")
	root.set_condition(&"grounded", func() -> bool: return false)
	T.inputs(actor, [&"move_right"])
	actor.advancer.buffer_sequence(token)
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(root.get_active_states_info().path == &"fwalk" and actor.advancer.get_buffer().size() == 1, "ordinary fallback true stops native FIFO and leaves the next command queued")
	check(not actor.advance_commands(), "ordinary fallback records the same-frame transition guard")
	actor.free()
	print("NATIVE ADVANCER TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
