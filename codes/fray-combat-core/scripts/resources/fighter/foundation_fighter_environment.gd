class_name FoundationFighterEnvironment
extends Resource
## Fighter foundation 的环境与角色运动物理参数。
##
## 本资源统一提供移动、二段跳、受身和恢复流程的物理参数。
## 攻击/受击数值不在这里重复定义，仍只来自 FrayAttackAttribute。

@export_group("Ground")
## walk forwards，地面前进行走最大速度，单位为像素/秒。
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var walk_speed: float = 230.0

## walk backwards，后退行走相对前进速度的倍率。
@export_range(0.1, 1.0, 0.05) var back_walk_speed_ratio: float = 0.78

## walk accel，地面行走加速度，单位为像素/秒平方。
@export_range(1.0, 10000.0, 1.0, "suffix:px/s²") var ground_accel: float = 2100.0

## walk friction，无水平输入时的地面摩擦，单位为像素/秒平方。
@export_range(1.0, 10000.0, 1.0, "suffix:px/s²") var ground_friction: float = 2400.0

@export_group("Dash")
## 前冲最大速度。
@export_range(1.0, 3000.0, 1.0, "suffix:px/s") var dash_forward_speed: float = 570.0

## 后撤最大速度。
@export_range(1.0, 3000.0, 1.0, "suffix:px/s") var dash_back_speed: float = 475.0

## 前冲固定持续物理帧数。
@export_range(1, 30, 1, "suffix:F") var dash_forward_duration_frames: int = 12

## 后撤固定持续物理帧数。
@export_range(1, 30, 1, "suffix:F") var dash_back_duration_frames: int = 10

## 冲刺进入帧相对最大速度的比例。
@export_range(0.1, 1.0, 0.05) var dash_initial_speed_ratio: float = 0.65

## 冲刺前段加速度。
@export_range(1.0, 15000.0, 1.0, "suffix:px/s²") var dash_accel: float = 5200.0

## 冲刺收尾制动加速度。
@export_range(1.0, 15000.0, 1.0, "suffix:px/s²") var dash_brake: float = 6800.0

## 从冲刺总时长的此比例开始主动减速。
@export_range(0.5, 0.95, 0.05) var dash_brake_start_ratio: float = 0.72

## 冲刺最后一帧保留的目标速度比例。
@export_range(0.0, 1.0, 0.05) var dash_exit_speed_ratio: float = 0.18

@export_group("Jump")
## 起跳准备持续的固定物理帧数。
@export_range(0, 10, 1, "suffix:F") var jump_start_duration_frames: int = 4

## 垂直跳的上升初速度绝对值。
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var jump_neutral_speed: float = 890.0

## 前跳的上升初速度绝对值。
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var jump_forward_speed: float = 855.0

## 后跳的上升初速度绝对值。
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var jump_back_speed: float = 870.0

## 前跳锁定的水平速度。
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var jump_forward_x_speed: float = 285.0

## 后跳锁定的水平速度。
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var jump_back_x_speed: float = 245.0

## 每次离地允许使用的额外空中跳跃次数；1 即传统二段跳。
@export_range(0, 3, 1) var max_air_jumps: int = 1

## 二段跳垂直速度相对普通垂直跳的倍率。
@export_range(0.1, 1.5, 0.05) var double_jump_y_speed_ratio: float = 0.9

## 二段跳水平速度相对普通前后跳的倍率。
@export_range(0.0, 1.5, 0.05) var double_jump_x_speed_ratio: float = 0.9

## 落地恢复持续的固定物理帧数。
@export_range(0, 15, 1, "suffix:F") var land_duration_frames: int = 5

## 进入跳跃顶点区间的垂直速度阈值。
@export_range(0.0, 500.0, 1.0, "suffix:px/s") var apex_speed_threshold: float = 120.0

## 跳跃顶点区间的重力倍率。
@export_range(0.25, 1.0, 0.05) var apex_gravity_multiplier: float = 0.75

@export_group("Defense And Recovery")
## 受身翻滚速度。
@export_range(1.0, 3000.0, 1.0, "suffix:px/s") var tech_roll_speed: float = 490.0

## 受身翻滚持续帧数。
@export_range(1, 60, 1, "suffix:F") var tech_roll_duration_frames: int = 14

## 未提供倒地时长的攻击资源所使用的默认倒地帧数。
@export_range(1, 240, 1, "suffix:F") var default_knockdown_duration_frames: int = 42

## 起身恢复持续帧数。
@export_range(1, 120, 1, "suffix:F") var wakeup_duration_frames: int = 18

## 格挡推退相对攻击 knockback 的倍率。
@export_range(0.0, 1.0, 0.05) var block_pushback_ratio: float = 0.35

## 地面受击/格挡/倒地的水平减速。
@export_range(1.0, 10000.0, 1.0, "suffix:px/s²") var ground_reaction_friction: float = 1500.0

