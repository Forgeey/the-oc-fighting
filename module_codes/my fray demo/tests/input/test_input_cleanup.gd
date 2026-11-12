extends Node
## 清理只丢弃运行历史；配置时编译，禁用／失焦／离场不分配新 Matcher。
const T = preload("res://tests/input/input_test_support.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS: " if value else "FAIL: ", label)

func event(name: StringName) -> FrayInputEvent:
	var result := FrayInputEvent.new()
	result.input = name
	result._is_pressed = true
	result._is_distinct = true
	result.physics_frame = Engine.get_physics_frames()
	result.time_detected = Time.get_ticks_msec()
	result.time_pressed = result.time_detected
	return result

func _run() -> void:
	FrayInput.set_physics_process(false)
	# 公开插件接口只调用已有 _reset；初始化同一对象也须完整丢弃旧节点／已命中标记。
	var native := FraySequenceMatcher.new()
	var tree := FraySequenceTree.new()
	tree.add(&"prefix", FraySequenceBranch.builder().then(&"test_a").build())
	tree.add(&"long", FraySequenceBranch.builder().then(&"test_a").then(&"test_b").build())
	native.initialize(tree)
	var matched: Array[StringName] = []
	native.match_found.connect(func(name: StringName) -> void: matched.append(name))
	native.read(event(&"test_a"))
	check(matched == [&"prefix"] and native.get_match_branch().size() == 1, "native prefix remains in-progress before reset")
	var compiled := native._root
	var queue := native._input_queue
	native.clear_history()
	check(native._root == compiled and native._input_queue == queue, "public reset preserves compiled tree and queue object")
	check(native.get_match_branch().is_empty() and native._input_queue.empty() and native._current_frame == null and native._last_matched_node == null, "reset discards branch, queue, frame and last-match marker")
	native.read(event(&"test_b"))
	check(matched == [&"prefix"], "old prefix cannot complete after reset")
	native.clear_history()
	native.read(event(&"test_a"))
	native.read(event(&"test_b"))
	check(matched == [&"prefix", &"prefix", &"long"], "same prefix can match again after reset without reconnecting signal")
	native.clear_history()
	native.read(event(&"test_a"))
	var next_tree := FraySequenceTree.new()
	next_tree.add(&"new", FraySequenceBranch.builder().then(&"test_c").build())
	native.initialize(next_tree)
	check(native._root != compiled and native.get_match_branch().is_empty(), "reconfigure rebuilds tree but clears obsolete partial match")
	native.read(event(&"test_b"))
	native.read(event(&"test_c"))
	check(matched.back() == &"new" and native.match_found.get_connections().size() == 1, "reconfigured matcher retains exactly one signal connection")

	var motion := T.move(&"02010901", [&"dir_2", &"dir_6", &"light_attack"])
	var actor := T.spawn(self, [motion])
	var input := actor.fighter_input
	var matcher := input.matcher
	var root := matcher._root
	var sequence_tree := input._sequence_tree
	check(not input.has_signal("command_buffered") and not input.has_method("milliseconds_to_frames") and not input.has_method("get_world_direction") and not input.has_method("get_horizontal_axis"), "unused signal and forwarding/observation wrappers are removed")
	check(not FrayInputMap.has_input(&"game_world_3"), "unused diagonal composite registration is removed")
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	check(not matcher.get_match_branch().is_empty(), "real direction prefix reaches character matcher")
	actor.advancer.buffer_sequence(&"old_command")
	input.clear_history()
	check(input.matcher == matcher and matcher._root == root and input._sequence_tree == sequence_tree, "character clear preserves matcher identity and compiled tree")
	check(actor.advancer.get_buffer().is_empty() and input._pending_singles.is_empty() and input._event_sources.is_empty() and input._claimed_ids.is_empty(), "clear removes pending singles, source ownership and buffered commands")
	T.inputs(actor, [])
	T.inputs(actor, [&"move_right"])
	T.inputs(actor, [&"move_right", &"light_attack"])
	check(actor.advancer.get_buffer().is_empty(), "cleared direction prefix cannot combine with new suffix")
	input.clear_history()
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	actor.controller.disabled = true
	for index in 4:
		input.sample()
	check(input.matcher == matcher and matcher._root == root and matcher._input_queue.empty(), "repeated disabled samples clear history without rebuilding matcher")
	check(input.get_movement_intent() == &"idle" and input._horizontal_axis == 0.0, "disabled controller still clears movement")
	actor.controller.disabled = false
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	input._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	input.sample()
	check(input.matcher == matcher and matcher._root == root and matcher.get_match_branch().is_empty(), "focus loss clears history without allocation")
	input._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	actor.controller.device = 1
	input.publish_context(-1)
	check(FighterInputBindings.get_device_input(0) == null and FighterInputBindings.get_device_input(1) == input, "device switch rebinds ownership and removes old device")
	check(input.matcher == matcher and matcher._root == root and matcher.get_match_branch().is_empty(), "device switch resets history but keeps compiled matcher")
	for index in 4:
		input.sample()
	check(input.matcher == matcher and matcher._root == root and input._horizontal_axis == 0.0, "disconnected device samples clear without rebuilding or preserving movement")
	actor.controller.device = 0
	input.publish_context(1)
	T.pause(actor)
	T.inputs(actor, [])
	T.inputs(actor, [&"move_down"])
	var other := T.spawn(self)
	input.sample()
	check(FighterInputBindings.get_device_input(0) == other.fighter_input and matcher.get_match_branch().is_empty(), "losing device ownership clears old input history")
	check(input.matcher == matcher and matcher._root == root, "ownership changes do not allocate a matcher")
	other.free()
	FighterInputBindings.bind_device(0, input)
	var replacement := T.move(&"02010902", [&"dir_4", &"heavy_attack"])
	input.configure(actor.controller, [replacement, replacement], actor.advancer)
	T.pause(actor)
	check(input._commands.size() == 1 and input._commands[0] == replacement.command, "local configure-only ID set deduplicates commands")
	check(input.matcher == matcher and matcher._root != root and matcher.match_found.get_connections().size() == 1, "only configure recompiles tree, without new matcher or duplicate callback")
	root = matcher._root
	T.inputs(actor, [])
	T.inputs(actor, [&"move_left"])
	T.inputs(actor, [&"move_left", &"heavy_attack"])
	check(actor.advancer.get_buffer().size() == 1 and actor.advancer.get_buffer()[0].sequence_name == replacement.command.command_id, "reconfigured sequence is recognized through existing matcher")
	actor.free()
	check(FighterInputBindings.get_device_input(0) == null and matcher._root == root and matcher._input_queue.empty(), "exit unbinds and clears existing matcher instead of constructing a discarded replacement")
	print("INPUT CLEANUP TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
