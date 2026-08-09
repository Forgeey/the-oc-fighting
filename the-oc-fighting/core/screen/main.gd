extends Control

# 背景在设置页打开时的放大倍率（沿用改造前 0.72 / 0.65 的观感）
const BG_ZOOM := 1.108

@onready var buttons = $Buttons
@onready var combat_button = $Buttons/双人对战
@onready var settings_button = $Buttons/设置
@onready var quit_game = $Buttons/退出
@onready var background = $BackGround
@onready var game_title = $GameTitle
@onready var input_hint = $InputHint

func _ready():
	# 连接按钮信号
	combat_button.pressed.connect(_on_combat_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_game.pressed.connect(_on_quit_pressed)

	# 背景铺满整个视口，缩放动画始终绕视口中心
	background.resized.connect(_update_bg_pivot)
	_update_bg_pivot()

	# 初始化背景模糊材质
	var blur_shader = load("res://asset/shader/blur.gdshader")
	var blur_mat = ShaderMaterial.new()
	blur_mat.shader = blur_shader
	blur_mat.set_shader_parameter("blur_strength", 0.0)
	background.material = blur_mat

	# Logo 与按键说明入场淡入（配合按钮入场动画）
	_fade_in_decor()


# 窗口尺寸变化时把缩放中心重新对到背景正中
func _update_bg_pivot():
	background.pivot_offset = background.size * 0.5


# Logo 与按键说明一起淡入
func _fade_in_decor():
	for node in [game_title, input_hint]:
		node.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.4).set_delay(0.15).set_ease(Tween.EASE_OUT)


# Logo 与按键说明一起淡出（设置页有自己的说明条，避免两条重叠）
func _fade_out_decor():
	for node in [game_title, input_hint]:
		var tween = create_tween()
		tween.tween_property(node, "modulate", Color(1, 1, 1, 0), 0.3).set_delay(0.1).set_ease(Tween.EASE_IN)


# 设置/清除背景模糊强度（被 tween_method 调用）
func _set_blur(value: float):
	if background.material:
		background.material.set_shader_parameter("blur_strength", value)


# 主菜单退出动画：按钮依次划出淡出 → Logo淡出 → 叠加设置页面
func _play_exit_animation():
	# 禁用输入，防止动画期间用户误操作
	set_process_input(false)
	buttons.process_mode = Node.PROCESS_MODE_DISABLED
	
	# 1) 按钮依次向右划出淡出（从上到下）
	for i in range(7):
		var btn = buttons.get_child(i)
		var tween = create_tween()
		tween.tween_interval(i * 0.06)  # 延迟后开始
		tween.set_parallel(true)
		tween.tween_property(btn, "position", btn.position + Vector2(300, 0), 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(btn, "modulate", Color(1, 1, 1, 0), 0.18).set_ease(Tween.EASE_IN)
	
	# 2) Logo 与按键说明淡出
	_fade_out_decor()
	
	# 3) 背景图轻微缩放 + 同步模糊
	var bg_tween = create_tween()
	bg_tween.set_parallel(true)
	bg_tween.tween_property(background, "scale", Vector2(BG_ZOOM, BG_ZOOM), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bg_tween.tween_method(_set_blur, 0.0, 0.8, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 等待动画完成
	await get_tree().create_timer(0.7).timeout
	
	# 4) 叠加设置页面（不销毁主菜单）
	_load_settings_overlay()


# 加载设置页面并叠加在主页面上方
func _load_settings_overlay():
	var setting_scene = load("res://core/screen/setting.tscn").instantiate()
	get_tree().root.add_child(setting_scene)
	# 监听设置页关闭信号
	setting_scene.closed.connect(_on_settings_closed)


# 设置页关闭：恢复主菜单
func _on_settings_closed():
	# 恢复按钮
	buttons.process_mode = Node.PROCESS_MODE_INHERIT
	buttons.restore_and_play_entrance()
	
	# 恢复 Logo 与按键说明
	_fade_in_decor()
	
	# 恢复背景缩放 + 清除模糊
	var bg_tween = create_tween()
	bg_tween.set_parallel(true)
	bg_tween.tween_property(background, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bg_tween.tween_method(_set_blur, 0.8, 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 恢复输入
	set_process_input(true)

func _on_combat_pressed():
	print("开始对战")
	SceneManager.change_scene("sky")

func _on_settings_pressed():
	print("打开设置")
	_play_exit_animation()

func _on_quit_pressed():
	print("退出")
	get_tree().quit()

func _input(event):
	# 按ESC键退出游戏
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if event.is_action_pressed("ui_accept"):
		buttons.当前选择框.emit_signal("pressed")
