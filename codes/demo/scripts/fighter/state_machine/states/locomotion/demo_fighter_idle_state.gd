class_name DemoFighterIdleState
extends FrayState

## 站立中立状态：清理攻击并启用站姿受击框。

const ID := &"idle"

var fighter: DemoFighter


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Stand")
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_ground_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return true
