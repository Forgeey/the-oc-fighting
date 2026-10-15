class_name DemoFighterJumpState
extends FrayState

## 上升跳跃状态：启动格斗游戏式跳跃并在上升结束后转入下落。

const ID := &"jump"

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
	fighter.movement.start_fighting_game_jump()
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

