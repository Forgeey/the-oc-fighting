class_name DemoFighterDashState
extends FrayState

## 地面前/后 dash 状态：由 Fray 双击方向指令进入，并使用起步、加速和刹车阶段推进。

var state_id: StringName = &""
var relative_direction := 1
var world_direction := 1
var fighter: DemoFighter
var elapsed_time := 0.0
var duration := 0.0
var speed := 0.0


## 初始化实例并保存构造参数。
func _init(p_state_id: StringName = &"", p_relative_direction := 1) -> void:
	state_id = p_state_id
	relative_direction = 1 if p_relative_direction >= 0 else -1


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:

	elapsed_time = 0.0
	duration = fighter.get_dash_duration(state_id)
	speed = fighter.get_dash_speed(state_id)
	world_direction = fighter.facing * relative_direction
	fighter.clear_attack_state()
	fighter.set_hurt_state(&"Stand")
	fighter.movement.set_jump_air_locked(false)
	fighter.movement.start_ground_dash(world_direction, speed)
	fighter.animation_player.play(state_id)


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:

	elapsed_time += delta
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_ground_dash_motion(world_direction, speed, elapsed_time, duration, delta)
	fighter.movement.move_body()


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return elapsed_time >= duration
