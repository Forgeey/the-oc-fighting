class_name Movement
extends RefCounted

## 角色移动模块的接口骨架
##
## 这里仅定义传统横板 2D 格斗游戏常用的移动职责，不包含任何具体实现
## 具体的角色位置、碰撞和动画同步，应由 Fighter/CharacterBody2D 负责接入

var move_env: MoveEnvironment = MoveEnvironment.new()
var fighter
var _grounded = false
var _moving = false
var _movement_locked = false
var _hit = false
var _arean_left = false
var _arean_right = false


#region 初始化与生命周期

## 设置运动角色和环境物理
func init_movement(fighter) -> void:
	fighter = fighter

## 清空速度、冲刺、跳跃和受击等临时移动状态
func reset() -> void:
	pass

## 每个物理帧的统一入口；由状态机根据当前状态调用对应分支
func step(delta: float, input_axis: float, grounded: bool) -> void:
	pass

## 地面状态下的移动入口；IdleState 已预留对此函数的调用
func step_grounded(input_axis: float, delta: float) -> void:
	pass

## 空中状态下的移动入口
func step_airborne(input_axis: float, delta: float) -> void:
	pass

## 受击、倒地、起身等非自由移动状态的入口
func step_restricted(delta: float) -> void:
	pass

#endregion


#region 基础物理读取

## 读取当前重力；通常根据上升、下落和跳跃顶点区间选择不同参数
func _get_gravity():
	if _hit:
		return move_env.fall_gravity

	var gravity
	if is_rising():
		gravity = move_env.jump_gravity
	else:
		gravity = move_env.fall_gravity
	if absf(fighter.velocity.y) <= move_env.hspeed_threshold:
		gravity *= move_env.threshold_gravity_ratio
	return gravity

## 读取当前水平加速度；通常根据前进、后退、停止或冲刺阶段选择参数
func _get_accel():
	pass

## 读取当前水平速度
func _get_hspeed():
	pass

## 读取当前垂直速度
func _get_vspeed():
	pass

## 读取当前水平输入
func _get_input_axis():
	pass

## 读取角色当前朝向
func _get_facing():
	pass

## 应用重力
func _apply_gravity(delta: float) -> void:
	pass

## 按当前移动阶段应用水平加速度
func _apply_accel(delta: float) -> void:
	pass

## 对没有输入的水平速度施加停止摩擦/减速度
func _apply_ground_friction(delta: float) -> void:
	pass

## 对空中水平速度施加空中控制或空气阻力
func _apply_air_control(input_axis: float, delta: float) -> void:
	pass

## 将最终速度提交给角色，并执行 CharacterBody2D 的碰撞移动
func _apply_motion(delta: float) -> void:
	pass

## 限制角色的水平和垂直速度范围
func _clamp_velocity() -> void:
	pass

#endregion


#region 行走与转身

## 判断输入方向是前进还是后退
func is_forward_input(input_axis: float) -> bool:
	pass

func is_backward_input(input_axis: float) -> bool:
	pass

## 开始或更新普通行走；根据输入方向区分前进和后退速度
func start_walk(input_axis: float, delta: float) -> void:
	pass

## 结束行走并让角色平滑停下
func stop_walk(delta: float) -> void:
	pass

## 设置水平速度；适合状态切换、动画锁定或特殊移动使用
func set_horizontal_speed(speed: float) -> void:
	pass

## 立即停止水平速度；适合进入攻击、受击或硬直状态时使用
func stop_horizontal() -> void:
	pass

## 根据输入和对手相对位置更新角色朝向
func update_facing(input_axis: float, opponent_position = null) -> void:
	pass

## 直接设置角色朝向；direction 应为 -1 或 1
func set_facing(direction: int) -> void:
	pass

#endregion


#region 冲刺

## 判断角色当前是否处于前冲刺状态
func is_forward_dashing() -> bool:
	pass

## 判断角色当前是否处于后冲刺状态
func is_backward_dashing() -> bool:
	pass

## 启动一次前冲，并初始化冲刺阶段计时
func start_fdash(forward: bool = true) -> void:
	pass

## 更新冲刺的启动、持续和减速阶段
func step_fdash(delta: float) -> void:
	pass

## 启动一次前冲，并初始化冲刺阶段计时
func start_bdash(forward: bool = true) -> void:
	pass

## 更新冲刺的启动、持续和减速阶段
func step_bdash(delta: float) -> void:
	pass

## 结束冲刺并进入普通移动或停止阶段
func stop_dash() -> void:
	pass

## 在攻击、受击、落地或其他状态切换时取消冲刺
func cancel_dash() -> void:
	pass

#endregion


#region 跳跃与空中移动

## 判断角色是否正在上升
func is_rising() -> bool:
	pass

## 判断角色是否正在下落
func is_falling() -> bool:
	pass

## 开始垂直跳、前跳或后跳；horizontal_direction 用于决定水平初速度
func start_jump(horizontal_direction: float = 0.0) -> void:
	pass

## 执行多段跳/二段跳的检查和初速度设置
func start_double_jump(horizontal_direction: float = 0.0) -> void:
	pass

## 处理跳跃上升、跳跃顶点和下落阶段
func step_jump(delta: float) -> void:
	pass

#endregion


#region 落地、边界与碰撞

## 判断本帧是否发生了从空中到地面的转换
func has_landed() -> bool:
	pass

## 更新落地硬直
func step_landing(delta: float) -> void:
	pass

## 处理地面吸附，避免角色在斜面或微小缝隙处抖动
func apply_floor_snap() -> void:
	pass

## 根据 MoveEnvironment 的竞技场边界限制角色位置
func clamp_to_arena() -> void:
	pass

## 处理左右墙壁/边界碰撞后的速度修正
func resolve_wall_collision() -> void:
	pass

#endregion


#region 受击与外力

## 判断当前是否正在执行外部受力移动
func has_kickback_velocity() -> bool:
	pass

## 施加击退、浮空等外部速度；不应被普通行走加速度覆盖
func apply_kickback_hspeed(kickback_hspeed: Vector2) -> void:
	pass
	
## 施加击退、浮空等外部速度
func apply_kickback_vspeed(kickback_vspeed: Vector2) -> void:
	pass

## 清除击退等外部速度，恢复普通移动控制
func clear_kickback_velocity() -> void:
	pass

#endregion


#region 状态查询

## 读取角色当前是否接触地面
func _is_grounded() -> bool:
	return _grounded

## 判断是否存在水平移动
func is_moving() -> bool:
	return _moving

## 判断当前移动是否被攻击/受击/落地等状态锁定
func is_movement_locked() -> bool:
	return _movement_locked

## 判断角色是否正在被打
func is_hit() -> bool:
	return _hit

## 判断角色是否位于竞技场左边界
func is_at_left_boundary() -> bool:
	return _arean_left

## 判断角色是否位于竞技场右边界
func is_at_right_boundary() -> bool:
	return _arean_right

#endregion
