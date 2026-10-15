class_name DemoFighterEnvironment
extends Resource

## Demo 角色使用的环境/运动物理参数。
##
## 这些值不属于具体攻击招式；攻击位移和受击结算仍以 FrayAttackAttribute 为准。
## 将它们做成 Resource 后，可以在检查器里快速调不同舞台/手感预设。

@export_group("Ground")
@export var walk_speed := 230.0
@export var ground_accel := 2100.0
@export var friction := 2400.0

@export_group("Dash")
@export var dash_forward_duration := 0.205
@export var dash_back_duration := 0.175
@export var dash_forward_speed := 570.0
@export var dash_back_speed := 475.0
@export_range(0.1, 1.0, 0.05) var dash_initial_speed_ratio := 0.65
@export var dash_accel := 5200.0
@export var dash_brake := 6800.0
@export_range(0.5, 0.95, 0.05) var dash_brake_start_ratio := 0.72
@export_range(0.0, 1.0, 0.05) var dash_exit_speed_ratio := 0.18

@export_group("Jump")
@export var jump_startup_time := 0.0588
@export var jump_neutral_speed := 890.0
@export var jump_forward_speed := 855.0
@export var jump_back_speed := 870.0
@export var jump_forward_x_speed := 285.0
@export var jump_back_x_speed := 245.0
@export var min_jump_rise_time := 0.09
@export var min_fall_time := 0.055
@export var landing_recovery := 0.088
@export var apex_speed_threshold := 120.0
@export_range(0.25, 1.0, 0.05) var apex_gravity_multiplier := 0.75

@export_group("Gravity")
@export var jump_rise_gravity := 2550.0
@export var jump_fall_gravity := 3250.0
@export var max_fall_speed := 1180.0

@export_group("Air Momentum")
## 非跳跃锁定轨迹受到的水平减速；普通跳跃会完整保留起跳水平惯性。
@export var air_knockback_friction := 460.0

@export_group("Knockdown")
@export var default_knockdown_time := 0.45
@export var wakeup_recovery := 0.265
@export var knockdown_friction := 1500.0
@export var tech_roll_duration := 0.205
@export var tech_roll_speed := 420.0
@export var tech_roll_brake := 1700.0

@export_group("Arena")
@export var arena_left := 64.0
@export var arena_right := 896.0
@export var floor_y := 500.0
