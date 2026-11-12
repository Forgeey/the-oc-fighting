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

func queued(actor: Fighter, command: FighterCommandDefinition) -> bool:
	for item in actor.advancer.get_buffer():
		if item.sequence_name == command.command_id: return true
	return false

func begin(actor: Fighter) -> void:
	actor.fighter_input.clear_history()
	T.inputs(actor, [])

func _run() -> void:
	FrayInput.set_physics_process(false)
	var motion := T.move(&"02010101", [&"dir_2", &"dir_3", &"dir_6", &"light_attack"])
	motion.command.max_step_delay_ms = 160
	var vertical := T.move(&"02010102", [&"dir_2", &"dir_8"])
	vertical.command.max_step_delay_ms = 350
	var charge := T.move(&"02010103", [&"dir_4", &"dir_6", &"heavy_attack"])
	charge.command.min_charge_ms = 100
	var reverse := T.move(&"02010104", [&"dir_2", &"dir_1", &"dir_4", &"medium_attack"])
	var moves: Array[FighterMoveDefinition] = [motion, vertical, charge, reverse]
	var actor := T.spawn(self, moves)
	var input := actor.fighter_input
	var matcher := input.matcher
	check(matcher != null and input._sequence_tree.get_sequence_names().size() == 7, "one tree contains motions, mirrored paths, charge and both-facing vertical command without duplicate endpoint")
	check(not input.has_method("_reset_matchers") and not input.get("_groups") is Array, "no per-command matcher groups remain")
	check(not motion.command.has_method("get_world_steps") and not motion.command.has_method("get_sequence_domain") and not motion.command.has_method("create_world_branch"), "three former compiler functions replaced by create_branch only")
	var branch := motion.command.create_branch(-1)
	var names: Array[StringName] = []
	for requirement in branch.input_requirements: names.append(requirement.input)
	check(names == [&"world_2", &"world_1", &"world_4", &"light_attack"], "single compiler creates left-facing world path and keeps button unchanged")
	check(branch.input_requirements[1].max_delay == 160, "branch retains per-command timing without matcher domains")

	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_up"])
	check(queued(actor, vertical.command), "overlapping down-up completes in the same matcher as circular motions")
	check(input._direction == 8, "unified recognition stream uses last-pressed vertical direction rather than losing up to a zero axis")
	begin(actor)
	T.inputs(actor, [&"move_up", &"move_down"])
	check(queued(actor, vertical.command), "same-frame vertical tolerance is consistently down then up, not sorted per command")

	begin(actor)
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_right"])
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(queued(actor, motion.command) and not queued(actor, vertical.command), "ordinary circular input is not polluted by a second vertical-only stream")

	begin(actor)
	T.inputs(actor, [&"move_down", &"move_left"])
	var partial := input.matcher.get_match_branch()
	check(partial.is_empty(), "a same-frame diagonal is one world_1 step, not a fabricated world_2 then world_1 prefix")

	begin(actor)
	T.inputs(actor, [&"move_left"])
	input._direction_pressed_ms = Time.get_ticks_msec() - 150
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"heavy_attack"])
	check(queued(actor, charge.command), "charge-release branch shares the same matcher as ordinary and vertical commands")

	begin(actor)
	matcher = input.matcher
	T.inputs(actor, [&"move_down"])
	T.inputs(actor, [&"move_down", &"move_left"])
	T.turn(actor, -1)
	T.inputs(actor, [&"move_left"])
	T.inputs(actor, [&"move_left", &"light_attack"])
	check(queued(actor, motion.command) and input.matcher == matcher, "world history survives side change without rebuilding the only matcher")
	actor.free()

	# 同一路径不同时间要求：一个原生叶子宽包络，命中后用原生 is_match 复核。
	var fast := T.move(&"02010201", [&"dir_2", &"dir_6", &"light_attack"])
	fast.command.max_step_delay_ms = 40
	var slow := T.move(&"02010202", [&"dir_2", &"dir_6", &"light_attack"])
	slow.command.max_step_delay_ms = 250
	var timed: Array[FighterMoveDefinition] = [fast, slow]
	actor = T.spawn(self, timed)
	check(actor.fighter_input._sequence_tree.get_sequence_names().size() == 2, "identical timed world paths register one endpoint per mirror, not another matcher or conflicting sequence leaf")
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	actor.fighter_input.matcher.get_match_branch()[0].time_detected = Time.get_ticks_msec() - 120
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(not queued(actor, fast.command) and queued(actor, slow.command), "exact command delay is rechecked: slow route succeeds without admitting the strict command")
	actor.free()

	# 同路普通终结与 negative edge 不创建第二 Matcher。
	var press := T.move(&"02010301", [&"dir_2", &"dir_6", &"light_attack"])
	var negative := T.move(&"02010302", [&"dir_2", &"dir_6", &"light_attack"])
	negative.command.negative_edge = true
	var edges: Array[FighterMoveDefinition] = [press, negative]
	actor = T.spawn(self, edges)
	T.inputs(actor, [])
	T.inputs(actor, [&"light_attack"])
	T.inputs(actor, [&"light_attack", &"move_down"])
	T.inputs(actor, [&"light_attack", &"move_right"])
	T.inputs(actor, [&"move_right"])
	check(not queued(actor, press.command) and queued(actor, negative.command), "shared negative-edge envelope does not make press-only command accept release")
	actor.free()

	var long_charge := T.move(&"02010401", [&"dir_4", &"dir_6", &"heavy_attack"])
	long_charge.command.min_charge_ms = 300
	var short_charge := T.move(&"02010402", [&"dir_4", &"dir_6", &"heavy_attack"])
	short_charge.command.min_charge_ms = 100
	var charges: Array[FighterMoveDefinition] = [long_charge, short_charge]
	actor = T.spawn(self, charges)
	check(actor.fighter_input._sequence_tree.get_sequence_names().size() == 2, "different charge durations share a single typed press/release route per mirror")
	T.inputs(actor, [])
	T.inputs(actor, [&"move_left"])
	actor.fighter_input._direction_pressed_ms = Time.get_ticks_msec() - 150
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"heavy_attack"])
	check(not queued(actor, long_charge.command) and queued(actor, short_charge.command), "same charge endpoint still enforces each command's minimum hold instead of admitting the long-charge command")
	actor.free()

	var up_down := T.move(&"02010501", [&"dir_8", &"dir_2"])
	var down_up := T.move(&"02010502", [&"dir_2", &"dir_8"])
	var opposite: Array[FighterMoveDefinition] = [up_down, down_up]
	actor = T.spawn(self, opposite)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_up"])
	T.inputs(actor, [&"move_up", &"move_down"])
	check(queued(actor, up_down.command) and not queued(actor, down_up.command), "separate sampled up-then-down steps retain their real order when both opposite commands share one matcher")
	begin(actor)
	T.inputs(actor, [&"move_down", &"move_up"])
	check(queued(actor, down_up.command) and not queued(actor, up_down.command), "truly simultaneous opposites follow one shared down-up ordering rather than per-command reordering")
	actor.free()
	print("SINGLE MATCHER TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
