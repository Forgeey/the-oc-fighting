class_name AttackState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var sprite: AnimatedSprite2D

# 判定状态管理器
var attack_hitstate: FrayHitState2D

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	sprite = context.get("sprite")
	attack_hitstate = actor.get_node("FrayHitStateManager2D/1_HitState2D")

# 进入状态时进行的操作
func _enter_impl(_context: Dictionary) -> void:
	# 动画和角色速度
	sprite.play("idle")
	actor.velocity.x = 0
	print("attack")
	# 激活碰撞箱状态
	if attack_hitstate:
		attack_hitstate.activate()
		attack_hitstate.active_hitboxes = 7

# 在这个状态每一帧的操作
func _physics_process_impl(_delta):
	# 在 Fray 中，状态转换通过 transition 自动处理
	# 这里只处理状态内的逻辑
	pass
