class_name FoundationMovement
extends RefCounted
## CharacterBody2D 的格斗游戏式移动适配层。
## 统一负责所有状态的底层角色运动计算。
## 每个FrayState负责决定在当前状态的哪个时机调用哪一种运动方法
##
## 地面移动、冲刺、分段重力、固定跳跃轨迹、二段跳、受击击退和场地边界
## 均由状态调用；攻击帧数据仍只来自 FrayAttackAttribute。

# 常量，在角色脚底即将接触或刚好轻微陷入地面时，强行认定角色为“接地”状态
# 防止角色因物理引擎的数值误差或高速下落导致的落地判定失效
const FLOOR_CONTACT_EPSILON: float = 0.5

# 变量，包括角色、环境、运动参数
# _queued记录角色跳跃时的摇杆方向和角色朝向
# _jump_air_locked禁止角色浮空时受到空中的摩擦力
# _air_jumps_used处理多段跳
var _fighter
var _environment: FoundationFighterEnvironment
var _grounded: bool = false
var _queued_jump_axis: float = 0.0
var _queued_jump_facing: int = 1
var _jump_air_locked: bool = false
var _air_jumps_used: int = 0
var _juggle_gravity_active: bool = false
var _juggle_gravity_base_scale: float = 1.0
var _juggle_air_hit_count: int = 0
var _juggle_airborne_frames: int = 0


## 绑定 fighter 与环境资源，并应用 CharacterBody2D 接触参数。
func setup(fighter, environment: FoundationFighterEnvironment) -> void:
	_fighter = fighter
	_environment = environment
	_fighter.floor_snap_length = _environment.floor_snap_length
	_fighter.safe_margin = _environment.safe_margin
	refresh_snapshot()


## 在状态机处理前刷新 grounded 只读快照与空中跳跃次数。
func refresh_snapshot() -> void:
	_grounded = _is_floor_contact()
	if _grounded:
		_air_jumps_used = 0
		_reset_juggle_gravity()


## 返回上一物理步骤后的落地状态。
func is_grounded() -> bool:
	return _grounded


## 返回 fighter 当前速度。
func get_velocity() -> Vector2:
	return _fighter.velocity


## 返回当前剩余空中跳跃是否允许进入二段跳。
func can_double_jump() -> bool:
	return not _grounded and _air_jumps_used < _environment.max_air_jumps


## 将 fighter 速度立即清零，并清除跳跃轨迹锁定。
func stop() -> void:
	_fighter.velocity = Vector2.ZERO
	_jump_air_locked = false
	_air_jumps_used = 0
	_reset_juggle_gravity()


## 只停止水平速度，保留垂直重力流程。
func stop_horizontal() -> void:
	_fighter.velocity.x = 0.0


## 缓存起跳瞬间的世界方向与当前朝向，避免预备帧或换边改变跳跃轨迹。
func queue_fighting_game_jump(horizontal_axis: float) -> void:
	_queued_jump_axis = signf(horizontal_axis)
	_queued_jump_facing = _fighter.facing_direction
	_fighter.velocity.x = move_toward(
		_fighter.velocity.x,
		0.0,
		_environment.ground_friction * float(_environment.jump_start_duration_frames) / float(Engine.physics_ticks_per_second)
	)


## 按缓存方向启动垂直、前跳或后跳，并在空中锁定水平惯性。
func launch_fighting_game_jump() -> void:
	var jump_x_speed := 0.0
	var jump_y_speed := _environment.jump_neutral_speed
	if not is_zero_approx(_queued_jump_axis):
		var is_forward_jump := _queued_jump_axis == float(_queued_jump_facing)
		jump_x_speed = _environment.jump_forward_x_speed if is_forward_jump else _environment.jump_back_x_speed
		jump_y_speed = _environment.jump_forward_speed if is_forward_jump else _environment.jump_back_speed
	_jump_air_locked = true
	_fighter.velocity.x = _queued_jump_axis * jump_x_speed
	_fighter.velocity.y = -jump_y_speed
	_grounded = false


## 消耗一次空中跳跃，并按当前输入刷新二段跳轨迹。
func launch_double_jump(horizontal_axis: float) -> void:
	if not can_double_jump():
		return
	_air_jumps_used += 1
	var jump_axis := signf(horizontal_axis)
	var jump_x_speed := 0.0
	if not is_zero_approx(jump_axis):
		var is_forward_jump := jump_axis == float(_fighter.facing_direction)
		var base_x_speed := _environment.jump_forward_x_speed if is_forward_jump else _environment.jump_back_x_speed
		jump_x_speed = base_x_speed * _environment.double_jump_x_speed_ratio
	_jump_air_locked = true
	_fighter.velocity.x = jump_axis * jump_x_speed
	_fighter.velocity.y = -_environment.jump_neutral_speed * _environment.double_jump_y_speed_ratio
	_grounded = false


