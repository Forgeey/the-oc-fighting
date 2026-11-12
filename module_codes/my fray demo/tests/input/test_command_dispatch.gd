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
	T.inputs(actor, [&"move_right"])
	root.set_condition(&"grounded", func() -> bool: return false)
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(root.get_active_states_info().path == &"fwalk" and actor.advancer.get_buffer().is_empty(), "rejected attack can advance an eligible ordinary walking edge")
	check(not actor.advance_commands() and root.get_active_states_info().path == &"fwalk", "ordinary fallback also prevents a second transition in the same frame")
	actor._last_transition_frame = -1
	root.set_condition(&"grounded", func() -> bool: return true)
	actor.advancer.buffer_sequence(token)
	T.drive(actor)
	check(root.get_active_states_info().path == &"light_attack", "native sequence token dispatches only equipped launch rules")
	var attack := root.get_state(&"light_attack") as BasicAttackState
	check(not attack.attack_attributes.is_empty() and not actor.loadout.move_library.moves[0].has_method("total_frames"), "attack state reads timing from hitbox Attribute without Move or entry args")
	check(not actor.advance_commands(), "successful native command prevents second ordinary transition in same physics frame")
	actor.set_facing(-1)
	actor.publish_input_context()
	check(actor.fighter_input.facing_dir == 1, "unfinished attack locks requested facing")
	attack.elapsed_frames = attack.total_frames()
	actor._last_transition_frame = -1
	actor._physics_process(0.0)
	check(actor.fighter_input.facing_dir == -1, "finished attack releases facing at frame-end publication")
	check(not actor.sprite.flip_h and actor.hit_state_manager.scale.x == -1, "legal publication synchronizes visuals and hit-state mirror")
	check(actor.fighter_input.matcher != null and actor.fighter_input._routes.is_empty(), "single-key character keeps one empty matcher and no sequence paths")
	actor.advancer.buffer_sequence(token)
	actor.set_facing(1)
	actor.publish_input_context()
	check(actor.advancer.get_buffer().size() == 1, "ordinary turn does not clear already recognized command")
	actor.free()

	var normal := T.move(&"01010001")
	normal.command.resolve_delay_frames = 2
	var combo := T.move(&"03010001")
	combo.command.input_kind = FighterCommandDefinition.InputKind.COMBINATION
	combo.command.buttons = [&"light_attack", &"medium_attack"]
	var moves: Array[FighterMoveDefinition] = [normal, combo]
	actor = T.spawn(self, moves)
	T.inputs(actor, [])
	T.inputs(actor, [&"light_attack"])
	check(actor.advancer.get_buffer().is_empty(), "single key waits before ownership is resolved")
	T.inputs(actor, [&"light_attack", &"medium_attack"])
	check(actor.advancer.get_buffer().size() == 1 and actor.advancer.get_buffer()[0].sequence_name == combo.command.command_id, "same-source combination cancels not-yet-queued single")
	T.drive(actor)
	check(actor.advancer.get_buffer().is_empty(), "native execution removes accepted combination without a second candidate queue")
	actor.free()
	# 同一逻辑输入，不同来源／条件可以走不同目标；边不引用 move_id。
	actor = T.spawn(self)
	root = actor.state_machine.get_root()
	var one := FighterTransitionDefinition.new()
	one.command = &"shared_button"
	one.from_state = &"idle"
	one.to_state = &"fwalk"
	one.prereqs = PackedStringArray(["grounded"])
	one.advance_conditions = PackedStringArray(["!grounded"])
	one.auto_advance = false
	var two := one.duplicate() as FighterTransitionDefinition
	two.to_state = &"bwalk"
	two.advance_conditions = PackedStringArray(["grounded"])
	var crouch_edge := two.duplicate() as FighterTransitionDefinition
	crouch_edge.from_state = &"crouch"
	crouch_edge.to_state = &"fwalk"
	T.set_rules(actor, [one, two, crouch_edge])
	check(T.try_input(root, &"shared_button") and root.get_active_states_info().path == &"bwalk", "same command tries multiple current-state edges and enforces advance gates even with auto_advance false")
	root.goto(&"crouch")
	check(T.try_input(root, &"shared_button") and root.get_active_states_info().path == &"fwalk", "same command selects a different target from a different active source without any move_id")
	root.goto(&"idle")
	one.advance_conditions = PackedStringArray(["grounded"])
	one.priority = -1
	T.set_rules(actor, [one, two, crouch_edge])
	check(T.try_input(root, &"shared_button") and root.get_active_states_info().path == &"fwalk", "parallel matching edges use explicit priority rather than a unique command-to-move lookup")
	root.goto(&"idle")
	var original_command := actor.loadout.move_library.moves[0].command.command_id
	check(original_command == &"light_attack" and actor._selected_transitions[0].command == &"shared_button", "input identifiers and transition acceptance are independent of eight-digit move identity")
	actor.free()

	var gated := T.move(&"01010077")
	gated.prereqs = PackedStringArray(["grounded"])
	var gated_moves: Array[FighterMoveDefinition] = [gated]
	actor = T.spawn(self, gated_moves)
	root = actor.state_machine.get_root()
	root.set_condition(&"grounded", func() -> bool: return false)
	check(not T.try_input(root, gated.command.command_id), "legacy action prerequisites compile into state-entry gates rather than disappearing during command decoupling")
	check(gated.prereqs == PackedStringArray(["grounded"]), "compiling action prerequisites does not mutate shared move resources")
	actor.free()
	# context 中的 Manager 可以返回已经由状态 super-enter 选中的本状态姿态及属性。
	actor = T.spawn(self)
	root = actor.state_machine.get_root()
	root.goto(&"light_attack")
	var entered_attack := root.get_state(&"light_attack") as BasicAttackState
	var pose := entered_attack.hit_state_manager.get_current_state_obj()
	check(pose == actor._current_hit_state and pose.get_node("Attackbox").attribute is FighterHitboxAttribute, "attack state can obtain its selected hitbox Attribute through context Manager without entry move args")
	actor.free()
	print("COMMAND DISPATCH TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
