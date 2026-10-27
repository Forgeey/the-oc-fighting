class_name FighterMovement
extends RefCounted
## 统一处理角色地面运动并预留其它移动接口。

var move_env: FighterMoveEnv
var fighter: CharacterBody2D
var _grounded: bool = false
var _moving: bool = false
var _movement_locked: bool = false
var _hit: bool = false
var _arean_left: bool = false
var _arean_right: bool = false
var _input_axis: float = 0.0
var _facing: int = 1
var _landed: bool = false


#region 初始化与生命周期

## 绑定角色与移动参数并初始化运动状态。
func init_movement(environment: FighterMoveEnv, player: CharacterBody2D) -> void:
	move_env = environment
	fighter = player
	fighter.floor_snap_length = float(move_env.floor_snap_length)
	fighter.safe_margin = move_env.safe_margin
	reset()

## 重置角色速度和运动标记。
func reset() -> void:
	fighter.velocity = Vector2.ZERO
	_input_axis = 0.0
	_grounded = fighter.is_on_floor()
	_moving = false
	_movement_locked = false
	_hit = false
	_landed = false
	_arean_left = false
	_arean_right = false

## 预留统一移动更新接口，当前未实现。
func step(delta: float, input_axis: float, grounded: bool) -> void:
	pass

## 按输入更新地面加速度、重力和碰撞移动。
func step_grounded(input_axis: float, delta: float) -> void:
	_input_axis = input_axis
	if _movement_locked or absf(_input_axis) <= 0.1:
		_input_axis = 0.0
	if is_zero_approx(_input_axis):
		_apply_ground_friction(delta)
	else:
		_apply_accel(delta)
	_apply_gravity(delta)
	_apply_motion(delta)

## 预留空中移动更新接口，当前未实现。
func step_airborne(input_axis: float, delta: float) -> void:
	pass

## 预留受限移动更新接口，当前未实现。
func step_restricted(delta: float) -> void:
	pass

#endregion


#region 基础物理读取

## 按升降阶段和顶点区间计算重力。
func _get_gravity() -> float:
	if _hit:
		return float(move_env.fall_gravity)
	var gravity := float(move_env.jump_gravity if is_rising() else move_env.fall_gravity)
	if absf(fighter.velocity.y) <= move_env.hspeed_threshold:
		gravity *= move_env.threshold_gravity_ratio
	return gravity

## 按前进或后退输入读取水平加速度。
func _get_accel() -> float:
	return float(move_env.fwalk_accel if is_forward_input(_input_axis) else move_env.bwalk_accel)

## 返回角色当前水平速度。
func _get_hspeed() -> float:
	return fighter.velocity.x

## 返回角色当前垂直速度。
func _get_vspeed() -> float:
	return fighter.velocity.y

## 返回移动模块保存的水平输入。
func _get_input_axis() -> float:
	return _input_axis

## 返回移动模块保存的角色朝向。
func _get_facing() -> int:
	return _facing

## 应用重力并限制最大下落速度。
func _apply_gravity(delta: float) -> void:
	if not fighter.is_on_floor():
		fighter.velocity.y = minf(fighter.velocity.y + _get_gravity() * delta, float(move_env.fall_speed))
	elif fighter.velocity.y > 0.0:
		fighter.velocity.y = 0.0

## 按当前输入将水平速度趋近目标速度。
func _apply_accel(delta: float) -> void:
	var speed := float(move_env.fwalk_speed if is_forward_input(_input_axis) else move_env.bwalk_speed)
	var target_speed := _input_axis * speed
	fighter.velocity.x = move_toward(fighter.velocity.x, target_speed, _get_accel() * delta)

## 按地面减速度使水平速度趋近零。
func _apply_ground_friction(delta: float) -> void:
	fighter.velocity.x = move_toward(fighter.velocity.x, 0.0, float(move_env.swalk_accel) * delta)

## 预留空中阻力接口，当前未实现。
func _apply_air_friction(input_axis: float, delta: float) -> void:
	pass

## 执行碰撞移动并更新接地和边界标记。
func _apply_motion(_delta: float) -> void:
	var was_grounded := _grounded
	# 唯一一次真实运动。velocity 已是像素/秒，不要再乘 delta。
	fighter.move_and_slide()
	clamp_to_arena()
	resolve_wall_collision()
	_grounded = fighter.is_on_floor()
	_landed = not was_grounded and _grounded
	_moving = not is_zero_approx(fighter.velocity.x)

#endregion


#region 行走与转身

## 判断输入方向是否朝向角色前方。
func is_forward_input(input_axis: float) -> bool:
	return input_axis * _facing > 0.1

## 判断输入方向是否朝向角色后方。
func is_backward_input(input_axis: float) -> bool:
	return input_axis * _facing < -0.1

