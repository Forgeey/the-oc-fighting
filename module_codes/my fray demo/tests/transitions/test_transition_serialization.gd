@tool
extends Node
## 在隔离测试工程保存真实转换库并核对重载，随后由新进程运行真实资源回归。

const LIBRARY := "res://resource/state_machine/transition_library.tres"
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


## 仅测试默认配置的契约，不为运行时资源补写或回退任何条件。
func _check_library(library: FighterTransitionLibrary, label: String) -> void:
	_check(library.transitions.size() == 16, label + " keeps all sixteen default rules")
	for rule in library.transitions:
		var packed_conditions := typeof(rule.prereqs) == TYPE_PACKED_STRING_ARRAY and typeof(rule.advance_conditions) == TYPE_PACKED_STRING_ARRAY
		_check(packed_conditions, label + " uses packed condition arrays: " + String(rule.transition_id))
		if not packed_conditions:
			continue
		var expected_advance := PackedStringArray()
		var expected_prereqs := PackedStringArray()
		if not rule.command.is_empty():
			expected_prereqs.append("grounded")
			_check(not rule.auto_advance, label + " move still needs candidate: " + String(rule.transition_id))
		elif rule.transition_id == &"light_attack_to_idle":
			_check(rule.switch_mode == FrayStateMachineTransition.SwitchMode.AT_END, label + " return uses plugin completion")
		else:
			var source := String(rule.from_state).get_file()
			var target := String(rule.to_state).get_file()
			expected_advance.append("!inputed_" + source if target == "idle" else "inputed_" + target)
			_check(rule.auto_advance, label + " ordinary edge evaluates advance conditions: " + String(rule.transition_id))
		_check(rule.advance_conditions == expected_advance and rule.prereqs == expected_prereqs, label + " preserves required conditions: " + String(rule.transition_id))


