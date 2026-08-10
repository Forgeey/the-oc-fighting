class_name DemoFighterWakeupState
extends FrayState

## 倒地结束到恢复中立之间的明确起身恢复状态。
const ID := &"wakeup"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.25


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	elapsed_time = 0.0
	duration = fighter.movement.get_wakeup_recovery()
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Stand")
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_ground_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
