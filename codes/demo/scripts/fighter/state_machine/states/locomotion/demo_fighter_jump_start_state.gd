class_name DemoFighterJumpStartState
extends FrayState

## 起跳预备状态：锁定起跳方向并等待起跳前摇结束。

const ID := &"jump_start"

var fighter: DemoFighter
var elapsed_time := 0.0


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	elapsed_time = 0.0
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Stand")
	fighter.movement.queue_fighting_game_jump()
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_ground_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= fighter.movement.get_jump_startup_time()
