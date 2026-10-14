extends Control

const CONFIRM_DIALOG_SCENE := preload("res://core/ui/confirm_dialog.tscn")
const MENU_EXIT_STAGGER := 0.04
const MENU_EXIT_DURATION := 0.2
const MENU_ENTRANCE_STAGGER := 0.06
const MENU_ENTRANCE_DURATION := 0.25
const MENU_BUTTON_COUNT := 7
const SETTINGS_TRANSITION_DURATION := 0.45

@onready var buttons = $Buttons
@onready var combat_button = $Buttons/双人对战
@onready var settings_button = $Buttons/设置
@onready var quit_game = $Buttons/退出
@onready var background = $BackGround
@onready var game_title = $GameTitle
@onready var input_hint = $InputHint

var _dialog_active: bool = false
var _game_title_start_position: Vector2

func _ready():
	# 连接按钮信号
	combat_button.pressed.connect(_on_combat_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_game.pressed.connect(_on_quit_pressed)
	_game_title_start_position = game_title.position

	# 初始化背景模糊材质
	var blur_shader = load("res://asset/shader/blur.gdshader")
	var blur_mat = ShaderMaterial.new()
	blur_mat.shader = blur_shader
	blur_mat.set_shader_parameter("blur_strength", 0.0)
	background.material = blur_mat

	# Logo 与按键说明入场淡入（配合按钮入场动画）
	_fade_in_decor()



# Logo 滑入，按键说明淡入
func _fade_in_decor():
	for node in [game_title, input_hint]:
		if node == game_title:
			var slide_distance: float = _get_game_title_slide_distance()
			node.position = _game_title_start_position - Vector2(slide_distance, 0)
		var tween = create_tween()
		if node == game_title:
			tween.tween_property(node, "position", _game_title_start_position, _get_menu_entrance_duration()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			node.modulate = Color(1, 1, 1, 0)
			tween.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.4).set_delay(0.15).set_ease(Tween.EASE_OUT)


# Logo 滑出，按键说明淡出（设置页有自己的说明条，避免两条重叠）
func _fade_out_decor():
	for node in [game_title, input_hint]:
		var tween = create_tween()
		if node == game_title:
			var slide_distance: float = _get_game_title_slide_distance()
			tween.tween_property(game_title, "position", _game_title_start_position - Vector2(slide_distance, 0), _get_menu_exit_duration()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		else:
			tween.tween_property(node, "modulate", Color(1, 1, 1, 0), 0.3).set_delay(0.1).set_ease(Tween.EASE_IN)


func _get_menu_entrance_duration() -> float:
	return MENU_ENTRANCE_DURATION + MENU_ENTRANCE_STAGGER * float(MENU_BUTTON_COUNT - 1)


func _get_menu_exit_duration() -> float:
	return MENU_EXIT_DURATION + MENU_EXIT_STAGGER * float(MENU_BUTTON_COUNT - 1)


func _get_game_title_slide_distance() -> float:
	return _game_title_start_position.x + float(game_title.size.x) + 16.0


# 设置/清除背景模糊强度（被 tween_method 调用）
func _set_blur(value: float):
	if background.material:
		background.material.set_shader_parameter("blur_strength", value)


# 主菜单退出动画：按钮依次划出淡出 → Logo淡出 → 叠加设置页面
func _play_exit_animation():
	set_process_input(false)
	buttons.process_mode = Node.PROCESS_MODE_DISABLED
	
	for i in range(MENU_BUTTON_COUNT):
		var btn = buttons.get_child(i)
		var tween = create_tween()
		tween.tween_interval(i * MENU_EXIT_STAGGER)
		tween.set_parallel(true)
		tween.tween_property(btn, "position", btn.position + Vector2(300, 0), MENU_EXIT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	_fade_out_decor()
	
	var bg_tween = create_tween()
	bg_tween.tween_method(_set_blur, 0.0, 0.8, SETTINGS_TRANSITION_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	await get_tree().create_timer(SETTINGS_TRANSITION_DURATION).timeout
	
	_load_settings_overlay()


# 加载设置页面并叠加在主页面上方
func _load_settings_overlay():
	var setting_scene = load("res://core/screen/setting.tscn").instantiate()
	get_tree().root.add_child(setting_scene)
	# 监听设置页关闭信号
	setting_scene.closed.connect(_on_settings_closed)


# 设置页关闭：恢复主菜单
func _on_settings_closed():
	buttons.process_mode = Node.PROCESS_MODE_INHERIT
	buttons.restore_and_play_entrance()
	
	_fade_in_decor()
	
	var bg_tween = create_tween()
	bg_tween.tween_method(_set_blur, 0.8, 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	set_process_input(true)

func _on_combat_pressed():
	print("开始对战")
	SceneManager.change_scene("sky")

func _on_settings_pressed():
	print("打开设置")
	_play_exit_animation()

func _on_quit_pressed():
	print("退出")
	_show_quit_confirm()


# 弹出确认框，确认后才退出游戏
func _show_quit_confirm():
	if _dialog_active:
		return
	_dialog_active = true
	buttons.process_mode = Node.PROCESS_MODE_DISABLED
	var dialog = CONFIRM_DIALOG_SCENE.instantiate()
	dialog.title_text = "退出游戏"
	dialog.message_text = "确定要退出游戏吗？"
	dialog.confirm_text = "退出"
	dialog.cancel_text = "留下"
	add_child(dialog)
	dialog.confirmed.connect(_on_quit_confirmed)
	dialog.cancelled.connect(_on_quit_cancelled)


func _on_quit_confirmed():
	_dialog_active = false
	get_tree().quit()


func _on_quit_cancelled():
	_dialog_active = false
	buttons.process_mode = Node.PROCESS_MODE_INHERIT

func _input(event):
	# 弹窗打开期间不响应主菜单按键
	if _dialog_active:
		return
	# 按ESC键退出游戏（带确认）
	if event.is_action_pressed("ui_cancel"):
		_show_quit_confirm()
	if event.is_action_pressed("ui_accept"):
		buttons.当前选择框.emit_signal("pressed")