## 执行地面状态的一帧移动；前进与后退使用不同目标速度。
func step_grounded(horizontal_axis: float, delta: float) -> void:
	_apply_gravity(delta)
	if absf(horizontal_axis) > 0.01:
		var moving_forward := signf(horizontal_axis) == float(_fighter.facing_direction)
		var speed_ratio := 1.0 if moving_forward else _environment.back_walk_speed_ratio
		var target_speed := horizontal_axis * _environment.walk_speed * speed_ratio
		_fighter.velocity.x = move_toward(_fighter.velocity.x, target_speed, _environment.ground_accel * delta)
	else:
		_apply_ground_friction(delta)
	_move_body()
	if _grounded:
		_jump_air_locked = false


## 执行起跳准备的一帧地面制动，不在预备帧继续改变已缓存的起跳方向。
func step_jump_start(delta: float) -> void:
	_apply_gravity(delta)
	_apply_ground_friction(delta)
	_move_body()


## 执行上升、二段跳或下落状态的一帧格斗游戏式空中运动。
func step_airborne(delta: float) -> void:
	_apply_gravity(delta)
	if not _jump_air_locked:
		_fighter.velocity.x = move_toward(_fighter.velocity.x, 0.0, _environment.air_friction * delta)
	_move_body()


## 使用 FrayAttackAttribute 的 lunge 数据推进地面攻击移动。
func step_ground_attack(attribute: FrayAttackAttribute, elapsed_frames: int, delta: float) -> void:
	_apply_gravity(delta)
	if elapsed_frames <= attribute.lunge_frames:
		_fighter.velocity.x = float(_fighter.facing_direction) * attribute.lunge_speed
	else:
		_apply_ground_friction(delta)
	_move_body()


## 进入冲刺时写入初始速度，避免首帧从静止瞬间跳到最大速度。
func start_ground_dash(world_direction: int, speed: float) -> void:
	var direction := 1 if world_direction >= 0 else -1
	_fighter.velocity.x = float(direction) * speed * _environment.dash_initial_speed_ratio
	if _is_floor_contact() and _fighter.velocity.y > 0.0:
		_fighter.velocity.y = 0.0


## 按冲刺阶段加速并在收尾主动制动；世界方向由状态 enter 时锁定。
func step_dash_world(
	world_direction: int,
	speed: float,
	elapsed_frames: int,
	duration_frames: int,
	delta: float
) -> void:
	_apply_gravity(delta)
	var phase := clampf(float(elapsed_frames) / float(maxi(duration_frames, 1)), 0.0, 1.0)
	var target_speed := speed
	var acceleration := _environment.dash_accel
	if phase >= _environment.dash_brake_start_ratio:
		var brake_phase := inverse_lerp(_environment.dash_brake_start_ratio, 1.0, phase)
		target_speed = lerpf(speed, speed * _environment.dash_exit_speed_ratio, brake_phase)
		acceleration = _environment.dash_brake
	var direction := 1 if world_direction >= 0 else -1
	var target_velocity := float(direction) * target_speed
	if elapsed_frames >= duration_frames:
		# 配置项描述的是“最后一帧实际保留速度”；不能只把它当作 move_toward 的目标，
		# 否则短 Dash 会因制动时间不足而带着远高于配置值的残余速度退出。
		_fighter.velocity.x = target_velocity
	else:
		_fighter.velocity.x = move_toward(_fighter.velocity.x, target_velocity, acceleration * delta)
	_move_body()


## 使用攻击资源启动受击击退；命中前已浮空时读取 airborne_launch_y_velocity。
## airborne_hit_count 来自当前 ComboContext，只用于共享重力缩放，不复制攻击数值。
func start_hit_reaction(
	attribute: FrayAttackAttribute,
	defender_was_airborne: bool,
	airborne_hit_count: int = 0
) -> void:
	_jump_air_locked = false
	_fighter.velocity.x = -float(_fighter.facing_direction) * attribute.knockback
	var launch_velocity := attribute.get_launch_y_velocity(defender_was_airborne)
	if not is_zero_approx(launch_velocity):
		_fighter.velocity.y = launch_velocity
	elif not defender_was_airborne and _fighter.velocity.y > 0.0:
		_fighter.velocity.y = 0.0
	if defender_was_airborne or launch_velocity < 0.0:
		_begin_juggle_gravity(attribute.gravity_scale_on_hit, airborne_hit_count)


## 使用攻击资源启动格挡推退。
func start_block_reaction(attribute: FrayAttackAttribute) -> void:
	_jump_air_locked = false
	_fighter.velocity.x = -float(_fighter.facing_direction) * attribute.knockback * _environment.block_pushback_ratio
	if _fighter.velocity.y > 0.0:
		_fighter.velocity.y = 0.0


## 使用攻击资源启动倒地运动，并保留命中前姿态与空中命中计数。
func start_knockdown(
	attribute: FrayAttackAttribute,
	defender_was_airborne: bool = false,
	airborne_hit_count: int = 0
) -> void:
	start_hit_reaction(attribute, defender_was_airborne, airborne_hit_count)


