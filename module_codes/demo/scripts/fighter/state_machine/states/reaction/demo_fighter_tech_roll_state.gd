class_name DemoFighterTechRollState
extends FrayState

## 软倒地期间按住水平方向并通过 Fray 格挡输入进入的可选受身翻滚状态。
const ID := &"tech_roll"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.2
var world_direction := 1


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	elapsed_time = 0.0
	duration = fighter.movement.get_tech_roll_duration()
	world_direction = fighter.get_tech_roll_direction()
	fighter.clear_pending_knockdown()
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Crouch")
	fighter.movement.set_jump_air_locked(false)
	fighter.movement.start_tech_roll(world_direction)
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_tech_roll_motion(world_direction, elapsed_time, duration, delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
