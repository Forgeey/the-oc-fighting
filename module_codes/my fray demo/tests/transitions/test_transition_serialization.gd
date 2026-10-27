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
		var expected_advance := PackedStringArray()
		var expected_prereqs := PackedStringArray()
		if not rule.move_id.is_empty():
			expected_prereqs.append("grounded")
			_check(not rule.auto_advance, label + " move still needs candidate: " + String(rule.transition_id))
		elif rule.transition_id == &"action_to_neutral":
			expected_prereqs.append("active_leaf_done")
		else:
			var source := String(rule.from_state).get_file()
			var target := String(rule.to_state).get_file()
			expected_advance.append("!inputed_" + source if target == "idle" else "inputed_" + target)
			_check(rule.auto_advance, label + " ordinary edge evaluates advance conditions: " + String(rule.transition_id))
		_check(rule.advance_conditions == expected_advance and rule.prereqs == expected_prereqs, label + " preserves required conditions: " + String(rule.transition_id))


func _run() -> void:
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
	_check(file.count('advance_conditions = PackedStringArray("') == 12 and file.count('prereqs = PackedStringArray("') == 4, "serialized file retains all twelve input gates and four prerequisites")
	for i in reloaded.transitions.size():
		_check(reloaded.transitions[i].transition_id == ids[i] and reloaded.transitions[i].from_state == sources[i] and reloaded.transitions[i].to_state == targets[i], "save preserves identity, endpoints and ordering: " + String(ids[i]))
	print("TRANSITION SERIALIZATION TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