## 新帧配置也必须在真正的编辑器占位／tool 模式中正确保存。
func _check_attack_attribute() -> void:
	var scene := load("res://scenes/combat/hit_states/01010001_hit_state.tscn") as PackedScene
	var pose := scene.instantiate() as FrayHitState2D
	var authored := pose.get_node("Attackbox").attribute as FighterHitboxAttribute
	_check(authored != null and authored.total_frames() == 24, "authored Attackbox uses the new timing Attribute")
	var copy := authored.duplicate() as FighterHitboxAttribute
	copy.startup_frames = 12
	copy.active_frames = 5
	copy.recovery_frames = 11
	_check(ResourceSaver.save(copy, "res://test_attack_timing_attribute.tres") == OK, "can serialize non-default attack timing Attribute in isolated project")
	var reloaded := ResourceLoader.load("res://test_attack_timing_attribute.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as FighterHitboxAttribute
	_check(reloaded.startup_frames == 12 and reloaded.active_frames == 5 and reloaded.recovery_frames == 11 and reloaded.total_frames() == 28, "attack Attribute retains all timing fields after save/reload")
	_check(not reloaded.is_active_at(11) and reloaded.is_active_at(12) and reloaded.is_active_at(16) and not reloaded.is_active_at(17), "reloaded timing keeps half-open active interval")
	_check(authored.startup_frames == 10 and authored.total_frames() == 24, "timing save does not mutate shared authored Attribute")
	pose.free()

## 在编辑器和下一运行进程保留一份真正引用组的 Move，验证静态入口与成员装配。
func _check_compound_move_reference() -> void:
	var fixture_path := "res://test_move_compound_container_reference.tres"
	if not FileAccess.file_exists(fixture_path):
		var fixture := FighterLoadout.new()
		fixture.state_library = FighterStateLibrary.new()
		fixture.move_library = FighterMoveLibrary.new()
		var compound := FighterCompoundStateDefinition.new()
		compound.state_name = &"serialization_combo"
		compound.start_state = &"B"
		fixture.state_library.compound_states = [compound]
		var source := load("res://resource/states/light_attack_state.tres") as FighterStateDefinition
		for index in 3:
			var leaf := source.duplicate() as FighterStateDefinition
			leaf.state_id = StringName("01019999%02d" % index)
			leaf.state_name = StringName(["B", "C", "D"][index])
			fixture.state_library.states.append(leaf)
			compound.states.append(leaf)
		for names in [[&"B", &"C"], [&"C", &"D"]]:
			var transition := FighterTransitionDefinition.new()
			transition.transition_id = StringName("serialized_" + String(names[0]))
			transition.from_state = names[0]
			transition.to_state = names[1]
			transition.prereqs = PackedStringArray(["gate_a"])
			compound.transitions.append(transition)
		var move := FighterMoveDefinition.new()
		move.move_id = &"01019999"
		move.state = compound
		fixture.move_library.moves = [move]
		fixture.selected_move_ids = [move.move_id]
		_check(ResourceSaver.save(fixture, fixture_path) == OK, "compound Move fixture saves in isolated project")
	var fixture := ResourceLoader.load(fixture_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as FighterLoadout
	var move := fixture.move_library.moves[0]
	_check(move.state is FighterCompoundStateDefinition, "Move.state reload keeps compound definition type")
	_check(move.state == fixture.state_library.compound_states[0], "Move and catalog share the same reloaded static group definition")
	_check((move.state as FighterCompoundStateDefinition).start_state == &"B", "compound entry survives editor and fresh runtime reload")
	var members := (move.state as FighterCompoundStateDefinition).states
	var compound := move.state as FighterCompoundStateDefinition
	_check(compound.transitions.size() == 2 and compound.transitions[0].from_state == &"B" and compound.transitions[1].to_state == &"D", "compound holds internal transition resources across editor and runtime reload")
	_check(compound.transitions[0].prereqs == PackedStringArray(["gate_a"]), "contained rule prerequisites survive editor and runtime save")
	_check(members.size() == 3 and fixture.selected_move_ids.size() == 1, "serialized compound keeps B/C/D membership without child Moves")
	# 编辑器中的非 @tool Resource 是占位实例，只验证保存的数据；运行进程再调用正式解析。
	if not Engine.is_editor_hint():
		var selection := fixture.resolve_selection()
		_check(selection.states.size() == 3 and selection.compound_states.size() == 1 and selection.moves.size() == 1, "fresh runtime resolves serialized compound into all members")
	var exported: Dictionary = move.get_property_list().filter(func(property: Dictionary) -> bool: return property.name == "state")[0]
	_check((exported.usage & PROPERTY_USAGE_STORAGE) != 0 and exported.hint_string.contains("FighterCompoundStateDefinition") and exported.hint_string.contains("FighterStateDefinition"), "Inspector state slot offers leaf or compound definition and is serializable")
	_check(ResourceSaver.save(fixture, fixture_path) == OK, "compound Move survives repeated editor/resource save")


func _run() -> void:
	print("Serialization editor_hint=", Engine.is_editor_hint())
	_check_attack_attribute()
	_check_compound_move_reference()
	var collections := preload("res://tests/resources/test_resource_collections.gd").new()
	collections.run()
	checks += collections.checks
	failures += collections.failures
	var moves := load("res://resource/state_machine/move_library.tres") as FighterMoveLibrary
	var state_library := load("res://resource/state_machine/state_library.tres") as FighterStateLibrary
	var loadout := load("res://resource/characters/demo_loadout.tres") as FighterLoadout
	_check(loadout.selected_state_names == [&"idle", &"fwalk", &"bwalk", &"crouch"] and loadout.entry_state == &"idle", "default loadout uses flat names and single entry")
	_check(ResourceSaver.save(loadout, loadout.resource_path) == OK, "flat loadout can save in isolated project")
	var saved_loadout := ResourceLoader.load(loadout.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as FighterLoadout
	_check(saved_loadout.selected_state_names == loadout.selected_state_names and saved_loadout.entry_state == &"idle", "flat loadout survives fresh reload without nested group defaults")
	for state in state_library.states:
		_check(ResourceSaver.save(state, state.resource_path) == OK, "state resource saves its stable ID")
		_check(not String(state.state_name).contains("/"), "runtime state names are direct root addresses")
		_check(not FileAccess.get_file_as_string(state.resource_path).contains("\ncategory ="), "saved state never reintroduces deleted category field")
		var reloaded_state := ResourceLoader.load(state.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as FighterStateDefinition
		_check(reloaded_state.state_id == state.state_id and reloaded_state.state_name == state.state_name and typeof(reloaded_state.state_id) == TYPE_STRING_NAME, "state resource reload preserves ID and leading zeros")
	for move in moves.moves:
		_check(typeof(move.prereqs) == TYPE_PACKED_STRING_ARRAY, "move prerequisites keep packed array type: " + String(move.move_id))
		_check(move.state is FighterStateDefinition, "single attack references a leaf definition, not a wrapper group")
		var definition := move.state as FighterStateDefinition
		_check(state_library.states.has(definition), "execution resource references an authoritative catalog leaf")
		var legacy_fields := move.get_property_list().filter(func(property: Dictionary) -> bool:
			return property.name in ["state_ids", "entry_state", "required_state_paths", "states"])
		_check(legacy_fields.is_empty(), "move no longer exports dependency arrays or duplicate entry fields")
		_check(ResourceSaver.save(move, move.resource_path) == OK, "actual move saves its execution definition reference")
		var reloaded_move := ResourceLoader.load(move.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as FighterMoveDefinition
		_check(reloaded_move.state == move.state, "move reload preserves its single execution resource reference")
		_check(not FileAccess.get_file_as_string(move.resource_path).contains("state_ids ="), "saving move does not resurrect removed state_ids")
	var library := load(LIBRARY) as FighterTransitionLibrary
	_check_library(library, "before save")
	var ids: Array[StringName] = []
	var sources: Array[StringName] = []
	var targets: Array[StringName] = []
	for rule in library.transitions:
		ids.append(rule.transition_id)
		sources.append(rule.from_state)
		targets.append(rule.to_state)
	for name in [&"advance_conditions", &"prereqs"]:
		var properties := library.transitions[0].get_property_list().filter(
			func(property: Dictionary) -> bool: return property.name == name)
		_check(properties.size() == 1 and (properties[0].usage & PROPERTY_USAGE_STORAGE) != 0, "exported field is serializable: " + String(name))
	# run_headless.py 保证只在隔离副本执行，绝不在正式工程修复/覆盖条件。
	_check(ResourceSaver.save(library, LIBRARY) == OK, "Godot can save actual default transition resource")
	var reloaded := ResourceLoader.load(LIBRARY, "", ResourceLoader.CACHE_MODE_IGNORE) as FighterTransitionLibrary
	_check_library(reloaded, "after save/reload")
	# Godot 可能额外写入空数组，检查非空字段而非字段总数。
	var file := FileAccess.get_file_as_string(LIBRARY)
	_check(file.count('advance_conditions = PackedStringArray("') == 12 and file.count('prereqs = PackedStringArray("') == 3, "serialized file retains all twelve input gates and three launch prerequisites")
	for i in reloaded.transitions.size():
		_check(reloaded.transitions[i].transition_id == ids[i] and reloaded.transitions[i].from_state == sources[i] and reloaded.transitions[i].to_state == targets[i], "save preserves identity, endpoints and ordering: " + String(ids[i]))
	print("TRANSITION SERIALIZATION TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
