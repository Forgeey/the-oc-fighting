class_name FighterMoveEnv
extends Resource

## 定义角色移动的物理环境

## 移动物理
@export_group("Walk")
## 前进加速度
@export var fwalk_accel = 2100
## 后退加速度
@export var bwalk_accel = 2200
## 前进最大速度
@export var fwalk_speed = 230
## 后退最大速度
@export var bwalk_speed = 180
## 移动停止加速度
@export var swalk_accel = 2400

## 冲刺物理
@export_group("Dash")
## 前冲加速度
@export var fdash_accel = 5200
## 后冲加速度
@export var bdash_accel = 5000
## 前冲起手帧最大速度
@export var fdash_start_speed = 370
## 后冲起手帧最大速度
@export var bdash_start_speed = 305
## 前冲持续帧最大速度
@export var fdash_speed = 570
## 后冲持续帧最大速度
@export var bdash_speed = 470
## 前冲持续物理帧
@export var fdash_frame = 12
## 后冲持续物理帧
@export var bdash_frame = 10
## 冲刺停止加速度
@export var sdash_accel = 6800
## 主动减速时机帧数倍率 
@export var sdash_frame_ratio = 0.72
## 冲刺最后一帧速度比率
@export var sdash_speed_ratio = 0.18

## 跳跃物理
@export_group("Jump")
## 起跳帧数
@export var jump_start_frame = 4
## 垂直跳垂直初速度
@export var jump_vspeed = 890
## 前跳垂直初速度
@export var fjump_vspeed= 860
## 后跳垂直初速度
@export var bjump_vspeed = 870
## 前跳水平初速度
@export var fjump_hspeed= 285
## 后跳水平初速度
@export var bjump_hspeed = 245
## 多段跳垂直速度倍率
@export var djump_vspeed_ratio = 0.6
## 多段跳水平速度倍率
@export var djump_hspeed_ratio = 0.7
## 跳跃顶点区间垂直速度阈值
@export var hspeed_threshold = 120
## 跳跃顶点区间重力倍率
@export var threshold_gravity_ratio = 0.7

## 落地物理
## 落地硬直摩擦
@export var land_accel = 6800
## 落地硬直帧数
@export var land_frame = 6

## 重力物理
@export_group("Gravity")
## 上升阶段重力
@export var jump_gravity = 2250
## 下落阶段重力
@export var fall_gravity = 3250
## 最大下落速度
@export var fall_speed = 1150

## 地图物理
@export_group("Arena")
## 贴地吸附物理
@export var floor_snap_length = 8
## 轻微穿透修正距离
@export var safe_margin = 0.05
## 地图左边界
@export var arena_left: float = 48.0
## 地图右边界
@export var arena_right: float = 1232.0
