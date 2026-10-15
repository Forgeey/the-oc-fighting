class_name DemoFighterHitstunState
extends FrayState

## 受击硬直状态：根据命中参数维持硬直并处理击退、空中重力修正。

const ID := &"hitstun"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.35
var gravity_scale := 1.0


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(args: Dictionary) -> void:
	elapsed_time = 0.0
	duration = float(args.get("duration", 0.35))
	gravity_scale = maxf(0.1, float(args.get("gravity_scale", 1.0)))
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Air" if args.get("airborne", false) else &"Stand")
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.movement.apply_gravity(delta, gravity_scale)
	fighter.movement.apply_knockback_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
