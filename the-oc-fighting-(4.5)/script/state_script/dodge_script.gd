class_name ParryState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var anim_player: AnimationPlayer

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	anim_player = context.get("anim_player")

# 进入状态时进行的操作
func _enter_impl(context: Dictionary) -> void:
	anim_player.play("dodge")
	# 如果这里要改的话，应该需要用到我新加的VisualRoot，对其进行翻转，用scale.x=-1，能让判定框和图像精灵一起翻转（Furai）
	#sprite.flip_h = true

# 在这个状态每一帧的操作
func _physics_process_impl(delta):
	pass
