extends Control

const CONFIRM_DIALOG_SCENE := preload("res://core/ui/confirm_dialog.tscn")
const SLIDE_TRANSITION := preload("res://core/ui/slide_transition.gd")
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

func _ready():
	# 连接按钮信号
	combat_button.pressed.connect(_on_combat_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_game.pressed.connect(_on_quit_pressed)
	# 初始化背景模糊材质
	var blur_shader = load("res://asset/shader/blur.gdshader")
	var blur_mat = ShaderMaterial.new()
	blur_mat.shader = blur_shader
	blur_mat.set_shader_parameter("blur_strength", 0.0)
	background.material = blur_mat

	# Logo 与按键提示入场（配合按钮入场动画）
	_fade_in_decor()



# Logo 滑入，按键提示从下方滑入
func _fade_in_decor():
	SLIDE_TRANSITION.slide_in(game_title, SLIDE_TRANSITION.Direction.RIGHT, 0.0, _get_menu_entrance_duration())
	input_hint.play_entrance(SLIDE_TRANSITION.Direction.UP)


# Logo 滑出，按键提示向下滑出（设置页有自己的说明条，避免两条重叠）
func _fade_out_decor():
	SLIDE_TRANSITION.slide_out(game_title, SLIDE_TRANSITION.Direction.LEFT, 0.0, _get_menu_exit_duration())
	input_hint.play_exit(SLIDE_TRANSITION.Direction.DOWN)


func _get_menu_entrance_duration() -> float:
	return MENU_ENTRANCE_DURATION + MENU_ENTRANCE_STAGGER * float(MENU_BUTTON_COUNT - 1)


func _get_menu_exit_duration() -> float:
	return MENU_EXIT_DURATION + MENU_EXIT_STAGGER * float(MENU_BUTTON_COUNT - 1)


# 设置/清除背景模糊强度（被 tween_method 调用）
func _set_blur(value: float):
	if background.material:
		background.material.set_shader_parameter("blur_strength", value)


func _play_exit_animation():
	set_process_input(false)
	buttons.set_process_input(false)
	
	for i in range(MENU_BUTTON_COUNT):
		var btn = buttons.get_child(i)
		SLIDE_TRANSITION.slide_out(
			btn,
			SLIDE_TRANSITION.Direction.RIGHT,
			i * MENU_EXIT_STAGGER,
			MENU_EXIT_DURATION
		)
	
	_fade_out_decor()
	
	await get_tree().create_timer(SETTINGS_TRANSITION_DURATION).timeout
	
	_load_settings_overlay()


# 加载设置页面并叠加在主页面上方
func _load_settings_overlay():
	var setting_scene = load("res://core/screen/setting.tscn").instantiate()
	setting_scene.opening.connect(_on_settings_opening)
	setting_scene.closed.connect(_on_settings_closed)
	setting_scene.closing.connect(_on_settings_closing)
	get_tree().root.add_child(setting_scene)


func _on_settings_opening(transition_duration: float):
	var bg_tween = create_tween()
	bg_tween.tween_method(_set_blur, 0.0, 0.8, transition_duration).set_ease(Tween.EASE_OUT)


# 设置页开始关闭：与遮罩淡出同步恢复背景清晰度
func _on_settings_closing(transition_duration: float):
	var bg_tween = create_tween()
	bg_tween.tween_method(_set_blur, 0.8, 0.0, transition_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


# 设置页退场完成后，再播放主菜单入场动画
func _on_settings_closed():
	buttons.set_process_input(true)
	buttons.restore_and_play_entrance()
	_fade_in_decor()
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
