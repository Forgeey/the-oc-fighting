class_name DemoMoveListFormatter
extends RefCounted

## 直接从已安装的 Fray 招式配置生成格斗游戏风格招式表，不在界面层复制指令和取消路线数据。
const INPUT_LABELS := {
	"up": "U",
	"down": "D",
	"forward": "F",
	"back": "B",
	"left": "LEFT",
	"right": "RIGHT",
	"light": "J",
	"heavy": "K",
	"special": "L",
	"block": ";",
}


## 根据当前招式配置生成招式表 BBCode。
static func build_bbcode(loadout: DemoFighterLoadout) -> String:
	var entries := loadout.get_installed_entries()
	var entries_by_id: Dictionary = {}
	for entry in entries:
		entries_by_id[entry.move.id] = entry

	var basic_lines: PackedStringArray = PackedStringArray()
	var combo_lines: PackedStringArray = PackedStringArray()
	var special_lines: PackedStringArray = PackedStringArray()
	var cancel_lines: PackedStringArray = PackedStringArray()

	for entry in entries:
		var move := entry.move
		if move.is_special_move():
			special_lines.append(_format_move_line(move.get_move_list_name(), _format_command(entry.command)))
		else:
			if move.neutral_available:
				basic_lines.append(_format_move_line(move.display_name, _format_command(entry.command)))
			if move.is_combo_ender():
				var combo_command := _format_combo_route(entry, entries_by_id)
				combo_lines.append(_format_move_line(move.get_move_list_name(), combo_command))
				var targets := _get_special_cancel_labels(loadout, move)
				if not targets.is_empty():
					cancel_lines.append(
						"• [color=#f4e7c5]%s[/color]  [color=#e05a47]~[/color]  %s"
						% [combo_command, " / ".join(targets)]
					)

	basic_lines.sort()
	combo_lines.sort()
	special_lines.sort()
	cancel_lines.sort()

	var sections: PackedStringArray = PackedStringArray()
	sections.append("[center][font_size=24][b]招式表  /  MOVE LIST[/b][/font_size][/center]")
	sections.append("[center][color=#aaa69d]F=向前  B=向后  D=下  U=上  ·  J=轻击  K=重击  L=特殊  ;=格挡[/color][/center]")
	sections.append("[center][color=#8f8b84],=依次输入  +=同时输入  ~=取消  ·  M 关闭[/color][/center]")
	_append_section(sections, "基础攻击  BASIC ATTACKS", basic_lines)
	_append_section(sections, "组合技  KOMBOS", combo_lines)
	_append_section(sections, "特殊技  SPECIAL MOVES", special_lines)
	_append_section(sections, "组合技取消  KOMBO SPECIAL CANCELS", cancel_lines)
	sections.append("[color=#aaa69d]取消提示：在上一段攻击的取消窗口内完成后续输入。方向会随角色朝向自动镜像。[/color]")
	return "\n\n".join(sections)


## 追加章节。
static func _append_section(output: PackedStringArray, title: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	output.append("[color=#e05a47][b]%s[/b][/color]\n%s" % [title, "\n".join(lines)])


## 格式化招式行。
static func _format_move_line(name: String, command: String) -> String:
	return "• [color=#f4e7c5]%-28s[/color] [color=#f2c14e][b]%s[/b][/color]" % [name, command]


## 格式化连段路线。
static func _format_combo_route(
	ender_entry: DemoMoveLoadoutEntry,
	entries_by_id: Dictionary
) -> String:
	var command_parts: Array[String] = []
	var current := ender_entry
	var visited: Dictionary = {}
	while current != null and current.move != null and not visited.has(current.move.id):
		visited[current.move.id] = true
		command_parts.push_front(_format_command(current.command))
		var parent_id := current.move.combo_parent_move_id
		if parent_id == &"":
			current = null
		else:
			current = entries_by_id.get(parent_id) as DemoMoveLoadoutEntry
	return ", ".join(command_parts)


## 返回特殊技取消标签。
static func _get_special_cancel_labels(
	loadout: DemoFighterLoadout,
	source_move: DemoMoveDefinition
) -> PackedStringArray:
	var labels: PackedStringArray = PackedStringArray()
	for target_text in loadout.get_cancel_target_ids(source_move.id):
		var target_id := StringName(target_text)
		var target_entry := loadout.find_entry(target_id)
		var target := target_entry.move if target_entry != null else null
		if target == null or not target.is_special_move():
			continue
		var command_text := _format_command(loadout.get_command(target_id))
		labels.append(
			"%s [color=#f2c14e][b]%s[/b][/color]"
			% [target.get_move_list_name(), command_text]
		)
	return labels


## 格式化指令。
static func _format_command(command: DemoMoveCommand) -> String:
	if command == null:
		return "—"
	var steps: PackedStringArray = PackedStringArray()
	for step in command.steps:
		if step == null:
			continue
		var inputs: PackedStringArray = PackedStringArray()
		for input_name in step.inputs:
			inputs.append(String(INPUT_LABELS.get(input_name, input_name.to_upper())))
		steps.append("+".join(inputs))
	return ", ".join(steps)
