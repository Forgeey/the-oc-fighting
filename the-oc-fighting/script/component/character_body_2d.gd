extends CharacterBody2D

## 预加载状态脚本资源
const IdleState = preload("res://script/state_script/idle_script.gd")
const ForwardState = preload("res://script/state_script/forward_script.gd")
const BackwardState = preload("res://script/state_script/backward_script.gd")
const DodgeState = preload("res://script/state_script/dodge_script.gd")
const JumpState = preload("res://script/state_script/jump_script.gd")
const ForwardJumpState = preload("res://script/state_script/forward_jump_script.gd")
const BackwardJumpState = preload("res://script/state_script/backward_jump_script.gd")
const FloatState = preload("res://script/state_script/float_script.gd")

@onready var state_machine: FrayStateMachine = $FrayStateMachine
@onready var advancer = $FrayStateMachine/FrayBufferedInputAdvancer

func _ready() -> void:
	# 映射输入
	FrayInputMap.add_bind_action("forward", "right")
	FrayInputMap.add_bind_action("backward", "left")
	FrayInputMap.add_bind_action("jump", "jump")
	FrayInputMap.add_bind_action("dodge", "dodge")
	init_combine_actions()
	
	# 将FrayInputMap信号传给函数处理
	FrayInput.input_detected.connect(_on_FrayInput_input_dected)

	# 初始化状态机
	# 第一个参数是状态数据
	state_machine.initialize({
			actor = self,
			sprite = $AnimatedSprite2D,
			state_machine = state_machine
		},
		FrayCompoundState.builder()
		# 初始状态
		.start_at("idle_state")
		# 添加状态
		.add_state("idle_state", IdleState.new())
		.add_state("forward_state", ForwardState.new())
		.add_state("backward_state", BackwardState.new())
		.add_state("dodge_state", DodgeState.new())
		.add_state("jump_state", JumpState.new())
		.add_state("forward_jump_state", ForwardJumpState.new())
		.add_state("backward_jump_state", BackwardJumpState.new())
		.add_state("float_state", FloatState.new())
		
		# 打标签
		.tag_multi(["idle_state", "forward_state", "backward_state", "dodge_state"], ["stand_on_ground"])
		.tag_multi(["jump_state", "float_state", "forward_jump_state", "backward_jump_state"], ["in_air"])
		
		# 注册条件
		.register_conditions({ "is_on_ground": _is_on_ground})
		
		# 定义状态转换
		.transition_press("idle_state", "forward_state", {"input": "forward"})
		.transition_press("forward_state", "idle_state", {"input": "idle"})
		.transition_press("idle_state", "backward_state", {"input": "backward"})
		.transition_press("backward_state", "idle_state", {"input": "idle"})
		.transition_press("idle_state", "dodge_state", {"input": "dodge"})
		.transition_press("dodge_state", "idle_state", {"input": "idle"})
		.transition_press("idle_state", "jump_state", {"input": "jump"})
		.transition_press("forward_state", "forward_jump_state", {"input": "forward_jump"})
		.transition_press("backward_state", "backward_jump_state", {"input": "backward_jump"})
		.transition("float_state", "idle_state", {
			"advance_conditions": ["is_on_ground"],
			"auto_advance": true
		})
		.build()
	)
	
	# 角色1在左边，面朝右。动画精灵默认朝向为朝左，后期进行调整。

# 构建运动招式表
func init_combine_actions() -> void:
	# 设计前跳，由前和跳按键组合而成
	FrayInputMap.add_composite_input("forward_jump", FrayCombinationInput.builder()
		.add_component_simple("forward")
		.add_component_simple("jump")
		.mode_async()
		.build()
	)
	# 设计后跳，由后和跳按键组合而成
	FrayInputMap.add_composite_input("backward_jump", FrayCombinationInput.builder()
		.add_component_simple("backward")
		.add_component_simple("jump")
		.mode_async()
		.build()
	)

func _process(delta: float) -> void:
	if FrayInput.is_pressed("forward"):
		advancer.buffer_press("forward")
	elif FrayInput.is_pressed("backward"):
		advancer.buffer_press("backward")
	elif FrayInput.is_pressed("dodge"):
		advancer.buffer_press("dodge")
	elif FrayInput.is_just_pressed("jump"):
		advancer.buffer_press("jump")
	else:
		advancer.buffer_press("idle")

func _physics_process(delta: float) -> void:
	pass
	
# 检查是否在地面上
func _is_on_ground() -> bool:
	return is_on_floor()
	
func _on_FrayInput_input_dected(event: FrayInputEvent) -> void:
	if event.input == "forward_jump" and event.is_pressed():
		advancer.buffer_press("forward_jump")
	if event.input == "backward_jump" and event.is_pressed():
		advancer.buffer_press("backward_jump")
