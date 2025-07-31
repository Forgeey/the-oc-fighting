class_name LeftJumpState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var sprite: AnimatedSprite2D
var state_machine: FrayStateMachine
var facing_right : bool
var speed = 180
var jump_velocity = 800.0
var gravity = 1800

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	sprite = context.get("sprite")
	state_machine = context.get("state_machine")

# 进入状态时进行的操作
func _enter_impl(args: Dictionary):
	# 判断角色面朝哪
	facing_right = actor.is_facing_right
	# 如果面朝右，向左移动状态，那就是后跳，否则是前跳
	if facing_right:
		sprite.play("backjump")
	else:
		sprite.play("jump")
	actor.velocity.x = -speed
	actor.velocity.y = -jump_velocity

func _physics_process_impl(delta):
	# 持续施加重力
	actor.velocity.y += gravity * delta
	actor.move_and_slide()
	
	# 当速度不再向上时，强制移动到浮空状态
	if actor.velocity.y >=0:
		state_machine.goto("float_state")
