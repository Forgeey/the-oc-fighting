class_name JumpState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var sprite: AnimatedSprite2D
var state_machine: FrayStateMachine
var jump_velocity = 900.0
var gravity = 1800

# 判定状态管理器
var jump_hitstate: FrayHitState2D

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	sprite = context.get("sprite")
	state_machine = context.get("state_machine")
	jump_hitstate = actor.get_node("FrayHitStateManager2D/Jump_HitState2D")

# 进入状态时进行的操作
func _enter_impl(args: Dictionary):
	sprite.play("jump")
	actor.velocity.x = 0
	actor.velocity.y = -jump_velocity
	
	# 激活碰撞箱状态
	if jump_hitstate:
		jump_hitstate.activate()
		jump_hitstate.active_hitboxes = 3

func _physics_process_impl(delta):
	# 持续施加重力
	actor.velocity.y += gravity * delta
	actor.move_and_slide()
	
	# 当速度不再向上时，强制移动到浮空状态
	if actor.velocity.y >=0:
		state_machine.goto("float_state")
