class_name LeftState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var sprite: AnimatedSprite2D
var facing_right: bool
var speed = 180.0

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	sprite = context.get("sprite")

# 进入状态时进行的操作
func _enter_impl(context: Dictionary) -> void:
	pass

# 检查状态，设置动画
func _process_impl(delta: float):
	# 判断角色面朝哪
	facing_right = actor.is_facing_right
	# 如果面朝右，向左移动状态，那就是后退，否则是前进
	if facing_right:
		sprite.play("backward")
	else:
		sprite.play("forward")

# 在这个状态每一帧的操作
func _physics_process_impl(delta):
	# 设置移动速度，然后移动
	actor.velocity.x = -speed
	actor.move_and_slide()
