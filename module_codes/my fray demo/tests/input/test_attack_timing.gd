extends Node
const T = preload("res://tests/input/input_test_support.gd")
const ATTACK := &"light_attack"
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS: " if value else "FAIL: ", label)

func tick(attack: BasicAttackState, frame: int) -> void:
	while attack.elapsed_frames < frame:
		attack._physics_process_impl(1.0 / 60.0)

func _run() -> void:
	FrayInput.set_physics_process(false)
	var actor := T.spawn(self)
	var root := actor.state_machine.get_root()
	var move := actor.loadout.move_library.moves[0]
	check(not move.has_method("total_frames"), "Move no longer owns attack duration")
	var old_fields := false
	for property in move.get_property_list():
		if property.name in ["startup_frames", "active_frames", "recovery_frames"]: old_fields = true
	check(not old_fields, "Move no longer exports duplicate frame fields")
	root.goto(ATTACK)
	var attack := root.get_state(ATTACK) as BasicAttackState
	var pose := actor.hit_state_manager.get_current_state_obj()
	var typed_boxes: Array[FrayHitbox2D] = pose.get_hitboxes()
	check(typed_boxes.is_typed() and typed_boxes.size() == 3, "native get_hitboxes returns actual typed Array matching its public signature")
	var box := pose.get_node("Attackbox") as FrayHitbox2D
	var timing := box.attribute as FighterHitboxAttribute
	check(timing != null and attack.attack_attributes[2] == timing, "state resolves actual attack Attribute through selected Manager pose")
	check(attack.total_frames() == 24 and timing.total_frames() == 24, "single source Attribute retains original 10/4/10 timing")
	var hurt_timing := pose.get_node("Hurtbox").attribute as FighterHitboxAttribute
	var push_timing := pose.get_node("Pushbox").attribute as FighterHitboxAttribute
	check(attack.attack_attributes.size() == 1 and hurt_timing.total_frames() == 0 and push_timing.total_frames() == 0, "unified Attribute selects attack kind only; Hurt and Push do not extend action timing")
	check(not hurt_timing.is_active_at(10) and not push_timing.is_active_at(10), "non-attack kinds never report active attack windows")
	check(attack.get_phase() == BasicAttackState.Phase.STARTUP and pose.active_hitboxes == 3, "entry keeps Hurt/Push but attack bit is closed")
	tick(attack, 9)
	check(not box.monitoring and not attack.is_done_processing(), "last startup frame cannot hit or finish")
	tick(attack, 10)
	check(box.monitoring and pose.active_hitboxes == 7 and attack.get_phase() == BasicAttackState.Phase.ACTIVE, "active interval opens attack frame exactly at startup boundary")
	tick(attack, 13)
	check(box.monitoring and not attack.is_done_processing(), "last active frame remains enabled")
	tick(attack, 14)
	check(not box.monitoring and pose.active_hitboxes == 3 and attack.get_phase() == BasicAttackState.Phase.RECOVERY, "active-end boundary closes only attack, preserving Hurt/Push")
	tick(attack, 23)
	check(not attack.is_done_processing() and not attack.can_update_facing(), "closed attack box does not end recovery or release facing")
	tick(attack, 24)
	check(attack.is_done_processing() and attack.can_update_facing() and attack.get_phase() == BasicAttackState.Phase.DONE, "recovery end completes action and releases facing")
	root._transition_to(ATTACK, {}, attack)
	tick(attack, 10)
	root.goto(&"idle")
	check(not box.monitoring and pose.active_hitboxes == 0, "interruption immediately clears active attack without waiting for timing")
	root.goto(ATTACK)
	check(attack.elapsed_frames == 0 and pose.active_hitboxes == 3, "re-entry resets per-state progress and transient attack bits")
	var second := T.spawn(self)
	second.state_machine.get_root().goto(ATTACK)
	var second_attack := second.state_machine.get_root().get_state(ATTACK) as BasicAttackState
	tick(attack, 10)
	check(second_attack.elapsed_frames == 0 and not second._current_hit_state.get_node("Attackbox").monitoring, "shared timing Attribute does not share runtime progress or active masks")
	second.free()

	# 同一动作多个框，各自窗口，动作等待最长恢复结束。
	var extra := box.duplicate() as FrayHitbox2D
	extra.name = &"LateAttackbox"
	extra.attribute = timing.duplicate() as FighterHitboxAttribute
	(extra.attribute as FighterHitboxAttribute).startup_frames = 18
	(extra.attribute as FighterHitboxAttribute).active_frames = 2
	(extra.attribute as FighterHitboxAttribute).recovery_frames = 10
	pose.add_child(extra)
	root._transition_to(ATTACK, {}, attack)
	check(attack.total_frames() == 30 and pose.active_hitboxes == 3, "multiple frame attributes use longest full duration and reset all attack bits")
	tick(attack, 10)
	check(box.monitoring and not extra.monitoring, "first attack opens only its own bit")
	tick(attack, 18)
	check(not box.monitoring and extra.monitoring and pose.active_hitboxes == 11, "later attack opens independently after first window closes")
	tick(attack, 20)
	check(not box.monitoring and not extra.monitoring and not attack.is_done_processing(), "all windows closed still waits for final recovery")
	tick(attack, 30)
	check(attack.is_done_processing() and timing.startup_frames == 10, "longer recovery finishes without mutating original shared Attribute")
	actor.free()
	print("ATTACK TIMING TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
