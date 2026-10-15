class_name DemoFighterBlockstunState
extends FrayState

## 防御硬直状态：保留受击后的后退并在持续时间结束后回到中立。

const ID := &"blockstun"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.18


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(args: Dictionary) -> void:
	elapsed_time = 0.0
	duration = float(args.get("duration", 0.18))
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Air" if args.get("airborne", false) else (&"Crouch" if fighter.wants_crouch() else &"Stand"))
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_knockback_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
