extends Control

@onready var combat_button = $Buttons/对战
@onready var settings_button = $Buttons/设置
@onready var background = $BackGround
@onready var game_title = $GameTitle

func _ready():
	# 连接按钮信号
	combat_button.pressed.connect(_on_combat_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

func _on_combat_pressed():
	print("开始对战")
	# 切换到战斗场景
	SceneManager.change_scene("arena")

func _on_settings_pressed():
	print("打开设置")
	# 切换到设置场景
	SceneManager.change_scene("setting")

func _input(event):
	# 按ESC键退出游戏
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
