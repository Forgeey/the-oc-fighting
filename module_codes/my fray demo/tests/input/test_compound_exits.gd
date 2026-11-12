extends Node
## 正式 Loadout/Builder/Fighter 的多出口回归；不用空 done 或组子类。
const T = preload("res://tests/input/input_test_support.gd")
var checks := 0
var failures := 0
var cancel_open := true

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS: " if value else "FAIL: ", label)

func rule(id: StringName, source: StringName,
		target: StringName, command: StringName = &"") -> FighterTransitionDefinition:
	var result := FighterTransitionDefinition.new()
	result.transition_id = id
	result.from_state = source
	result.to_state = target
	result.command = command
	return result

func spawn_combo() -> Fighter:
	var actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	actor.loadout = actor.loadout.duplicate()
	actor.loadout.state_library = actor.loadout.state_library.duplicate()
	actor.loadout.state_library.states = actor.loadout.state_library.states.duplicate()
	actor.loadout.state_library.compound_states = []
	var group := FighterCompoundStateDefinition.new()
	group.state_name = &"combo1"
	group.start_state = &"B"
	actor.loadout.state_library.compound_states.append(group)
	var unused := FighterCompoundStateDefinition.new()
	unused.state_name = &"unequipped_group"
	unused.start_state = &"unused"
	actor.loadout.state_library.compound_states.append(unused)
	actor.loadout.move_library = actor.loadout.move_library.duplicate()
	actor.loadout.move_library.moves = actor.loadout.move_library.moves.duplicate()
	actor.loadout.selected_move_ids = actor.loadout.selected_move_ids.duplicate()
	var attack := load("res://resource/states/light_attack_state.tres") as FighterStateDefinition
	var buttons: Array[StringName] = [&"medium_attack", &"heavy_attack", &"guard"]
	for index in 3:
		var state := attack.duplicate() as FighterStateDefinition
		state.state_id = StringName("0101000%d00" % (index + 2))
		state.state_name = StringName(["B", "C", "D"][index])
		group.states.append(state)
		actor.loadout.state_library.states.append(state)
		var move := T.move(StringName("0101000%d" % (index + 2)))
		move.state = group if index == 0 else state
		move.command.command_id = StringName("follow_" + String(state.state_name))
		move.command.buttons = [buttons[index]]
		move.prereqs = PackedStringArray(["grounded"])
		actor.loadout.move_library.moves.append(move)
		actor.loadout.selected_move_ids.append(move.move_id)
	actor.loadout.transition_library = actor.loadout.transition_library.duplicate()
	actor.loadout.transition_library.transitions = actor.loadout.transition_library.transitions.duplicate()
	var enter := rule(&"enter_combo", &"light_attack", &"combo1", &"follow_B")
	enter.switch_mode = FrayStateMachineTransition.SwitchMode.IMMEDIATE
	actor.loadout.transition_library.transitions.append(enter)
	for edge in [[&"B", &"C"], [&"C", &"D"]]:
		var next := rule(StringName("follow_" + String(edge[1])), edge[0], edge[1], StringName("follow_" + String(edge[1])))
		next.switch_mode = FrayStateMachineTransition.SwitchMode.IMMEDIATE
		next.advance_conditions = PackedStringArray(["grounded"])
		group.transitions.append(next)
	var leave := rule(&"combo_to_idle", &"combo1", &"idle")
	actor.loadout.transition_library.transitions.append(leave)
	var omitted := rule(&"unused_edge", &"unused", &"unused")
	unused.transitions.append(omitted)
	add_child(actor)
	T.pause(actor)
	actor.state_machine.get_root().set_condition(&"grounded", func() -> bool: return true)
	var combo := actor.state_machine.get_root().get_state(&"combo1") as FrayCompoundState
	combo.set_condition(&"grounded", func() -> bool: return cancel_open)
	return actor

func send(actor: Fighter, command: StringName) -> void:
	actor.advancer.buffer_sequence(command)
	T.drive(actor)

