extends Node
const T = preload("res://tests/input/input_test_support.gd")
var checks := 0
var failures := 0
func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS: " if value else "FAIL: ", label)
func queued(actor: Fighter, move: FighterMoveDefinition) -> bool:
	for item in actor.advancer.get_buffer():
		if item is FrayBufferedInputAdvancer.BufferedInputSequence and item.sequence_name == move.command.command_id: return true
	return false
func _run() -> void:
	FrayInput.set_physics_process(false)
	var forward := T.move(&"02010001", [&"dir_2", &"dir_3", &"dir_6", &"light_attack"])
	var back := T.move(&"02010002", [&"dir_2", &"dir_1", &"dir_4", &"heavy_attack"])
	var moves: Array[FighterMoveDefinition] = [forward, back]
	var actor := T.spawn(self, moves)
	check(actor.fighter_input.matcher != null, "all equipped sequences use the character single native matcher")
	var matcher: FraySequenceMatcher = actor.fighter_input.matcher
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_left"])
	actor.set_facing(-1)
	check(actor.fighter_input.facing_dir == 1, "facing request cannot mutate published sampling context")
	actor.publish_input_context()
	check(actor.fighter_input.matcher == matcher, "ordinary facing change retains matcher instance and partial world history")
	T.inputs(actor, [&"move_left"])
	T.inputs(actor, [&"move_left", &"light_attack"])
	check(queued(actor, forward), "world 214 started facing right completes as forward motion facing left")
	actor.fighter_input.clear_history()
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_right"])
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(actor.advancer.get_buffer().is_empty(), "world 236 is not forward-special when finishing facing left")
	actor.fighter_input.clear_history()
	T.inputs(actor, [])
	T.turn(actor, 1)
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_left"])
	T.inputs(actor, [&"move_left"])
	T.inputs(actor, [&"move_left", &"heavy_attack"])
	check(queued(actor, back), "same shared tree distinguishes second named world route")
	actor.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(actor.advancer.get_buffer().is_empty(), "focus loss clears completed buffered commands")
	actor.fighter_input._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	actor.free()

	var vertical := T.move(&"02010003", [&"dir_2", &"dir_8"])
	var vertical_moves: Array[FighterMoveDefinition] = [vertical]
	actor = T.spawn(self, vertical_moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_up"])
	check(queued(actor, vertical), "down held then up still matches a pure-direction command despite neutral vertical axis")
	actor.fighter_input.clear_history()
	T.inputs(actor, [])
	T.inputs(actor, [&"move_up", &"move_down"])
	check(queued(actor, vertical), "same-frame up/down uses explicit down-up tolerance without fabricating a new frame")
	var count := actor.advancer.get_buffer().size()
	T.inputs(actor, [&"move_up", &"move_down"])
	check(actor.advancer.get_buffer().size() == count, "held vertical overlap does not repeatedly enqueue")
	actor.free()

	var charge := T.move(&"02010004", [&"dir_4", &"dir_6", &"light_attack"])
	charge.command.min_charge_ms = 100
	var charge_moves: Array[FighterMoveDefinition] = [charge]
	actor = T.spawn(self, charge_moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_left"])
	actor.fighter_input._direction_pressed_ms = Time.get_ticks_msec() - 150
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(queued(actor, charge), "native matcher receives real direction-release charge duration")
	actor.free()
	var negative := T.move(&"02010005", [&"dir_2", &"dir_6", &"light_attack"])
	negative.command.negative_edge = true
	var negative_moves: Array[FighterMoveDefinition] = [negative]
	actor = T.spawn(self, negative_moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"light_attack"])
	T.inputs(actor, [&"light_attack", &"move_down"])
	T.inputs(actor, [&"light_attack", &"move_right"])
	T.inputs(actor, [&"move_right"])
	check(queued(actor, negative), "negative edge completes on release of the actual held attack button")
	actor.free()

	var timed := T.move(&"02010006", [&"dir_2", &"dir_6", &"light_attack"])
	var timed_moves: Array[FighterMoveDefinition] = [timed]
	actor = T.spawn(self, timed_moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	# 只调整独立测试事件来模拟间隔经过，不修改正式输入或共享资源。
	var partial: Array[FrayInputEvent] = actor.fighter_input.matcher.get_match_branch()
	partial[0].time_detected = Time.get_ticks_msec() - 500
	T.turn(actor, -1)
	T.inputs(actor, [&"move_left"])
	T.inputs(actor, [&"move_left", &"light_attack"])
	check(actor.advancer.get_buffer().is_empty(), "ordinary turn does not extend an expired partial-motion deadline")
	actor.free()

	var directional := T.move(&"01010009")
	directional.command.required_direction = 6
	var directional_moves: Array[FighterMoveDefinition] = [directional]
	actor = T.spawn(self, directional_moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(queued(actor, directional), "forward plus button accepts a direction held before the button")
	actor.fighter_input.clear_history()
	T.inputs(actor, [])
	T.turn(actor, -1)
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(actor.advancer.get_buffer().is_empty(), "direction-qualified single rejects world-right when that is backward")
	actor.fighter_input.clear_history()
	T.inputs(actor, [])
	T.inputs(actor, [&"move_left", &"light_attack"])
	check(queued(actor, directional), "direction-qualified single mirrors using the published facing snapshot")
	actor.free()
	print("DIRECTION HISTORY TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
