# settings.gd
# 设置页采用格斗游戏的按键操作逻辑：整页只靠键盘/手柄驱动，不接受鼠标点击。
#   W / ↑ (1p_jump, 2p_jump)    上移选择
#   S / ↓ (1p_dodge, 2p_dodge)  下移选择
#   A / ← (1p_left, 2p_left)    减小 / 关闭 / 上一项
#   D / → (1p_right, 2p_right)  增大 / 开启 / 下一项
#   Enter / Space (ui_accept)   确认（开关翻转、分辨率下一项、执行「应用」「返回」）
#   Esc (ui_cancel)             返回
extends Control

signal closed  # 设置页关闭信号，通知主菜单恢复

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

const VOLUME_STEP := 0.05

# 未选中 / 选中状态下的行样式（在 setting.tscn 里配好）
@export var row_style: StyleBox
@export var row_style_selected: StyleBox

enum Row { MASTER_VOLUME, MUSIC_VOLUME, FULLSCREEN, RESOLUTION, APPLY, BACK }

# 竖向排列的可选行，顺序即上下移动的顺序
@onready var _rows: Array[Control] = [
	%MasterVolume,
	%MusicVolume,
	%Fullscreen,
	%Resolution,
	%Apply,
	%Back,
]

# 设置变量
var master_volume: float = 1.0
var music_volume: float = 1.0
var fullscreen: bool = false
var resolution: Vector2i = Vector2i(1920, 1080)

var _index: int = 0
var _resolution_index: int = 0
var _closing: bool = false


func _ready():
	# 加载当前设置
	_load_current_settings()

	# 把设置值刷到界面上，并选中第一行
	_refresh_all()
	_refresh_selection()

	# 入场动画
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.25).set_ease(Tween.EASE_OUT)


func _load_current_settings():
	# 未来增加设置管理器，从设置管理器加载设置
	# 目前直接读取窗口的真实状态，避免 UI 和实际显示对不上
	var mode := DisplayServer.window_get_mode()
	fullscreen = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	# 选中与当前窗口尺寸最接近的分辨率
	var current := DisplayServer.window_get_size()
	var best_delta := -1
	for i in range(RESOLUTIONS.size()):
		var delta: int = absi(RESOLUTIONS[i].x - current.x) + absi(RESOLUTIONS[i].y - current.y)
		if best_delta < 0 or delta < best_delta:
			best_delta = delta
			_resolution_index = i
	resolution = RESOLUTIONS[_resolution_index]

func _input(event: InputEvent) -> void:
	if _closing:
		return

	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_on_back_pressed()
	elif _is_up(event):
		accept_event()
		_move_selection(-1)
	elif _is_down(event):
		accept_event()
		_move_selection(1)
	elif _is_left(event):
		accept_event()
		_adjust(-1)
	elif _is_right(event):
		accept_event()
		_adjust(1)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		_activate()


func _is_up(event: InputEvent) -> bool:
	return event.is_action_pressed("1p_jump") or event.is_action_pressed("2p_jump")


func _is_down(event: InputEvent) -> bool:
	return event.is_action_pressed("1p_dodge") or event.is_action_pressed("2p_dodge")


func _is_left(event: InputEvent) -> bool:
	return event.is_action_pressed("1p_left") or event.is_action_pressed("2p_left")


func _is_right(event: InputEvent) -> bool:
	return event.is_action_pressed("1p_right") or event.is_action_pressed("2p_right")

func _move_selection(direction: int) -> void:
	_index = wrapi(_index + direction, 0, _rows.size())
	_refresh_selection()


# A / D：连续量增减，开关左关右开，分辨率上一项/下一项
func _adjust(direction: int) -> void:
	match _index:
		Row.MASTER_VOLUME:
			_set_master_volume(master_volume + direction * VOLUME_STEP)
		Row.MUSIC_VOLUME:
			_set_music_volume(music_volume + direction * VOLUME_STEP)
		Row.FULLSCREEN:
			_set_fullscreen(direction > 0)
		Row.RESOLUTION:
			_set_resolution_index(wrapi(_resolution_index + direction, 0, RESOLUTIONS.size()))


# Enter：开关翻转、分辨率下一项、执行动作行
func _activate() -> void:
	match _index:
		Row.FULLSCREEN:
			_set_fullscreen(not fullscreen)
		Row.RESOLUTION:
			_set_resolution_index(wrapi(_resolution_index + 1, 0, RESOLUTIONS.size()))
		Row.APPLY:
			_on_apply_pressed()
		Row.BACK:
			_on_back_pressed()

func _set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	_refresh_master_volume()


func _set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	# 项目暂时只有 Master 一条总线，加了音乐总线后这里才会生效
	if AudioServer.get_bus_count() > 1:
		AudioServer.set_bus_volume_db(1, linear_to_db(music_volume))
	_refresh_music_volume()


func _set_fullscreen(value: bool) -> void:
	if fullscreen == value:
		return
	fullscreen = value
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_refresh_fullscreen()


func _set_resolution_index(index: int) -> void:
	_resolution_index = index
	resolution = RESOLUTIONS[_resolution_index]
	if not fullscreen:
		DisplayServer.window_set_size(resolution)
	_refresh_resolution()

func _refresh_all() -> void:
	_refresh_master_volume()
	_refresh_music_volume()
	_refresh_fullscreen()
	_refresh_resolution()


func _refresh_master_volume() -> void:
	_row_slider(Row.MASTER_VOLUME).value = master_volume
	_row_value(Row.MASTER_VOLUME).text = "%d%%" % roundi(master_volume * 100.0)


func _refresh_music_volume() -> void:
	_row_slider(Row.MUSIC_VOLUME).value = music_volume
	_row_value(Row.MUSIC_VOLUME).text = "%d%%" % roundi(music_volume * 100.0)


func _refresh_fullscreen() -> void:
	_row_value(Row.FULLSCREEN).text = "‹ 开 ›" if fullscreen else "‹ 关 ›"


func _refresh_resolution() -> void:
	_row_value(Row.RESOLUTION).text = "‹ %d x %d ›" % [resolution.x, resolution.y]

func _refresh_selection() -> void:
	for i in range(_rows.size()):
		var row: Control = _rows[i]
		var selected: bool = i == _index
		row.add_theme_stylebox_override("panel", row_style_selected if selected else row_style)
		row.modulate = Color(1, 1, 1, 1) if selected else Color(1, 1, 1, 0.65)


func _row_slider(row_index: int) -> HSlider:
	return _rows[row_index].get_node("HBox/Slider") as HSlider


func _row_value(row_index: int) -> Label:
	return _rows[row_index].get_node("HBox/Value") as Label

func _on_apply_pressed():
	# 保存设置
	_save_settings()
	print("设置已应用")


func _on_back_pressed():
	# 返回主菜单
	_play_exit_animation()


func _play_exit_animation():
	# 禁用输入
	_closing = true
	set_process_input(false)

	# 淡出
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.2).set_ease(Tween.EASE_IN)

	await tween.finished
	closed.emit()
	queue_free()


func _save_settings():
	# 未来增加设置管理器，保存到设置管理器
	pass
