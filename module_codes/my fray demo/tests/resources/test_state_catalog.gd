extends Node
## 测试状态库白名单与编号契约。四条精确匹配的拒绝日志属于预期结果。

var checks := 0
var failures := 0


func _check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _loadout() -> FighterLoadout:
	var result := load("res://resource/characters/demo_loadout.tres").duplicate() as FighterLoadout
	result.state_library = result.state_library.duplicate()
	result.state_library.states = result.state_library.states.duplicate()
	result.move_library = result.move_library.duplicate()
	result.move_library.moves = result.move_library.moves.duplicate()
	result.move_library.moves[0] = result.move_library.moves[0].duplicate()
	return result


func _ready() -> void:
	var loadout := _loadout()
	var index: Dictionary[StringName, FighterStateDefinition] = {}
	for state in loadout.state_library.states:
		index[state.state_id] = state
	var digits := RegEx.new()
	digits.compile("^[0-9]{10}$")
	_check(index.size() == 5, "five default states have unique catalog IDs")
	for state in loadout.state_library.states:
		_check(digits.search(String(state.state_id)) != null, "state ID is exactly ten decimal digits: " + String(state.state_id))
		_check(index[state.state_id] == state, "ID resolves to exact catalog definition")
	var move := loadout.move_library.moves[0]
	_check((move.state as FighterStateDefinition).state_id == &"0101000100", "default attack uses move ID plus 00")
	_check(index[(move.state as FighterStateDefinition).state_id].state_name == &"light_attack", "state identity remains separate from routing path")
	var fields: Array[StringName] = []
	for property in index[(move.state as FighterStateDefinition).state_id].get_property_list():
		fields.append(property.name)
	_check(&"category" not in fields and &"state_id" in fields and &"state_name" in fields, "state definitions contain neither category nor owner backreference")
	var definition_fields := (load("res://scripts/states/state_definition.gd") as Script).get_script_property_list().filter(func(property: Dictionary) -> bool:
		return (property.usage & PROPERTY_USAGE_STORAGE) != 0)
	var transition_fields := (load("res://scripts/transitions/transition_definition.gd") as Script).get_script_property_list().filter(func(property: Dictionary) -> bool:
		return (property.usage & PROPERTY_USAGE_STORAGE) != 0)
	_check(definition_fields.size() == 5 and transition_fields.size() == 9, "leaf and edge definitions retain exactly their own data, no stored owner property")
	var old_id := index[(move.state as FighterStateDefinition).state_id].state_id
	var moved_state := index[old_id].duplicate() as FighterStateDefinition
	moved_state.state_name = &"renamed"
	_check(moved_state.state_id == old_id and moved_state.state_name != index[old_id].state_name, "renaming or regrouping does not change stable state ID")
	var reordered := _loadout()
	reordered.state_library.states.reverse()
	var selection := reordered.resolve_selection()
	_check(selection.states.back().state_id == &"0101000100", "reordering catalog does not change ID resolution")
	var private_definition := index[old_id].duplicate() as FighterStateDefinition
	private_definition.animation_key = &"idle"
	loadout.state_library.states[4] = private_definition
	selection = loadout.resolve_selection()
	_check(selection.states.back() == private_definition and selection.states.back() != index[old_id], "move IDs resolve only through the supplied catalog, not old embedded resources")
	var shared := _loadout()
	shared.selected_move_ids.append(shared.selected_move_ids[0])
	_check(shared.resolve_selection().states.size() == 5, "repeated moves and shared execution definitions are assembled once")

	# 非库状态 ID 被拒绝，已解析基础状态不能作为部分成功结果返回。
	var invalid := _loadout()
	invalid.move_library.moves[0].state = invalid.move_library.moves[0].state.duplicate()
	(invalid.move_library.moves[0].state as FighterStateDefinition).state_id = &"0101000199"
	_check(invalid.resolve_selection().is_empty(), "unknown state ID fails the entire selection")
	invalid = _loadout()
	invalid.move_library.moves[0].state = null
	_check(invalid.resolve_selection().is_empty(), "move without an execution definition is rejected")
	invalid = _loadout()
	invalid.selected_state_names = [&"unknown"]
	_check(invalid.resolve_selection().is_empty(), "unknown basic-state path is rejected")
	invalid = _loadout()
	invalid.selected_move_ids = [&"99999999"]
	_check(invalid.resolve_selection().is_empty(), "unknown selected move is rejected before assembly")
	# Fighter 信任已验证的装配配置；不再测试它的重复停机兜底分支。
	print("STATE CATALOG TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
