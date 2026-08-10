class_name FoundationDebugOverlay
extends Control
## Fighter foundation 的只读调试覆盖层。
##
## 输入历史来自 FrayInput 事件，招式历史来自 Fray 状态转移成功结果；本层不参与输入判定。

const DISPLAY_INPUT_HISTORY_LIMIT: int = 8
const DISPLAY_STATE_HISTORY_LIMIT: int = 4
const DISPLAY_MOVE_HISTORY_LIMIT: int = 3

## 要观察的 FoundationFighter 节点路径。
@export_node_path("CharacterBody2D") var fighter_path: NodePath

@onready var _fighter: FoundationFighter = get_node_or_null(fighter_path) as FoundationFighter
@onready var _state_label: Label = %StateLabel
@onready var _input_label: Label = %InputLabel
@onready var _buffer_label: Label = %BufferLabel
@onready var _move_label: Label = %MoveLabel
@onready var _input_history_label: Label = %InputHistoryLabel
@onready var _state_history_label: Label = %StateHistoryLabel


## 初始化覆盖层；fighter 缺失时显示明确错误。
func _ready() -> void:
	if _fighter == null:
		_state_label.text = "FoundationFighter 未找到：%s" % fighter_path
		set_process(false)


## 每帧轮询只读快照；不从 UI 反向修改 fighter 状态。
func _process(_delta: float) -> void:
	var snapshot := _fighter.get_debug_snapshot()
	if not snapshot.get("valid", false):
		_state_label.text = "初始化中：%s" % snapshot.get("reason", "unknown")
		return
	_update_state_text(snapshot)
	_update_input_text(snapshot)
	_update_buffer_text(snapshot)
	_update_move_text(snapshot)
	_update_input_history_text(snapshot)
	_update_state_history_text(snapshot)


## 更新状态、路径、tag 与移动数据文本。
func _update_state_text(snapshot: Dictionary) -> void:
	var facing := int(snapshot.get("facing", 1))
	var facing_text := "右" if facing > 0 else "左"
	var tags: PackedStringArray = snapshot.get("tags", PackedStringArray())
	var velocity_value: Vector2 = snapshot.get("velocity", Vector2.ZERO)
	_state_label.text = (
		"状态: %s（%s）  路径: %s\nTags: %s\n速度: (%.1f, %.1f)  落地: %s  朝向: %s\n锁定: %s  暂停: %s\n最近转移: %s"
		% [
			snapshot.get("state", &""),
			snapshot.get("action", ""),
			snapshot.get("path", ""),
			", ".join(tags),
			velocity_value.x,
			velocity_value.y,
			snapshot.get("grounded", false),
			facing_text,
			snapshot.get("control_locked", false),
			snapshot.get("simulation_paused", false),
			snapshot.get("last_transition", ""),
		]
	)


## 更新 FrayController 的物理与相对语义输入文本。
func _update_input_text(snapshot: Dictionary) -> void:
	var names := PackedStringArray([
		"p1_left", "p1_right", "p1_down", "p1_up",
		"p1_forward", "p1_back", "p1_down_forward",
		"p1_light", "p1_heavy", "p1_guard",
	])
	var pressed := PackedStringArray()
	for input_name in names:
		if _fighter.controller.is_pressed(input_name):
			pressed.append(_format_input_name(input_name))
	_input_label.text = (
		"设备: %s  connected=%s  F%s\n当前按下: %s"
		% [
			snapshot.get("device", 0),
			snapshot.get("device_connected", false),
			snapshot.get("physics_frame", 0),
			"<无>" if pressed.is_empty() else ", ".join(pressed),
		]
	)


## 更新缓冲项名称、类型和 pause-aware 年龄。
func _update_buffer_text(snapshot: Dictionary) -> void:
	var lines := PackedStringArray()
	var current_clock := int(snapshot.get("buffer_clock_msec", 0))
	var buffer: Array = snapshot.get("buffer", [])
	for item in buffer:
		var input_name := "unknown"
		if item is FrayBufferedInputAdvancer.BufferedInputPress:
			input_name = "press:%s" % _format_input_name(item.input)
		elif item is FrayBufferedInputAdvancer.BufferedInputSequence:
			input_name = "sequence:%s" % _format_input_name(item.sequence_name)
		var age: int = int(item.calc_elapsed_time_msec(current_clock))
		lines.append("%s  age=%dms" % [input_name, age])
	_buffer_label.text = (
		"Fray 缓冲（5F / 83.333ms，clock_frozen=%s）：\n%s"
		% [
			snapshot.get("buffer_clock_paused", false),
			"<空>" if lines.is_empty() else "\n".join(lines),
		]
	)


