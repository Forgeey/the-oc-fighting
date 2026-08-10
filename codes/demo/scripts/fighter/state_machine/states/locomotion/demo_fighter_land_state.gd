class_name DemoFighterLandState
extends FrayState

## 落地恢复状态：恢复时长完全由角色移动配置决定，动画仅负责视觉表现。
const ID := &"land"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.0


## 状态就绪时从上下文获取角色依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化落地恢复并播放静态动画。
func _enter_impl(args: Dictionary) -> void:
	elapsed_time = 0.0
	duration = float(args.get("duration", fighter.movement.get_landing_recovery()))
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Crouch" if fighter.wants_crouch() else &"Stand")
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 每个物理帧更新落地恢复行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_ground_friction(delta)
	fighter.movement.move_body()


## 达到配置的落地恢复时长后结束状态。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
