class_name FloatState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var sprite: AnimatedSprite2D
var gravity = 1800

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	sprite = context.get("sprite")

# 进入状态时进行的操作
func _enter_impl(args: Dictionary):
	sprite.play("float")

func _physics_process_impl(delta):
	# 持续施加重力
	actor.velocity.y += gravity * delta
	actor.move_and_slide()
