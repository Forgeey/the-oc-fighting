# settings.gd
extends Control

@onready var background = $BackGround
@onready var settings_panel = $Settings
@onready var controls_settings = $Settings/ControlsSettings
@onready var graphics_settings = $Settings/GraphicsSetting
@onready var apply_button = $HBoxContainer/Apply
@onready var back_button = $HBoxContainer/Back

# 设置变量
var master_volume: float = 1.0
var music_volume: float = 1.0
var fullscreen: bool = false
var resolution: Vector2i = Vector2i(1920, 1080)

func _ready():
	# 连接按钮信号
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# 加载当前设置
	_load_current_settings()
	
	# 初始化UI控件
	_setup_ui_controls()

func _load_current_settings():
	# 未来增加设置管理器，从设置管理器加载设置
	pass

func _setup_ui_controls():
	# 设置音量滑块
	if controls_settings:
		var master_slider = controls_settings.get_node("MasterVolume/Slider")
		var music_slider = controls_settings.get_node("MusicVolume/Slider")
		
		if master_slider:
			master_slider.value = master_volume
			master_slider.value_changed.connect(_on_master_volume_changed)
		
		if music_slider:
			music_slider.value = music_volume
			music_slider.value_changed.connect(_on_music_volume_changed)
	
	# 设置图形选项
	if graphics_settings:
		var fullscreen_check = graphics_settings.get_node("FullscreenCheck")
		var resolution_option = graphics_settings.get_node("ResolutionOption")
		
		if fullscreen_check:
			fullscreen_check.pressed = fullscreen
			fullscreen_check.toggled.connect(_on_fullscreen_toggled)
		
		if resolution_option:
			_setup_resolution_options(resolution_option)

func _on_master_volume_changed(value: float):
	master_volume = value
	AudioServer.set_bus_volume_db(0, linear_to_db(value))

func _on_music_volume_changed(value: float):
	music_volume = value
	AudioServer.set_bus_volume_db(1, linear_to_db(value))

func _on_fullscreen_toggled(pressed: bool):
	fullscreen = pressed
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _setup_resolution_options(option_button: OptionButton):
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440)
	]
	
	for i in range(resolutions.size()):
		var res = resolutions[i]
		option_button.add_item(str(res.x) + "x" + str(res.y), i)
		
		if res == resolution:
			option_button.selected = i
	
	option_button.item_selected.connect(_on_resolution_selected)

func _on_resolution_selected(index: int):
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440)
	]
	
	if index < resolutions.size():
		resolution = resolutions[index]
		DisplayServer.window_set_size(resolution)

func _on_apply_pressed():
	# 保存设置
	_save_settings()
	print("设置已应用")

func _on_back_pressed():
	# 返回主菜单
	SceneManager.change_scene("main")

func _save_settings():
	# 未来增加设置管理器，保存到设置管理器
	pass
