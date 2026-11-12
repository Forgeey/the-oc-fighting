@tool
extends RefCounted
## 验证全部自定义 Resource 的集合默认值，以及每种集合字段的编辑器保存／重载。
## 仅由 run_headless.py 复制到隔离工程后调用，不写正式工程资源。

var checks := 0
var failures := 0
var collection_fields := 0


func _check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _scan_defaults(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):
		_scan_defaults(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if not file.ends_with(".gd"):
			continue
		var script := load(directory.path_join(file)) as Script
		if script.get_instance_base_type() != "Resource":
			continue
		for property in script.get_script_property_list():
			if (property.usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var type: int = property.type
			if type != TYPE_ARRAY and type != TYPE_DICTIONARY and not (type >= TYPE_PACKED_BYTE_ARRAY and type <= TYPE_PACKED_VECTOR4_ARRAY):
				continue
			collection_fields += 1
			var default_value: Variant = script.get_property_default_value(property.name)
			_check(typeof(default_value) == type, "%s.%s default matches exported collection type" % [script.get_global_name(), property.name])


## 比较集合类型参数、元素类型及嵌套 Resource 的导出字段，而非只比较元素数量。
func _snapshot(value: Variant) -> Variant:
	var result := {"type": typeof(value)}
	if value is Resource:
		var script := value.get_script() as Script
		result["script"] = script.resource_path if script != null else value.get_class()
		var fields := {}
		if script != null:
			for property in script.get_script_property_list():
				if (property.usage & PROPERTY_USAGE_STORAGE) != 0:
					fields[property.name] = _snapshot(value.get(property.name))
		result["fields"] = fields
	elif value is Dictionary:
		result["key_type"] = value.get_typed_key_builtin()
		result["value_type"] = value.get_typed_value_builtin()
		var entries := {}
		for key in value:
			entries["%d:%s" % [typeof(key), str(key)]] = _snapshot(value[key])
		result["entries"] = entries
	elif value is Array or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY):
		if value is Array:
			result["element_type"] = value.get_typed_builtin()
			result["element_class"] = value.get_typed_class_name()
			var element_script: Script = value.get_typed_script()
			result["element_script"] = element_script.resource_path if element_script != null else ""
		var items := []
		for item in value:
			items.append(_snapshot(item))
		result["items"] = items
	else:
		result["value"] = value
	return result


func _roundtrip(script_path: String, fields: String, names: Array, element_script: String = "", fixture_suffix: String = "") -> void:
	var path := "res://test_collection_fixture_%s.tres" % (script_path.get_file().get_basename() + fixture_suffix)
	if not FileAccess.file_exists(path):
		var text := '[gd_resource type="Resource" format=3]\n\n'
		text += '[ext_resource type="Script" path="%s" id="1"]\n\n' % script_path
		if not element_script.is_empty():
			text += '[ext_resource type="Script" path="%s" id="2"]\n\n' % element_script
			text += '[sub_resource type="Resource" id="Item"]\nscript = ExtResource("2")\n\n'
		text += '[resource]\nscript = ExtResource("1")\n' + fields + "\n"
		var file := FileAccess.open(path, FileAccess.WRITE)
		_check(file != null, "can create isolated collection fixture: " + script_path)
		if file == null:
			return
		file.store_string(text)
		file.close()
	# 下一进程直接读取上一进程保存的文件，不能重建 fixture 掩盖数据丢失。
	var resource := load(path) as Resource
	_check(resource != null, "can load collection fixture: " + script_path)
	if resource == null:
		return
	for name in names:
		var actual: Variant = resource.get(name)
		var expected_type := TYPE_ARRAY
		if name in ["prereqs", "advance_conditions"]:
			expected_type = TYPE_PACKED_STRING_ARRAY
		elif name == "condition_methods":
			expected_type = TYPE_DICTIONARY
		_check(typeof(actual) == expected_type and actual.size() == 2, "%s.%s retains two non-default fixture entries" % [script_path.get_file(), name])
	var before: Variant = _snapshot(resource)
	_check(ResourceSaver.save(resource, path) == OK, "can save collection fixture: " + script_path)
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reloaded != null and _snapshot(reloaded) == before, "save/reload preserves collection values and type parameters: " + script_path)


func run() -> void:
	# 正式工程不存在这个顶层测试脚本，防止误运行时写入正式资源目录。
	_check(FileAccess.file_exists("res://test_transition_serialization.gd"), "collection tests run only in isolated project")
	if failures != 0:
		return
	_scan_defaults("res://scripts")
	var array_fields := 'Array[ExtResource("2")]([SubResource("Item"), SubResource("Item")])'
	_roundtrip("res://scripts/states/state_library.gd",
		"states = " + array_fields, ["states"], "res://scripts/states/state_definition.gd")
	_roundtrip("res://scripts/states/state_library.gd",
		"compound_states = " + array_fields, ["compound_states"],
		"res://scripts/states/compound_state_definition.gd", "_compounds")
	_roundtrip("res://scripts/states/compound_state_definition.gd",
		"states = " + array_fields, ["states"], "res://scripts/states/state_definition.gd", "_children")
	_roundtrip("res://scripts/states/compound_state_definition.gd",
		"transitions = " + array_fields, ["transitions"], "res://scripts/transitions/transition_definition.gd", "_edges")
	_roundtrip("res://scripts/moves/fighter_move_library.gd",
		"moves = " + array_fields, ["moves"], "res://scripts/moves/fighter_move_definition.gd")
	_roundtrip("res://scripts/transitions/transition_library.gd",
		"transitions = " + array_fields + '\ncondition_methods = Dictionary[StringName, StringName]({&"gate_a": &"method_a", &"gate_b": &"method_b"})',
		["transitions", "condition_methods"], "res://scripts/transitions/transition_definition.gd")
	_roundtrip("res://scripts/fighter/fighter_loadout.gd",
		'selected_state_names = Array[StringName]([&"idle", &"crouch"])\nselected_move_ids = Array[StringName]([&"fixture_move_a", &"fixture_move_b"])',
		["selected_state_names", "selected_move_ids"])
	_roundtrip("res://scripts/moves/fighter_move_definition.gd",
		'prereqs = PackedStringArray("gate_a", "!gate_b")',
		["prereqs"])
	_roundtrip("res://scripts/transitions/transition_definition.gd",
		'prereqs = PackedStringArray("gate_a", "!gate_b")\nadvance_conditions = PackedStringArray("advance_a", "!advance_b")',
		["prereqs", "advance_conditions"])
	_roundtrip("res://scripts/input/fighter_command_definition.gd",
		'buttons = Array[StringName]([&"heavy_attack", &"guard"])\nsteps = Array[StringName]([&"down", &"heavy_attack"])',
		["buttons", "steps"])
	print("RESOURCE COLLECTION TESTS: %d checks, %d failures; %d exported collection defaults scanned" % [checks, failures, collection_fields])