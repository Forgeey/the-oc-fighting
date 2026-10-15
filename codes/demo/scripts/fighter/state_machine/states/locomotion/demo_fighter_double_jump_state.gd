class_name DemoFighterDoubleJumpState
extends FrayState

## 空中二段跳状态：通过 Fray 输入转移进入，刷新一次空中跳速度。

const ID := &"double_jump"

var fighter: DemoFighter
var elapsed_time := 0.0


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	elapsed_time = 0.0
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Air")
	fighter.movement.start_double_jump()
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_air_horizontal_velocity(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return (
		elapsed_time >= fighter.movement.get_min_jump_rise_time() and fighter.velocity.y >= 0.0
	)

