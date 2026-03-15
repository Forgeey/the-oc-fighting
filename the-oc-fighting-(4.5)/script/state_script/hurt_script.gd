class_name HurtState
extends FrayState

# 声明角色、动画精灵变量
# 它们通过_ready_impl被赋值
var actor: CharacterBody2D
var state_machine: FrayStateMachine
var anim_observer: FrayAnimationObserver
var anim_player: AnimationPlayer

# 此函数获取state_machine.initialize第一个参数的context
func _ready_impl(context: Dictionary) -> void:
	actor = context.get("actor")
	state_machine = context.get("state_machine")
	anim_observer = context.get("anim_observer")
	anim_player = context.get("anim_player")
	
	# 初始化信号
	var attack_finished = anim_observer.usignal_finished("hurt")
	attack_finished.connect(_is_hurt_finished)

# 进入状态时进行的操作
func _enter_impl(_context: Dictionary) -> void:
	# 动画和角色速度
	anim_player.play("hurt")
	actor.velocity.x = 0

# 在这个状态每一帧的操作
func _physics_process_impl(delta):
	# 在 Fray 中，状态转换通过 transition 自动处理
	# 这里只处理状态内的逻辑
	pass

func _is_hurt_finished() -> void:
	state_machine.goto("idle_state")
