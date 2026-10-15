@tool
class_name DemoFighterLoadout
extends Resource

## Demo 使用的固定招式及其 Fray 指令；固定攻击属性由角色场景中的 hit-state strike 持有。
@export var entries: Array[DemoMoveLoadoutEntry] = []

const RESERVED_STATE_IDS := [
	&"idle",
	&"walk",
	&"crouch",
	&"dash_forward",
	&"dash_back",
	&"jump_start",
	&"jump",
	&"double_jump",
	&"fall",
	&"land",
	&"hitstun",
	&"blockstun",
	&"knockdown",
	&"wakeup",
	&"tech_roll",
	&"ko",
]


## 按招式标识查找配置条目。
func find_entry(move_id: StringName) -> DemoMoveLoadoutEntry:
	for entry in entries:
		if entry != null and entry.move != null and entry.move.id == move_id:
			return entry
	return null


## 判断指定招式是否已启用。
func is_installed(move_id: StringName) -> bool:
	var entry := find_entry(move_id)
	return entry != null and entry.enabled


## 返回指定招式当前配置的指令。
func get_command(move_id: StringName) -> DemoMoveCommand:
	var entry := find_entry(move_id)
	return entry.command if entry != null else null


## 返回通过验证并按优先级排序的已启用条目。
func get_installed_entries() -> Array[DemoMoveLoadoutEntry]:
	var installed: Array[DemoMoveLoadoutEntry] = []
	var seen_ids: Dictionary = {}
	for entry in entries:
		if entry == null or not entry.enabled or entry.move == null:
			continue
		if seen_ids.has(entry.move.id):
			push_warning("Duplicate installed move ignored: %s" % entry.move.id)
			continue
		seen_ids[entry.move.id] = true
		if not _is_valid_entry(entry):
			continue
		installed.append(entry)
	installed.sort_custom(_sort_entries_by_priority)
	return installed


## 判断来源招式当前是否允许取消到目标招式。
func can_cancel_to_move(source_move_id: StringName, target_move_id: StringName) -> bool:
	var source_entry := find_entry(source_move_id)
	return (
		source_entry != null
		and source_entry.enabled
		and is_installed(target_move_id)
		and source_entry.move.cancel_target_move_ids.has(String(target_move_id))
	)


## 返回来源招式当前可用的取消目标标识列表。
func get_cancel_target_ids(source_move_id: StringName) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var source_entry := find_entry(source_move_id)
	if source_entry == null or not source_entry.enabled:
		return result
	for target_id in source_entry.move.cancel_target_move_ids:
		if is_installed(StringName(target_id)):
			result.append(target_id)
	return result


## 收集并返回整套招式配置的验证错误。
func get_validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var command_owner: Dictionary = {}
	var installed_ids: Dictionary = {}
	for entry in entries:
		if entry == null or not entry.enabled:
			continue
		if entry.move == null or not entry.move.is_valid() or is_reserved_move_id(entry.move.id):
			errors.append("Invalid installed move entry.")
			continue
		if installed_ids.has(entry.move.id):
			errors.append("%s is installed more than once." % entry.move.display_name)
			continue
		installed_ids[entry.move.id] = true
		if entry.command == null:
			errors.append("%s has no command." % entry.move.display_name)
			continue
		var command_error := entry.command.get_validation_error()
		if not command_error.is_empty():
			errors.append("%s: %s" % [entry.move.display_name, command_error])
			continue
		if entry.move.neutral_available:
			var collision_key := "%s|%s" % [entry.move.activation_context, entry.command.get_signature()]
			if command_owner.has(collision_key):
				errors.append(
					"%s and %s use the same command in the same context."
					% [command_owner[collision_key], entry.move.display_name]
				)
			else:
				command_owner[collision_key] = entry.move.display_name

	for entry in entries:
		if entry == null or not entry.enabled or entry.move == null:
			continue
		var parent_id := entry.move.combo_parent_move_id
		if parent_id == &"":
			continue
		if not installed_ids.has(parent_id):
			errors.append("%s requires missing kombo parent %s." % [entry.move.display_name, parent_id])
			continue
		var parent_entry := find_entry(parent_id)
		if (
			parent_entry == null
			or parent_entry.move == null
			or not parent_entry.move.cancel_target_move_ids.has(String(entry.move.id))
		):
			errors.append("%s is not a cancel target of %s." % [entry.move.display_name, parent_id])
	return errors


## 判断招式标识是否与内置状态名称冲突。
static func is_reserved_move_id(move_id: StringName) -> bool:
	return RESERVED_STATE_IDS.has(move_id)


## 生成招式序列输入在 Fray 中使用的名称。
static func get_sequence_input_name(move_id: StringName) -> StringName:
	return StringName("move_%s" % move_id)


## 生成组合输入步骤在 Fray 中使用的名称。
static func get_combination_input_name(step: DemoMoveCommandStep) -> StringName:
	if step == null:
		return &""
	return StringName("command_combo_%s" % step.get_signature().replace("+", "_"))


## 验证已启用条目的招式和指令配置。
func _is_valid_entry(entry: DemoMoveLoadoutEntry) -> bool:
	if not entry.move.is_valid():
		push_warning("Invalid move definition ignored: %s" % entry.move.id)
		return false
	if is_reserved_move_id(entry.move.id):
		push_warning("Move ID %s collides with a built-in fighter state" % entry.move.id)
		return false
	if entry.command == null:
		push_warning("Installed move %s has no command" % entry.move.id)
		return false
	var command_error := entry.command.get_validation_error()
	if not command_error.is_empty():
		push_warning("Installed move %s ignored: %s" % [entry.move.id, command_error])
		return false
	return true


## 按指令复杂度和招式优先级对条目排序。
func _sort_entries_by_priority(a: DemoMoveLoadoutEntry, b: DemoMoveLoadoutEntry) -> bool:
	var a_priority := a.command.get_complexity() * 100 + a.move.priority
	var b_priority := b.command.get_complexity() * 100 + b.move.priority
	return a_priority > b_priority