## 预留开始行走接口，当前未实现。
func start_walk(input_axis: float, delta: float) -> void:
	pass

## 预留停止行走接口，当前未实现。
func stop_walk(delta: float) -> void:
	pass

## 直接设置角色水平速度。
func set_horizontal_speed(speed: float) -> void:
	fighter.velocity.x = speed

## 立即清零水平速度和移动标记。
func stop_horizontal() -> void:
	fighter.velocity.x = 0.0
	_moving = false

## 预留自动朝向更新接口，当前未实现。
func update_facing(input_axis: float, opponent_position = null) -> void:
	pass

## 保存角色的移动朝向。
func set_facing(direction: int) -> void:
	_facing = direction

#endregion


#region 冲刺

## 预留前冲状态查询，当前返回 false。
func is_forward_dashing() -> bool:
	# TODO: 后续冲刺阶段实现。
	return false

## 预留后冲状态查询，当前返回 false。
func is_backward_dashing() -> bool:
	# TODO: 后续冲刺阶段实现。
	return false

## 预留前冲启动接口，当前未实现。
func start_fdash(forward: bool = true) -> void:
	pass

## 预留前冲更新接口，当前未实现。
func step_fdash(delta: float) -> void:
	pass

## 预留后冲启动接口，当前未实现。
func start_bdash(forward: bool = true) -> void:
	pass

## 预留后冲更新接口，当前未实现。
func step_bdash(delta: float) -> void:
	pass

## 预留冲刺结束接口，当前未实现。
func stop_dash() -> void:
	pass

## 预留冲刺取消接口，当前未实现。
func cancel_dash() -> void:
	pass

#endregion


#region 跳跃与空中移动

## 判断角色是否在空中上升。
func is_rising() -> bool:
	return not fighter.is_on_floor() and fighter.velocity.y < 0.0

## 判断角色是否在空中下落。
func is_falling() -> bool:
	return not fighter.is_on_floor() and fighter.velocity.y > 0.0

## 预留跳跃启动接口，当前未实现。
func start_jump(horizontal_direction: float = 0.0) -> void:
	pass

## 预留多段跳启动接口，当前未实现。
func start_double_jump(horizontal_direction: float = 0.0) -> void:
	pass

## 预留跳跃更新接口，当前未实现。
func step_jump(delta: float) -> void:
	pass

#endregion


#region 落地、边界与碰撞

## 判断本次移动是否刚从空中落地。
func has_landed() -> bool:
	return _landed

## 预留落地硬直更新接口，当前未实现。
func step_landing(delta: float) -> void:
	pass

## 调用角色的地面吸附处理。
func apply_floor_snap() -> void:
	fighter.apply_floor_snap()

## 将角色限制在场地水平边界内。
func clamp_to_arena() -> void:
	fighter.global_position.x = clampf(fighter.global_position.x, move_env.arena_left, move_env.arena_right)
	_arean_left = fighter.global_position.x <= move_env.arena_left + 0.1
	_arean_right = fighter.global_position.x >= move_env.arena_right - 0.1
	if (_arean_left and fighter.velocity.x < 0.0) or (_arean_right and fighter.velocity.x > 0.0):
		fighter.velocity.x = 0.0

## 清除朝墙壁内部移动的水平速度。
func resolve_wall_collision() -> void:
	if fighter.is_on_wall() and fighter.velocity.x * fighter.get_wall_normal().x < 0.0:
		fighter.velocity.x = 0.0

#endregion


#region 受击与外力

## 预留击退状态查询，当前返回 false。
func has_kickback_velocity() -> bool:
	# TODO: 后续受击阶段实现，不把普通行走速度误判为击退。
	return false

## 预留水平击退接口，当前未实现。
func apply_kickback_hspeed(kickback_hspeed: Vector2) -> void:
	pass

## 预留垂直击退接口，当前未实现。
func apply_kickback_vspeed(kickback_vspeed: Vector2) -> void:
	pass

## 预留击退清理接口，当前未实现。
func clear_kickback_velocity() -> void:
	pass

#endregion


#region 状态查询

## 返回最近一次移动后的接地标记。
func _is_grounded() -> bool:
	return _grounded

## 返回当前水平移动标记。
func is_moving() -> bool:
	return _moving

## 返回当前移动锁定标记。
func is_movement_locked() -> bool:
	return _movement_locked

## 返回当前受击标记。
func is_hit() -> bool:
	return _hit

## 返回角色是否处于场地左边界。
func is_at_left_boundary() -> bool:
	return _arean_left

## 返回角色是否处于场地右边界。
func is_at_right_boundary() -> bool:
	return _arean_right

#endregion
