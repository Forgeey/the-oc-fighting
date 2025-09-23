class_name IdleState
extends FrayState

# 声明角色、动画播放器变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var anim_player: AnimationPlayer

# 判定状态管理器
var idle_hitstate: FrayHitState2D

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	anim_player = context.get("anim_player")
	idle_hitstate = actor.get_node("FrayHitStateManager2D/Idle_HitState2D")

# 进入状态时进行的操作
func _enter_impl(_context: Dictionary) -> void:
	# 动画和角色速度
	anim_player.play("idle")
	actor.velocity.x = 0

# 在这个状态每一帧的操作
func _physics_process_impl(_delta):
	# 在 Fray 中，状态转换通过 transition 自动处理
	# 这里只处理状态内的逻辑
	pass
