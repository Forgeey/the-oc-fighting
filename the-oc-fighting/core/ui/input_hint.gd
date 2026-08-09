@tool
extends HBoxContainer

## 按键操作说明条（主菜单、设置页等界面共用）。
##
## hints 每一项的格式为 "按键|说明"，例如 "W / S|选择"。
## 按键部分用亮色、说明部分用暗色渲染，条目之间的间距由本节点的
## theme_override_constants/separation 控制。

const SEPARATOR := "|"
const ENTRY_SEPARATION := 8

@export var hints: Array[String] = ["W / S|选择", "Enter|确认", "Esc|返回"]:
	set(value):
		hints = value
		_rebuild()

@export var key_color: Color = Color(1, 1, 1, 0.92):
	set(value):
		key_color = value
		_rebuild()

@export var action_color: Color = Color(0.85, 0.85, 0.85, 0.7):
	set(value):
		action_color = value
		_rebuild()

@export var font_size: int = 18:
	set(value):
		font_size = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# 导出属性的 setter 在 _ready 之前就会被调用，这时子节点还不存在
	if not is_node_ready():
		return

	for child in get_children():
		remove_child(child)
		child.queue_free()

	for hint in hints:
		var parts := hint.split(SEPARATOR, false, 1)
		if parts.is_empty():
			continue
		add_child(_make_entry(parts[0], parts[1] if parts.size() > 1 else ""))


func _make_entry(key: String, action: String) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_theme_constant_override("separation", ENTRY_SEPARATION)
	entry.add_child(_make_label(key, key_color))
	if not action.is_empty():
		entry.add_child(_make_label(action, action_color))
	return entry


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label
