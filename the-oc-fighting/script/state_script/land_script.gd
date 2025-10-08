class_name LandState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var anim_player: AnimationPlayer
var state_machine: FrayStateMachine

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	anim_player = context.get("anim_player")
	state_machine = context.get("state_machine")

# 进入状态时进行的操作
func _enter_impl(args: Dictionary):
	anim_player.play("land")
	actor.velocity.x = 0

func _is_done_processing_impl() -> bool:
	if not is_instance_valid(anim_player):
		return true
	else:
		return not anim_player.is_playing()

func _physics_process_impl(delta):
	pass
