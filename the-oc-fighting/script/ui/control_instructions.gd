extends Control
class_name ControlInstructions

# 控制说明UI

@onready var instruction_label: Label = $InstructionLabel

var instructions_text = """
🎮 平台跳跃游戏控制说明

【玩家1 - WASD控制】
🔹 移动: A(左) D(右)
🔹 跳跃: W

【玩家2 - 方向键控制】  
🔹 移动: ←(左) →(右)
🔹 跳跃: ↑

【游戏特性】
✨ 更强的重力和下落速度(1.8倍)
✨ 空中控制有限，地面控制精确
✨ 最大下落速度限制(800px/s)
✨ 流畅的跳跃和移动体验

按任意键继续...
"""

func _ready():
	if instruction_label:
		instruction_label.text = instructions_text
	
	# 自动隐藏
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 8.0
	timer.one_shot = true
	timer.timeout.connect(hide_instructions)
	timer.start()

func _input(event):
	if event.is_pressed():
		hide_instructions()

func hide_instructions():
	queue_free()

func show_instructions():
	visible = true 