## 推进受击、格挡或 KO 状态的一帧物理。
func step_reaction(delta: float) -> void:
	_apply_gravity(delta)
	var friction := _environment.ground_reaction_friction if _is_floor_contact() else _environment.air_friction
	_fighter.velocity.x = move_toward(_fighter.velocity.x, 0.0, friction * delta)
	_move_body()


## 推进倒地状态的一帧物理。
func step_knockdown(delta: float) -> void:
	step_reaction(delta)


## 写入受身翻滚初速度。
func start_tech_roll(world_direction: int) -> void:
	start_ground_dash(world_direction, _environment.tech_roll_speed)


## 推进受身翻滚位移。
func step_tech_roll(world_direction: int, elapsed_frames: int, delta: float) -> void:
	step_dash_world(world_direction, _environment.tech_roll_speed, elapsed_frames, _environment.tech_roll_duration_frames, delta)


## 根据上升、顶点和下落阶段应用不同重力；浮空连段会随命中次数和滞空时间逐渐加速。
func _apply_gravity(delta: float) -> void:
	if not _is_floor_contact() and not _is_at_or_below_environment_floor():
		var gravity := _environment.jump_fall_gravity
		if _fighter.velocity.y < 0.0:
			gravity = _environment.jump_rise_gravity
			if absf(_fighter.velocity.y) <= _environment.apex_speed_threshold:
				gravity *= _environment.apex_gravity_multiplier
		var gravity_scale := _get_juggle_gravity_scale()
		gravity *= gravity_scale
		var fall_speed_scale := minf(gravity_scale, _environment.max_juggle_fall_speed_scale)
		_fighter.velocity.y = minf(
			_fighter.velocity.y + gravity * delta,
			_environment.max_fall_speed * fall_speed_scale
		)
		if _juggle_gravity_active:
			_juggle_airborne_frames += 1
	elif _fighter.velocity.y > 0.0:
		_fighter.velocity.y = 0.0
		_reset_juggle_gravity()


## 开始或续接浮空重力缩放；连续命中不重置已经累计的滞空时间。
func _begin_juggle_gravity(base_scale: float, airborne_hit_count: int) -> void:
	_juggle_gravity_active = true
	_juggle_gravity_base_scale = maxf(base_scale, 0.1)
	_juggle_air_hit_count = maxi(_juggle_air_hit_count, airborne_hit_count)


## 返回当前浮空重力倍率，由招式基础倍率、空中命中数和滞空时间共同决定。
func _get_juggle_gravity_scale() -> float:
	if not _juggle_gravity_active:
		return 1.0
	var followup_hits := maxi(_juggle_air_hit_count - 1, 0)
	var airborne_seconds := float(_juggle_airborne_frames) / FrayAttackAttribute.get_gameplay_frames_per_second()
	var growth := (
		float(followup_hits) * _environment.juggle_gravity_growth_per_hit
		+ airborne_seconds * _environment.juggle_gravity_growth_per_second
	)
	return minf(
		_juggle_gravity_base_scale * (1.0 + growth),
		_environment.max_juggle_gravity_scale
	)


## 落地、回合重置或强制停止时清除连续浮空重力。
func _reset_juggle_gravity() -> void:
	_juggle_gravity_active = false
	_juggle_gravity_base_scale = 1.0
	_juggle_air_hit_count = 0
	_juggle_airborne_frames = 0


## 对水平速度应用地面摩擦。
func _apply_ground_friction(delta: float) -> void:
	_fighter.velocity.x = move_toward(_fighter.velocity.x, 0.0, _environment.ground_friction * delta)


## 每帧唯一提交 move_and_slide，并处理地面修正、场地边界与快照。
func _move_body() -> void:
	_fighter.move_and_slide()
	_snap_to_environment_floor()
	_fighter.global_position.x = clampf(_fighter.global_position.x, _environment.arena_left, _environment.arena_right)
	refresh_snapshot()


## 判断角色是否通过物理碰撞或环境地面坐标保持接地。
## 负向垂直速度表示本帧已被 launcher 推离地面，不能沿用上次 move_and_slide 的旧 floor 标记。
func _is_floor_contact() -> bool:
	if _fighter.velocity.y < 0.0:
		return false
	if _fighter.is_on_floor():
		return true
	return _fighter.global_position.y >= _environment.floor_y - FLOOR_CONTACT_EPSILON


## 判断角色是否已经到达或低于环境地面。
func _is_at_or_below_environment_floor() -> bool:
	return _fighter.global_position.y >= _environment.floor_y and _fighter.velocity.y >= 0.0


## 修正高速下落或场景误差导致的轻微穿地。
func _snap_to_environment_floor() -> void:
	if _fighter.global_position.y <= _environment.floor_y:
		return
	_fighter.global_position.y = _environment.floor_y
	if _fighter.velocity.y > 0.0:
		_fighter.velocity.y = 0.0
