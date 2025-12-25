extends Control
@onready var buttons = $Buttons
@onready var combat_button = $Buttons/双人对战
@onready var settings_button = $Buttons/设置
@onready var quit_game = $Buttons/退出
@onready var background = $BackGround
@onready var game_title = $GameTitle

func _ready():
	# 连接按钮信号
	combat_button.pressed.connect(_on_combat_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_game.pressed.connect(_on_quit_pressed)
func _on_combat_pressed():
	print("开始对战")
	# 切换到战斗场景
	SceneManager.change_scene("sky")

func _on_settings_pressed():
	print("打开设置")
	# 切换到设置场景
	SceneManager.change_scene("setting")

func _on_quit_pressed():
	print("退出")
	# 切换到设置场景
	get_tree().quit()

func _input(event):
	# 按ESC键退出游戏
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if event.is_action_pressed("ui_accept"):
		buttons.当前选择框.emit_signal("pressed")
		pass