@export_group("Gravity")
## 上升阶段重力。
@export_range(1.0, 10000.0, 1.0, "suffix:px/s²") var jump_rise_gravity: float = 2550.0

## 下落阶段重力；高于上升重力可获得更利落的格斗游戏跳跃弧线。
@export_range(1.0, 10000.0, 1.0, "suffix:px/s²") var jump_fall_gravity: float = 3250.0

## 最大下落速度。
@export_range(1.0, 3000.0, 1.0, "suffix:px/s") var max_fall_speed: float = 1180.0

## 每次后续空中命中增加的浮空重力比例；落地后重置。
@export_range(0.0, 1.0, 0.01) var juggle_gravity_growth_per_hit: float = 0.16

## 每持续浮空一秒增加的浮空重力比例，避免长时间悬空。
@export_range(0.0, 2.0, 0.05) var juggle_gravity_growth_per_second: float = 0.35

## 浮空连段允许达到的最大重力倍率。
@export_range(1.0, 5.0, 0.05) var max_juggle_gravity_scale: float = 2.4

## 浮空连段允许达到的最大下落速度倍率。
@export_range(1.0, 3.0, 0.05) var max_juggle_fall_speed_scale: float = 1.5

@export_group("Air Momentum")
## 非普通跳跃锁定轨迹使用的空中水平摩擦。
@export_range(0.0, 5000.0, 1.0, "suffix:px/s²") var air_friction: float = 460.0

@export_group("Character Contact")
## CharacterBody2D 的贴地吸附距离。避免运动中产生轻微浮空或不稳定状态。
@export_range(0.0, 64.0, 0.5, "suffix:px") var floor_snap_length: float = 8.0

## CharacterBody2D 的安全边距。
# 检测角色是否轻微穿透、重叠或接近其他碰撞体时，应该提前多少距离进行修正。
@export_range(0.001, 1.0, 0.001, "suffix:px") var safe_margin: float = 0.05

@export_group("Arena")
# 角色位置限制在一定范围内，不会飞出场地。
## fighter 原点可到达的最左位置。
@export var arena_left: float = 48.0

## fighter 原点可到达的最右位置。
@export var arena_right: float = 1232.0

## fighter 站立时原点对应的地面高度。
@export var floor_y: float = 650.0


## 校验所有环境与移动参数；返回空数组表示配置可用。
# 发现错误时，不让Fighter继续初始化
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if walk_speed <= 0.0 or back_walk_speed_ratio <= 0.0:
		errors.append("行走速度与后退倍率必须大于 0。")
	if ground_accel <= 0.0 or ground_friction <= 0.0:
		errors.append("地面加速度与摩擦必须大于 0。")
	if dash_forward_speed <= walk_speed or dash_back_speed <= walk_speed:
		errors.append("前冲和后撤速度都必须大于 walk_speed。")
	if dash_forward_duration_frames < 1 or dash_back_duration_frames < 1:
		errors.append("冲刺持续帧数必须至少为 1。")
	if dash_brake_start_ratio <= 0.0 or dash_brake_start_ratio >= 1.0:
		errors.append("dash_brake_start_ratio 必须位于 0 与 1 之间。")
	if jump_start_duration_frames < 0 or land_duration_frames < 0:
		errors.append("起跳准备与落地恢复帧数不能小于 0。")
	if jump_neutral_speed <= 0.0 or jump_forward_speed <= 0.0 or jump_back_speed <= 0.0:
		errors.append("跳跃垂直速度必须大于 0。")
	if max_air_jumps < 0 or double_jump_y_speed_ratio <= 0.0 or double_jump_x_speed_ratio < 0.0:
		errors.append("空中跳跃次数与二段跳倍率配置无效。")
	if tech_roll_speed <= 0.0 or tech_roll_duration_frames < 1:
		errors.append("受身速度与持续帧必须有效。")
	if default_knockdown_duration_frames < 1 or wakeup_duration_frames < 1:
		errors.append("倒地与起身恢复帧必须至少为 1。")
	if block_pushback_ratio < 0.0 or block_pushback_ratio > 1.0 or ground_reaction_friction <= 0.0:
		errors.append("格挡推退倍率必须位于 0～1，反应摩擦必须大于 0。")
	if jump_rise_gravity <= 0.0 or jump_fall_gravity <= 0.0 or max_fall_speed <= 0.0:
		errors.append("重力与最大下落速度必须大于 0。")
	if juggle_gravity_growth_per_hit < 0.0 or juggle_gravity_growth_per_second < 0.0:
		errors.append("浮空重力增长参数不能小于 0。")
	if max_juggle_gravity_scale < 1.0 or max_juggle_fall_speed_scale < 1.0:
		errors.append("浮空最大重力与下落速度倍率不能小于 1。")
	if floor_snap_length < 0.0 or safe_margin <= 0.0:
		errors.append("贴地距离不能小于 0，安全边距必须大于 0。")
	if arena_left >= arena_right:
		errors.append("arena_left 必须小于 arena_right。")
	return errors
