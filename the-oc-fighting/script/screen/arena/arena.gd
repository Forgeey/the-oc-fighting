extends Node2D

# Arena场景主脚本
@onready var player1: CharacterBody2D = $Player1/CharacterBody2D
@onready var player2: CharacterBody2D = $Player2/CharacterBody2D

# 获取两个玩家的 AnimatedSprite2D 节点
@onready var p1_vr: Node2D = $Player1/CharacterBody2D/VisualRoot
@onready var p2_vr: Node2D = $Player2/CharacterBody2D/VisualRoot

# 获取每个玩家的输入推进器
@onready var p1_advancer = player1.advancer
@onready var p2_advancer = player2.advancer

# 准备
func _ready():
	# 初始化输入系统
	_init_player_control()
	# 初始化组合招式
	_init_combine_actions()
	
	# 将FrayInputMap信号传给函数处理
	FrayInput.input_detected.connect(_Player1_FrayInput_input_dected)
	# 将FrayInputMap信号传给函数处理
	FrayInput.input_detected.connect(_Player2_FrayInput_input_dected)

# 帧处理
func _process(delta: float) -> void:
	# 根据相对位置决定朝向
	if player1.global_position.x < player2.global_position.x:
		# 玩家1面朝右，玩家2面朝左
		player1.is_facing_right = true
		player2.is_facing_right = false
		# 玩家1在左，玩家2在右
		p1_vr.scale.x = -1		# P1朝右
		p2_vr.scale.x = 1		# P2朝左
	else:
		# 玩家1面朝左，玩家2面朝右
		player1.is_facing_right = false
		player2.is_facing_right = true
		# 玩家1在右，玩家2在左
		p1_vr.scale.x = 1		# P1朝左
		p2_vr.scale.x = -1		# P2朝右
	
	# p1玩家检测
	if FrayInput.is_pressed("1p_right_move"):			# 持续输入前进
		p1_advancer.buffer_press("right")
	elif FrayInput.is_just_released("1p_right_move"):	# 松开输入前进
		p1_advancer.buffer_press("right_release")
	elif FrayInput.is_pressed("1p_left_move"):		# 持续输入后退
		p1_advancer.buffer_press("left")
	elif FrayInput.is_just_released("1p_left_move"):	# 松开输入后退
		p1_advancer.buffer_press("left_release") 
	elif FrayInput.is_pressed("1p_dodge"):			# 持续输入下蹲
		p1_advancer.buffer_press("dodge")
	elif FrayInput.is_just_released("1p_dodge"):		# 松开输入下蹲
		p1_advancer.buffer_press("dodge_release") 
	elif FrayInput.is_just_pressed("1p_jump"):		# 点击输入上跳
		p1_advancer.buffer_press("jump")
	elif FrayInput.is_just_pressed("1p_attack"):
		p1_advancer.buffer_press("attack")
	elif FrayInput.is_just_pressed("1p_attack2"):
		p1_advancer.buffer_press("attack2")

	# p2玩家检测
	if FrayInput.is_pressed("2p_right_move"):			# 持续输入前进
		p2_advancer.buffer_press("right")
	elif FrayInput.is_just_released("2p_right_move"):	# 松开输入前进
		p2_advancer.buffer_press("right_release")
	elif FrayInput.is_pressed("2p_left_move"):		# 持续输入后退
		p2_advancer.buffer_press("left")
	elif FrayInput.is_just_released("2p_left_move"):	# 松开输入后退
		p2_advancer.buffer_press("left_release") 
	elif FrayInput.is_pressed("2p_dodge"):			# 持续输入下蹲
		p2_advancer.buffer_press("dodge")
	elif FrayInput.is_just_released("2p_dodge"):		# 松开输入下蹲
		p2_advancer.buffer_press("dodge_release") 
	elif FrayInput.is_just_pressed("2p_jump"):		# 点击输入上跳
		p2_advancer.buffer_press("jump")

# 初始化玩家按键输入
func _init_player_control() -> void:
	# 玩家1
	FrayInputMap.add_bind_action("1p_right_move", "1p_right")
	FrayInputMap.add_bind_action("1p_left_move", "1p_left")
	FrayInputMap.add_bind_action("1p_jump", "1p_jump")
	FrayInputMap.add_bind_action("1p_dodge", "1p_dodge")
	FrayInputMap.add_bind_action("1p_attack", "1p_attack")
	FrayInputMap.add_bind_action("1p_attack2", "1p_attack2")

	# 玩家2
	FrayInputMap.add_bind_action("2p_right_move", "2p_right")
	FrayInputMap.add_bind_action("2p_left_move", "2p_left")
	FrayInputMap.add_bind_action("2p_jump", "2p_jump")
	FrayInputMap.add_bind_action("2p_dodge", "2p_dodge")
	FrayInputMap.add_bind_action("2p_attack", "2p_attack")

# 构建运动招式表
func _init_combine_actions() -> void:
	# 玩家1
	# 设计前跳，由前和跳按键组合而成
	FrayInputMap.add_composite_input("1p_right_jump", FrayCombinationInput.builder()
		.add_component_simple("1p_right_move")
		.add_component_simple("1p_jump")
		.mode_async()
		.is_virtual()
		.build()
	)
	FrayInputMap.add_composite_input("1p_left_jump", FrayCombinationInput.builder()
		.add_component_simple("1p_left_move")
		.add_component_simple("1p_jump")
		.mode_async()
		.is_virtual()
		.build()
	)
	
	# 玩家2
	# 设计前跳，由前和跳按键组合而成
	FrayInputMap.add_composite_input("2p_right_jump", FrayCombinationInput.builder()
		.add_component_simple("2p_right_move")
		.add_component_simple("2p_jump")
		.mode_async()
		.is_virtual()
		.build()
	)
	FrayInputMap.add_composite_input("2p_left_jump", FrayCombinationInput.builder()
		.add_component_simple("2p_left_move")
		.add_component_simple("2p_jump")
		.mode_async()
		.is_virtual()
		.build()
	)

# 条件函数，判断角色在左或在右
func _is_p1_on_right_side(device: int) -> bool:
	return player1.global_position.x > player2.global_position.x
func _is_p2_on_right_side(device: int) -> bool:
	return player2.global_position.x > player1.global_position.x
	
# 检测器，处理组合输入
# 玩家1
func _Player1_FrayInput_input_dected(event: FrayInputEvent) -> void:
	if event.input == "1p_right_jump" and event.is_pressed():
		p1_advancer.buffer_press("right_jump")
	if event.input == "1p_left_jump" and event.is_pressed():
		p1_advancer.buffer_press("left_jump")

# 玩家2
func _Player2_FrayInput_input_dected(event: FrayInputEvent) -> void:
	if event.input == "2p_right_jump" and event.is_pressed():
		p2_advancer.buffer_press("right_jump")
	if event.input == "2p_left_jump" and event.is_pressed():
		p2_advancer.buffer_press("left_jump")
