extends CharacterBody2D

## 预加载状态脚本资源
const IdleState = preload("res://script/state_script/idle_script.gd")
const RightState = preload("res://script/state_script/right_script.gd")
const LeftState = preload("res://script/state_script/left_script.gd")
const DodgeState = preload("res://script/state_script/dodge_script.gd")
const JumpState = preload("res://script/state_script/jump_script.gd")
const DoubleJumpState = preload("res://script/state_script/double_jump_script.gd")
const RightJumpState = preload("res://script/state_script/right_jump_script.gd")
const LeftJumpState = preload("res://script/state_script/left_jump_script.gd")
const FloatState = preload("res://script/state_script/float_script.gd")
const LandState = preload("res://script/state_script/land_script.gd")
const AttackState = preload("res://script/state_script/attack_script.gd")
const HurtState = preload("res://script/state_script/hurt_script.gd")

# 状态机节点和推进器节点
@onready var state_machine = $FrayStateMachine
@onready var advancer = $FrayStateMachine/FrayBufferedInputAdvancer
@onready var hit_state_manager = $VisualRoot/FrayHitStateManager2D
@onready var anim_observer = $FrayAnimationObserver
@onready var anim_player = $AnimationPlayer

# 变量
@export var max_air_jumps: int = 1
var remaining_air_jumps: int
var is_facing_right = false
var double_jump_state: DoubleJumpState
var land_state: LandState

# 载入节点时触发一次
func _ready() -> void:
	# 角色变量
	remaining_air_jumps = max_air_jumps
	
	# 二段跳状态实例
	double_jump_state = DoubleJumpState.new()
	land_state = LandState.new()
	
	# 初始化状态机
	# 第一个参数是状态数据
	state_machine.initialize({
			actor = self,
			sprite = $AnimatedSprite2D,
			anim_observer = $FrayAnimationObserver,
			anim_player = $AnimationPlayer,
			state_machine = state_machine,
		},
		FrayCompoundState.builder()
		# 初始状态
		.start_at("idle_state")
		# 添加状态
		.add_state("idle_state", IdleState.new())
		.add_state("right_state", RightState.new())
		.add_state("left_state", LeftState.new())
		.add_state("dodge_state", DodgeState.new())
		.add_state("jump_state", JumpState.new())
		.add_state("double_jump_state", double_jump_state)
		.add_state("right_jump_state", RightJumpState.new())
		.add_state("left_jump_state", LeftJumpState.new())
		.add_state("float_state", FloatState.new())
		.add_state("land_state", land_state)
		.add_state("attack_state", AttackState.new())
		.add_state("hurt_state", HurtState.new())
		
		# 打标签
		.tag_multi(["idle_state", "right_state", "left_state", "land_state", "dodge_state"], ["stand_on_ground"])
		.tag_multi(["jump_state", "float_state", "right_jump_state", "left_jump_state"], ["in_air"])
		
		# 注册条件
		.register_conditions({
			"is_on_ground": _is_on_ground,
			"can_double_jump": _can_double_jump
		})
		
		# 定义状态转换
		# 待机的状态转换
		.transition_press("idle_state", "right_state", {"input": "right"})					# 持续输入前进
		.transition_press("idle_state", "left_state", {"input": "left"})					# 持续输入后退
		.transition_press("idle_state", "dodge_state", {"input": "dodge"})						# 持续输入下蹲
		.transition_press("idle_state", "jump_state", {"input": "jump"})							# 点击输入上跳
		.transition_press("idle_state", "right_jump_state", {"input": "right_jump"})			# 点击输入前跳
		.transition_press("idle_state", "left_jump_state", {"input": "left_jump"})			# 点击输入后跳
		.transition_press("idle_state", "attack_state", {"input": "attack"})					# 点击输入攻击
		
		# 前进的状态转换
		.transition_press("right_state", "idle_state", {"input": "right_release"})			# 松开输入前进
		.transition_press("right_state", "left_state", {"input": "left"})				# 持续输入后退
		.transition_press("right_state", "dodge_state", {"input": "dodge"}) 					# 持续输入下蹲
		.transition_press("right_state", "jump_state", {"input": "jump"})						# 点击输入上跳
		.transition_press("right_state", "right_jump_state", {"input": "right_jump"})		# 点击输入前跳
		.transition_press("right_state", "left_jump_state", {"input": "left_jump"})		# 点击输入后跳
		
		# 后退的状态转换
		.transition_press("left_state", "idle_state", {"input": "left_release"})			# 松开输入后退
		.transition_press("left_state", "right_state", {"input": "right"})				# 持续输入前进
		.transition_press("left_state", "dodge_state", {"input": "dodge"}) 					# 持续输入下蹲
		.transition_press("left_state", "jump_state", {"input": "jump"})						# 点击输入上跳
		.transition_press("left_state", "right_jump_state", {"input": "right_jump"})		# 点击输入前跳
		.transition_press("left_state", "left_jump_state", {"input": "left_jump"})		# 点击输入后跳
		
		# 下蹲的状态转换
		.transition_press("dodge_state", "idle_state", {"input": "dodge_release"})				# 松开输入下蹲
		.transition_press("dodge_state", "right_state", {"input": "right"})					# 持续输入前进
		.transition_press("dodge_state", "left_state", {"input": "left"})					# 持续输入后退
		.transition_press("dodge_state", "jump_state", {"input": "jump"})							# 点击输入上跳
		.transition_press("dodge_state", "right_jump_state", {"input": "right_jump"})			# 点击输入前跳
		.transition_press("dodge_state", "left_jump_state", {"input": "left_jump"})		# 点击输入后跳
		
		# 跳跃的状态转换
		.transition_press("jump_state", "double_jump_state", {
			"prereqs": ["can_double_jump"],
			"input": "jump"
		})
		
		# 浮空的状态转换
		.transition("float_state", "land_state", {												# 条件回到待机
			"advance_conditions": ["is_on_ground"],
			"auto_advance": true
		})
		.transition_press("float_state", "double_jump_state", {
			"prereqs": ["can_double_jump"],
			"input": "jump"
		})
		
		# 落地状态转换
		.transition("land_state", "idle_state", {
			"auto_advance": true,
			"switch_mode": FrayStateMachineTransition.SwitchMode.AT_END
		})

		# 构建状态机
		.build()
	)
	
	# FrayHitStateManager判定管理器信号连接
	hit_state_manager.hitbox_intersected.connect(_is_hurt)
	#hit_state_manager.hitbox_separated()
	double_jump_state.reduce_double_jump.connect(_reduce_double_jump)
	land_state.reset_double_jump.connect(_reset_double_jump)
	

# 每帧执行一次状态机，专用于条件转换
func _process(delta: float) -> void:
	pass

# 每帧推进一次
func _physics_process(delta: float) -> void:
	state_machine.advance()

# 检查是否在地面上
func _is_on_ground() -> bool:
	return is_on_floor()

# 检查是否可以二段跳
func _can_double_jump() -> bool:
	if remaining_air_jumps > 0:
		return true
	else:
		return false

# 减少一次二段跳次数
func _reduce_double_jump() -> void:
	remaining_air_jumps -= 1

# 重置二段跳次数
func _reset_double_jump() -> void:
	remaining_air_jumps = max_air_jumps

# 攻击判定，强制转换到受击状态
func _is_hurt(detector_hitbox: FrayHitbox2D, detected_hitbox: FrayHitbox2D) -> void:
	state_machine.goto("hurt_state")
