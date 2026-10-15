class_name DemoFighterKnockdownState
extends FrayState

## 地面倒地状态；持续时间读取战斗结算器缓存的 FrayAttackAttribute 受击数据。
const ID := &"knockdown"

var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.45
var untechable_time := 0.0
var hard_knockdown := false


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	var knockdown := fighter.consume_pending_knockdown()
	elapsed_time = 0.0
	duration = float(knockdown.get("duration", 0.0))
	if duration <= 0.0:
		duration = fighter.movement.get_default_knockdown_time()
	untechable_time = clampf(float(knockdown.get("untechable_time", 0.0)), 0.0, duration)
	hard_knockdown = bool(knockdown.get("hard", false))
	fighter.set_knockdown_tech_available(false, hard_knockdown)
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Crouch")
	fighter.movement.set_jump_air_locked(false)
	fighter.animation_player.play(ID)


## 退出状态时清理该状态产生的运行时数据。
func _exit_impl() -> void:
	fighter.set_knockdown_tech_available(false, false)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	elapsed_time += delta
	fighter.set_knockdown_tech_available(not hard_knockdown and elapsed_time >= untechable_time, hard_knockdown)
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_knockdown_friction(delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration


