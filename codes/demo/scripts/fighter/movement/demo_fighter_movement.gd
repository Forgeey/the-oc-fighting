class_name DemoFighterMovement
extends RefCounted

const FLOOR_CONTACT_EPSILON := 0.5

## 封装 demo 角色运动公式，FrayState 只负责选择何时调用。

var fighter: DemoFighter
var pushbox: DemoFighterPushbox
var environment: DemoFighterEnvironment
var queued_jump_axis := 0.0
var queued_jump_facing := 1
var jump_air_locked := false
var max_air_jumps := 1
var air_jumps_used := 0


## 保存运行所需依赖并完成初始化。
func setup(
	p_fighter: DemoFighter,
	p_pushbox: DemoFighterPushbox,
	p_environment: DemoFighterEnvironment
) -> void:
	fighter = p_fighter
	pushbox = p_pushbox
	environment = p_environment


## 设置跳跃空中锁定。
func set_jump_air_locked(locked: bool) -> void:
	jump_air_locked = locked


## 返回起跳准备阶段的持续时间。
func get_jump_startup_time() -> float:
	return environment.jump_startup_time


## 返回跳跃状态至少保持的上升时间。
func get_min_jump_rise_time() -> float:
	return environment.min_jump_rise_time


## 返回下落状态至少保持的时间。
func get_min_fall_time() -> float:
	return environment.min_fall_time


## 返回落地恢复。
func get_landing_recovery() -> float:
	return environment.landing_recovery


## 返回默认倒地持续时间。
func get_default_knockdown_time() -> float:
	return environment.default_knockdown_time


## 返回起身恢复。
func get_wakeup_recovery() -> float:
	return environment.wakeup_recovery


## 返回受身翻滚持续时间。
func get_tech_roll_duration() -> float:
	return environment.tech_roll_duration


## 移动角色本体并结算地面与推挤框。
func move_body() -> void:
	fighter.move_and_slide()
	_snap_to_environment_floor()
	if is_floor_contact():
		reset_air_jumps()
	pushbox.clamp_to_arena()
	pushbox.resolve_against(fighter.opponent)


## 应用重力。
func apply_gravity(delta: float, gravity_scale := 1.0) -> void:
	if not fighter.is_on_floor() and not _is_at_or_below_environment_floor():
		var gravity: float
		if fighter.velocity.y < 0.0:
			gravity = environment.jump_rise_gravity
			if absf(fighter.velocity.y) <= environment.apex_speed_threshold:
				gravity *= environment.apex_gravity_multiplier
		else:
			gravity = environment.jump_fall_gravity
		fighter.velocity.y = minf(
			fighter.velocity.y + gravity * maxf(0.1, gravity_scale) * delta,
			environment.max_fall_speed
		)
	elif fighter.velocity.y > 0.0:
		fighter.velocity.y = 0.0


## 对角色水平速度应用地面摩擦。
func apply_ground_friction(delta: float) -> void:
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, environment.friction * delta)


## 根据输入轴更新地面行走速度。
func apply_walk_motion(delta: float) -> void:
	var target_speed := fighter.get_move_axis() * environment.walk_speed
	fighter.velocity.x = move_toward(fighter.velocity.x, target_speed, environment.ground_accel * delta)


## 开始地面冲刺。
func start_ground_dash(world_direction: int, speed: float) -> void:
	fighter.velocity.x = float(world_direction) * speed * environment.dash_initial_speed_ratio
	if is_floor_contact() and fighter.velocity.y > 0.0:
		fighter.velocity.y = 0.0


## 按冲刺阶段更新地面冲刺速度。
func apply_ground_dash_motion(
	world_direction: int,
	speed: float,
	elapsed_time: float,
	duration: float,
	delta: float
) -> void:
	var phase := clampf(elapsed_time / maxf(duration, 0.001), 0.0, 1.0)
	var target_speed := speed
	var acceleration := environment.dash_accel
	if phase >= environment.dash_brake_start_ratio:
		var brake_phase := inverse_lerp(environment.dash_brake_start_ratio, 1.0, phase)
		target_speed = lerpf(speed, speed * environment.dash_exit_speed_ratio, brake_phase)
		acceleration = environment.dash_brake
	fighter.velocity.x = move_toward(
		fighter.velocity.x,
		float(world_direction) * target_speed,
		acceleration * delta
	)