## 更新已成功输出的招式和可用招式清单。
func _update_move_text(snapshot: Dictionary) -> void:
	var lines := PackedStringArray()
	var history: Array = snapshot.get("move_history", [])
	var first_index := maxi(history.size() - DISPLAY_MOVE_HISTORY_LIMIT, 0)
	for index in range(history.size() - 1, first_index - 1, -1):
		var item: Dictionary = history[index]
		lines.append("F%s  %s [%s]" % [item.get("frame", 0), item.get("name", ""), item.get("command", "")])
	var available_lines := PackedStringArray()
	var available_moves: Array = snapshot.get("available_moves", [])
	for value in available_moves:
		var item: Dictionary = value
		available_lines.append("%s [%s]" % [item.get("name", ""), item.get("command", "")])
	var last_move: Dictionary = snapshot.get("last_move", {})
	var last_move_text := "<尚未识别>"
	if not last_move.is_empty():
		last_move_text = "%s [%s]，F%s" % [last_move.get("name", ""), last_move.get("command", ""), last_move.get("frame", 0)]
	_move_label.text = (
		"最近招式: %s\n可用招式: %s\n\n招式输出历史（新→旧）：\n%s"
		% [
			last_move_text,
			" | ".join(available_lines),
			"<空>" if lines.is_empty() else "\n".join(lines),
		]
	)


## 更新 Fray 语义输入按下/松开历史，便于对照状态和招式输出。
func _update_input_history_text(snapshot: Dictionary) -> void:
	var lines := PackedStringArray()
	var history: Array = snapshot.get("input_history", [])
	var first_index := maxi(history.size() - DISPLAY_INPUT_HISTORY_LIMIT, 0)
	for index in range(history.size() - 1, first_index - 1, -1):
		var item: Dictionary = history[index]
		var edge := "按下" if item.get("pressed", false) else "松开"
		var flags := PackedStringArray()
		if item.get("virtual", false):
			flags.append("语义")
		if not item.get("distinct", true):
			flags.append("非独立")
		var flag_text := "" if flags.is_empty() else " (%s)" % ",".join(flags)
		lines.append("F%s  %s  %s%s" % [
			item.get("frame", 0),
			_format_input_name(StringName(item.get("input", ""))),
			edge,
			flag_text,
		])
	_input_history_label.text = "输入历史（新→旧）：\n%s" % ("<空>" if lines.is_empty() else "\n".join(lines))


## 更新最近 Fray 状态转移历史。
func _update_state_history_text(snapshot: Dictionary) -> void:
	var lines := PackedStringArray()
	var history: Array = snapshot.get("state_history", [])
	var first_index := maxi(history.size() - DISPLAY_STATE_HISTORY_LIMIT, 0)
	for index in range(history.size() - 1, first_index - 1, -1):
		var item: Dictionary = history[index]
		lines.append("F%s  %s → %s" % [item.get("frame", 0), item.get("from", &""), item.get("to", &"")])
	_state_history_label.text = "状态输出历史（新→旧）：\n%s" % ("<空>" if lines.is_empty() else "\n".join(lines))


## 把内部 Fray 输入名转换成紧凑的 HUD 文本。
func _format_input_name(input_name: StringName) -> String:
	var short_name := String(input_name).trim_prefix("p1_")
	match short_name:
		"left":
			return "左 / A"
		"right":
			return "右 / D"
		"down":
			return "下 / S"
		"up":
			return "上 / W"
		"forward":
			return "前"
		"back":
			return "后"
		"down_forward":
			return "下前"
		"light":
			return "轻攻击 / J"
		"heavy":
			return "重攻击 / K"
		"guard":
			return "防御 / Q"
		"dash_forward":
			return "前冲 / 66"
		"dash_back":
			return "后撤 / 44"
		_:
			return short_name