func _run() -> void:
	FrayInput.set_physics_process(false)
	var actor := spawn_combo()
	var root := actor.state_machine.get_root()
	var combo := root.get_state(&"combo1") as FrayCompoundState
	check(root.get_script() == combo.get_script(), "root and combo are both unwrapped native compounds")
	check(combo.start_state == &"B" and combo.end_state.is_empty(), "explicit start B, no end_state")
	check(combo._states.size() == 3 and not combo.has_state(&"done"), "only B/C/D; no artificial finish state")
	check(not root.has_state(&"unequipped_group"), "unselected group and its rule are not assembled")
	check(not root.has_state(&"B") and root.has_state(&"combo1/B"), "explicit ownership puts B inside combo1")
	check(combo.has_transition(&"B", &"C") and not root.has_transition(&"B", &"C"), "internal edges belong to combo owner")
	check(root.has_transition(&"combo1", &"idle"), "parent owns explicit group exit")
	check(actor._selected_transitions.size() == 20, "four selected combo edges plus sixteen existing edges")
	check("grounded" not in actor.loadout.transition_library.transitions[16].prereqs, "entry Move prereqs do not mutate shared rule")
	check("grounded" in actor._selected_transitions[16].prereqs, "group entry receives compound Move prereqs")
	check(combo._condition_func_by_name.has(&"grounded"), "internal rule conditions are explicitly bound locally")
	check(not root._condition_func_by_name.has(&"active_leaf_done") and not combo._condition_func_by_name.has(&"active_leaf_done"), "no game-side completion condition or inheritance is required")

	var group_move := actor.loadout.move_library.moves[1]
	check(group_move.state is FighterCompoundStateDefinition, "multi-stage move directly references a static compound definition")
	var only_group := actor.loadout.duplicate() as FighterLoadout
	only_group.selected_move_ids = [group_move.move_id]
	var only_selection := only_group.resolve_selection()
	check(only_selection.moves.size() == 1, "selecting group execution does not auto-equip child moves or their commands")
	check(only_selection.states.size() == 7 and only_selection.compound_states.size() == 1, "one group reference collects all three members plus four basic leaves")
	var only_root := FighterSMBuilder.new().build(actor, only_group, only_selection)
	var only_combo := only_root.get_state(&"combo1") as FrayCompoundState
	check(only_combo._states.size() == 3 and only_combo.has_state(&"D"), "D is installed without a separate Move dependency list or equipped D move")
	check(not only_root.has_state(&"light_attack"), "referencing continuation group does not silently install root starter A")
	check(only_combo.start_state == &"B" and only_combo.end_state.is_empty(), "group owns its default entry, not Move array order")
	var from_leaf := actor.loadout.duplicate() as FighterLoadout
	from_leaf.selected_move_ids = [actor.loadout.move_library.moves[2].move_id]
	var leaf_selection := from_leaf.resolve_selection()
	check(leaf_selection.compound_states.is_empty() and leaf_selection.states.size() == 5, "direct leaf selection installs only root leaf, never guesses a group")
	var leaf_root := FighterSMBuilder.new().build(actor, from_leaf, leaf_selection)
	check(leaf_root.has_state(&"C") and not leaf_root.has_state(&"combo1"), "referenced leaf is root content; container membership is never inferred backwards")
	var shared_loadout := only_group.duplicate() as FighterLoadout
	shared_loadout.selected_state_names = shared_loadout.selected_state_names.duplicate()
	shared_loadout.selected_state_names.append_array([&"B", &"C"])
	var shared_selection := shared_loadout.resolve_selection()
	var shared_root := FighterSMBuilder.new().build(actor, shared_loadout, shared_selection)
	var shared_leaf := shared_root.get_state(&"B") as FighterState
	var contained_leaf := shared_root.get_state(&"combo1/B") as FighterState
	check(shared_leaf != contained_leaf and shared_leaf.state_definition == contained_leaf.state_definition, "same static leaf can have independent root and group instances without a parent property")
	check(shared_leaf.get_parent() == shared_root and contained_leaf.get_parent() == shared_root.get_state(&"combo1"), "runtime parents come only from owning containers")
	check(not shared_root.has_transition(&"B", &"C") and (shared_root.get_state(&"combo1") as FrayCompoundState).has_transition(&"B", &"C"), "group rules cannot leak into root even when root has matching source names")
	check(shared_selection.root_states.size() == 6 and shared_selection.states.size() == 7, "hit selection deduplicates shared static leaf while root selection keeps distinct placement")
	var second_definition := (group_move.state as FighterCompoundStateDefinition).duplicate() as FighterCompoundStateDefinition
	second_definition.state_name = &"combo2"
	var second_move := group_move.duplicate() as FighterMoveDefinition
	second_move.move_id = &"01018888"
	second_move.state = second_definition
	var two_groups := only_group.duplicate() as FighterLoadout
	two_groups.state_library = only_group.state_library.duplicate()
	two_groups.state_library.compound_states = only_group.state_library.compound_states.duplicate()
	two_groups.state_library.compound_states.append(second_definition)
	two_groups.move_library = only_group.move_library.duplicate()
	two_groups.move_library.moves = only_group.move_library.moves.duplicate()
	two_groups.move_library.moves.append(second_move)
	two_groups.selected_move_ids = [group_move.move_id, second_move.move_id]
	var two_selection := two_groups.resolve_selection()
	var two_root := FighterSMBuilder.new().build(actor, two_groups, two_selection)
	var first_group := two_root.get_state(&"combo1") as FrayCompoundState
	var second_group := two_root.get_state(&"combo2") as FrayCompoundState
	check(first_group.get_state(&"B") != second_group.get_state(&"B") and (first_group.get_state(&"B") as FighterState).state_definition == (second_group.get_state(&"B") as FighterState).state_definition, "two containers reuse one static definition with separate runtime children")
	check(first_group.has_transition(&"B", &"C") and second_group.has_transition(&"B", &"C"), "same immutable internal transition resource can be registered in two explicit owners")
	first_group.set_condition(&"grounded", func() -> bool: return false)
	second_group.set_condition(&"grounded", func() -> bool: return true)
	check(not first_group.is_condition_true(&"grounded") and second_group.is_condition_true(&"grounded"), "reused internal rules still query per-owner conditions independently")
	check(two_selection.states.size() == 7 and two_selection.compound_states.size() == 2, "static hit dependencies deduplicate across multiple explicit containers")
	var private_group_move := group_move.duplicate() as FighterMoveDefinition
	private_group_move.state = group_move.state.duplicate()
	(private_group_move.state as FighterCompoundStateDefinition).start_state = &"C"
	only_group.move_library = FighterMoveLibrary.new()
	only_group.move_library.moves = [private_group_move]
	check(only_group.resolve_selection().compound_states[0].start_state == &"B", "group reference resolves authoritative library definition by name, not embedded override")
	var member_override := (group_move.state as FighterCompoundStateDefinition).duplicate() as FighterCompoundStateDefinition
	member_override.states = member_override.states.duplicate()
	member_override.states[0] = member_override.states[0].duplicate() as FighterStateDefinition
	member_override.states[0].animation_key = &"ignored_embedded_override"
	var catalog_selection := actor.loadout.duplicate() as FighterLoadout
	catalog_selection.state_library = actor.loadout.state_library.duplicate()
	catalog_selection.state_library.compound_states = actor.loadout.state_library.compound_states.duplicate()
	catalog_selection.state_library.compound_states[0] = member_override
	catalog_selection.selected_move_ids = [group_move.move_id]
	var catalog_root := FighterSMBuilder.new().build(actor, catalog_selection, catalog_selection.resolve_selection())
	var actual_member := catalog_root.get_state(&"combo1/B") as FighterState
	check(actual_member.state_definition != member_override.states[0] and actual_member.state_definition.animation_key == &"light_attack", "container child reference resolves current authoritative leaf by stable ID")
	check(member_override.states[0].animation_key == &"ignored_embedded_override", "canonical member assembly does not mutate authored reference resources")
	var repeated := actor.loadout.duplicate() as FighterLoadout
	repeated.selected_move_ids = [group_move.move_id, group_move.move_id]
	check(repeated.resolve_selection().compound_states.size() == 1 and repeated.resolve_selection().states.size() == 7, "shared group references install each group and leaf once")

	# A alone, AB, ABC, ABCD: the same actual attack completion gates every exit.
	for stop in 4:
		root.goto(&"light_attack")
		if stop >= 1:
			send(actor, &"follow_B")
		if stop >= 2:
			send(actor, &"follow_C")
		if stop >= 3:
			send(actor, &"follow_D")
		var expected: StringName = [&"light_attack", &"combo1/B", &"combo1/C", &"combo1/D"][stop]
		check(root.get_active_states_info().path == expected, "selected prefix reaches " + String(expected))
		var leaf := actor.get_active_leaf() as BasicAttackState
		check(leaf.elapsed_frames == 0 and leaf.get_parent() == (root if stop == 0 else combo), "actual attack enter resets the right independent leaf")
		if stop > 0:
			check(not combo.is_done_processing(), "empty end_state compound waits for unfinished active child recursively")
		check(not root.is_done_processing() and not T.ordinary(actor), "unfinished prefix cannot exit " + String(expected))
		actor.set_facing(-1)
		actor.publish_input_context()
		check(actor.fighter_input.facing_dir == 1, "unfinished actual leaf holds facing, not group completion")
		leaf.elapsed_frames = leaf.total_frames() - 1
		check(not T.ordinary(actor), "last recovery frame still blocks natural exit")
		leaf.elapsed_frames = leaf.total_frames()
		check(root.is_done_processing(), "root completion recursively reads finished actual leaf")
		# Completion alone does not change the state; advance must take the configured edge.
		check(root.get_active_states_info().path == expected, "completion alone does not pop to parent")
		check(T.ordinary(actor) and root.get_current_state_name() == &"idle", "explicit edge returns completed prefix to idle")
		actor.publish_input_context()
		check(actor.fighter_input.facing_dir == -1, "idle permits deferred facing update")
		actor.set_facing(1)
		actor.publish_input_context()

	root.goto(&"light_attack")
	send(actor, &"follow_B")
	cancel_open = false
	send(actor, &"follow_C")
	check(combo.get_current_state_name() == &"B", "local advance condition rejects followup without inheriting root true")
	check(not T.ordinary(actor), "rejected followup cannot cause premature natural exit")
	cancel_open = true
	send(actor, &"follow_C")
	check(combo.get_current_state_name() == &"C", "IMMEDIATE authorized followup can cancel unfinished B")
	root.goto(&"light_attack")
	send(actor, &"follow_B")
	var b := actor.get_active_leaf() as BasicAttackState
	b.elapsed_frames = b.total_frames()
	send(actor, &"follow_C")
	check(root.get_active_states_info().path == &"combo1/C", "child followup wins when parent natural exit is also eligible")
	root.goto(&"idle")
	root.goto(&"combo1")
	check(combo.get_current_state_name() == &"B" and actor.get_active_leaf().elapsed_frames == 0, "interrupted nonpersistent combo reenters B fresh")
	# 保存重载真实配置：新增组数组、状态 owner、转换 owner 和父出口条件均需保留。
	var save_path := "user://fray_test_compound_exit_loadout.tres"
	check(ResourceSaver.save(actor.loadout, save_path) == OK, "grouped loadout saves successfully")
	var saved := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as FighterLoadout
	check(saved.move_library.moves[1].state == saved.state_library.compound_states[0], "Move.state and compound catalog keep the same static resource after save/reload")
	check(saved.state_library.compound_states.size() == 2, "compound definition array survives resource reload")
	var selection := saved.resolve_selection()
	check(selection.compound_states.size() == 1 and selection.compound_states[0].start_state == &"B", "reload resolves only equipped group with explicit start B")
	var rebuilt := FighterSMBuilder.new().build(actor, saved, selection)
	var saved_combo := rebuilt.get_state(&"combo1") as FrayCompoundState
	check(saved_combo.has_state(&"B") and saved_combo.has_state(&"C") and saved_combo.has_state(&"D"), "compound member references survive resource reload")
	check(saved_combo.has_transition(&"B", &"C") and rebuilt.has_transition(&"combo1", &"idle"), "transition owner survives resource reload")
	check(rebuilt.get_next_transitions(&"combo1")[0].transition.prereqs.is_empty() and rebuilt.get_next_transitions(&"combo1")[0].transition.switch_mode == FrayStateMachineTransition.SwitchMode.AT_END, "unconditional parent AT_END survives resource reload")
	check(saved_combo.end_state.is_empty(), "resource reload does not invent a single end_state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	root.remove_transition(&"combo1", &"idle")
	var final_leaf := actor.get_active_leaf() as BasicAttackState
	final_leaf.elapsed_frames = final_leaf.total_frames()
	check(not T.ordinary(actor) and root.get_active_states_info().path == &"combo1/B", "finished group with no exit edge remains active, never implicitly pops")
	# 一个复合 Move、一条已注册命令即可连续驱动多段；不装备 C/D Move。
	var repeated_input_loadout := actor.loadout.duplicate() as FighterLoadout
	repeated_input_loadout.selected_move_ids = [group_move.move_id]
	repeated_input_loadout.entry_state = &"combo1"
	repeated_input_loadout.transition_library = actor.loadout.transition_library.duplicate()
	repeated_input_loadout.transition_library.transitions = []
	repeated_input_loadout.transition_library.transitions = actor.loadout.transition_library.transitions.duplicate()
	repeated_input_loadout.state_library = actor.loadout.state_library.duplicate()
	repeated_input_loadout.state_library.compound_states = actor.loadout.state_library.compound_states.duplicate()
	var repeated_definition := (group_move.state as FighterCompoundStateDefinition).duplicate() as FighterCompoundStateDefinition
	repeated_definition.transitions = []
	for original in (group_move.state as FighterCompoundStateDefinition).transitions:
		var copied := original.duplicate() as FighterTransitionDefinition
		copied.command = group_move.command.command_id
		repeated_definition.transitions.append(copied)
	repeated_input_loadout.state_library.compound_states[0] = repeated_definition
	actor.free()
	var repeated_actor: Fighter = load("res://scenes/Fighter.tscn").instantiate()
	repeated_actor.loadout = repeated_input_loadout
	add_child(repeated_actor)
	T.pause(repeated_actor)
	var repeated_root := repeated_actor.state_machine.get_root()
	var repeated_combo := repeated_root.get_state(&"combo1") as FrayCompoundState
	repeated_combo.set_condition(&"grounded", func() -> bool: return true)
	check(repeated_root.get_active_states_info().path == &"combo1/B", "one compound Move starts at B without child Moves")
	check(repeated_actor.fighter_input._commands.size() == 1, "single selected compound registers exactly one Command")
	check(repeated_combo != combo and repeated_combo.get_state(&"B") != b, "another actor gets independent native group and attack instances")
	for expected in [&"combo1/C", &"combo1/D"]:
		T.inputs(repeated_actor, [])
		T.inputs(repeated_actor, [&"medium_attack"])
		T.drive(repeated_actor)
		check(repeated_root.get_active_states_info().path == expected, "same actual input Command advances to " + String(expected))
	var repeated_leaf := repeated_actor.get_active_leaf() as BasicAttackState
	repeated_leaf.elapsed_frames = repeated_leaf.total_frames()
	check(T.ordinary(repeated_actor) and repeated_root.get_current_state_name() == &"idle", "single compound Move completes through explicit parent exit")
	T.inputs(repeated_actor, [])
	repeated_actor.free()
	print("COMPOUND EXIT TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