## 保持起跳时确定的水平惯性，不读取空中方向输入。
## 非跳跃轨迹（例如外力产生的空中位移）仍使用空中击退摩擦逐渐减速。
func apply_air_horizontal_velocity(delta: float) -> void:
	if jump_air_locked:
		return
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, environment.air_knockback_friction * delta)


## 对受击后的水平击退速度应用衰减。
func apply_knockback_friction(delta: float) -> void:
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, environment.friction * 0.5 * delta)


## 对倒地滑动速度应用摩擦。
func apply_knockdown_friction(delta: float) -> void:
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, environment.knockdown_friction * delta)


## 开始受身翻滚。
func start_tech_roll(world_direction: int) -> void:
	fighter.velocity.x = float(world_direction) * environment.tech_roll_speed
	fighter.velocity.y = 0.0


## 更新受身翻滚期间的水平移动。
func apply_tech_roll_motion(
	world_direction: int,
	elapsed_time: float,
	duration: float,
	delta: float
) -> void:
	var phase := clampf(elapsed_time / maxf(duration, 0.001), 0.0, 1.0)
	var target_speed := environment.tech_roll_speed * (1.0 - phase)
	fighter.velocity.x = move_toward(
		fighter.velocity.x,
		float(world_direction) * target_speed,
		environment.tech_roll_brake * delta
	)


## 根据攻击属性更新攻击期间的移动。
func apply_attack_motion(attack: FrayAttackAttribute, attack_frame: int, delta: float) -> void:

	if attack_frame < attack.lunge_frames:
		fighter.velocity.x = fighter.facing * attack.lunge_speed
	elif fighter.is_on_floor():
		apply_ground_friction(delta)
	else:
		apply_air_horizontal_velocity(delta)


## 缓存格斗游戏式跳跃的起跳方向。
func queue_fighting_game_jump() -> void:
	queued_jump_axis = signf(fighter.get_move_axis())
	queued_jump_facing = fighter.facing
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, environment.friction * environment.jump_startup_time)
	if is_floor_contact() and fighter.velocity.y > 0.0:
		fighter.velocity.y = 0.0


## 判断是否地面接触。
func is_floor_contact() -> bool:
	if fighter.is_on_floor():
		return true
	return fighter.global_position.y >= environment.floor_y - FLOOR_CONTACT_EPSILON and fighter.velocity.y >= 0.0


## 重置空中跳跃次数。
func reset_air_jumps() -> void:
	air_jumps_used = 0


## 判断当前是否可以二段跳跃。
func can_double_jump() -> bool:
	return not is_floor_contact() and air_jumps_used < max_air_jumps


## 开始二段跳跃。
func start_double_jump() -> void:
	if not can_double_jump():
		return

	air_jumps_used += 1
	queued_jump_axis = signf(fighter.get_move_axis())
	queued_jump_facing = fighter.facing
	var jump_dir := queued_jump_axis
	var jump_x_speed := environment.jump_forward_x_speed * 0.9 if jump_dir == float(queued_jump_facing) else environment.jump_back_x_speed * 0.9
	if jump_dir == 0.0:
		jump_x_speed = 0.0

	jump_air_locked = true
	fighter.velocity.x = jump_dir * jump_x_speed
	fighter.velocity.y = -environment.jump_neutral_speed * 0.9


## 按照缓存方向开始格斗游戏式跳跃。
func start_fighting_game_jump() -> void:
	var jump_dir := queued_jump_axis
	var jump_x_speed := 0.0
	var jump_y_speed := environment.jump_neutral_speed

	if jump_dir != 0.0:
		var is_forward_jump := jump_dir == float(queued_jump_facing)
		jump_x_speed = environment.jump_forward_x_speed if is_forward_jump else environment.jump_back_x_speed
		jump_y_speed = environment.jump_forward_speed if is_forward_jump else environment.jump_back_speed

	jump_air_locked = true
	fighter.velocity.x = jump_dir * jump_x_speed
	fighter.velocity.y = -jump_y_speed


## 判断角色是否到达或低于场地地面。
func _is_at_or_below_environment_floor() -> bool:
	return fighter.global_position.y >= environment.floor_y and fighter.velocity.y >= 0.0


## 吸附to场地地面。
func _snap_to_environment_floor() -> void:
	if fighter.global_position.y <= environment.floor_y:
		return

	fighter.global_position.y = environment.floor_y
	if fighter.velocity.y > 0.0:
		fighter.velocity.y = 0.0
