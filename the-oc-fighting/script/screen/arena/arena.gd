extends Node2D

# Arena场景主脚本

func _ready():
	# 显示控制说明
	show_control_instructions()

func show_control_instructions():
	# 创建控制说明UI
	var instructions = preload("res://script/ui/control_instructions.gd").new()
	
	# 创建Label节点
	var label = Label.new()
	label.name = "InstructionLabel"
	label.anchor_left = 0.1
	label.anchor_top = 0.1
	label.anchor_right = 0.9
	label.anchor_bottom = 0.9
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# 设置字体大小
	var label_settings = LabelSettings.new()
	label_settings.font_size = 20
	label_settings.font_color = Color.WHITE
	label.label_settings = label_settings
	
	instructions.add_child(label)
	
	# 设置背景
	var color_rect = ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.8)
	color_rect.anchor_left = 0.0
	color_rect.anchor_top = 0.0
	color_rect.anchor_right = 1.0
	color_rect.anchor_bottom = 1.0
	
	instructions.add_child(color_rect)
	instructions.move_child(color_rect, 0)  # 移到背景
	
	add_child(instructions)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
