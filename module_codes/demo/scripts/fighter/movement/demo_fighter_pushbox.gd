class_name DemoFighterPushbox
extends CollisionShape2D

## 演示用推挤框：负责限制角色不出场地并分离重叠的双方。
##
## Pushbox 不参与伤害结算；伤害、受击硬直、击退等仍由 FrayAttackAttribute 提供。
## 站立配置直接取自 Pushbox 节点的 RectangleShape2D 和节点位置；蹲下和空中使用导出配置。

const SEPARATION_MARGIN := 0.05

@export_group("Crouch")
@export var crouch_size := Vector2(88.0, 58.0)
@export var crouch_offset := Vector2(0.0, -29.0)

@export_group("Air")
@export var air_size := Vector2(72.0, 80.0)
@export var air_offset := Vector2(0.0, -40.0)

var fighter: DemoFighter
var arena_left := 0.0
var arena_right := 0.0
var _rectangle: RectangleShape2D
var _stand_size := Vector2.ZERO
var _stand_offset := Vector2.ZERO


## 初始化 pushbox 并保存 fighter 与场地边界。
func setup(
	p_fighter: DemoFighter,
	p_arena_left: float,
	p_arena_right: float
) -> void:
	fighter = p_fighter
	arena_left = p_arena_left
	arena_right = p_arena_right
	_initialize_shape()
	set_pose_profile()


## 根据角色姿态切换站立、蹲下或空中的 pushbox 尺寸与偏移。
func set_pose_profile(pose: StringName = &"Stand") -> void:
	match pose:
		&"Stand":
			_rectangle.size = _stand_size
			position = _stand_offset
		&"Crouch":
			_rectangle.size = crouch_size
			position = crouch_offset
		&"Air":
			_rectangle.size = air_size
			position = air_offset


## 将角色原点的水平位置限制在场地左右边界内。
func clamp_to_arena() -> void:
	move_horizontally(0.0)


## 检测与对手 pushbox 的矩形重叠，并将墙角无法承担的位移交给另一方。
func resolve_against(opponent: DemoFighter) -> void:
	var opponent_pushbox := opponent.get_pushbox_resolver()
	var overlap := get_pushbox_rect().intersection(opponent_pushbox.get_pushbox_rect())
	if not overlap.has_area():
		return

	var push_dir := signf(fighter.global_position.x - opponent.global_position.x)
	if push_dir == 0.0:
		push_dir = 1.0 if fighter.get_instance_id() > opponent.get_instance_id() else -1.0

	var separation := overlap.size.x + SEPARATION_MARGIN
	var half_separation := separation * 0.5
	var remaining := separation
	remaining -= absf(move_horizontally(push_dir * half_separation))
	remaining -= absf(opponent_pushbox.move_horizontally(-push_dir * half_separation))

	if remaining > 0.0:
		remaining -= absf(move_horizontally(push_dir * remaining))
	if remaining > 0.0:
		opponent_pushbox.move_horizontally(-push_dir * remaining)


## 返回当前 pushbox 的世界坐标轴对齐矩形。
func get_pushbox_rect() -> Rect2:
	return Rect2(global_position - _rectangle.size * 0.5, _rectangle.size)


## 在场地内水平移动所属角色，并返回边界约束后的实际移动距离。
func move_horizontally(delta_x: float) -> float:
	var previous_x := fighter.global_position.x
	fighter.global_position.x = clampf(previous_x + delta_x, arena_left, arena_right)
	return fighter.global_position.x - previous_x


## 复制场景配置的矩形，避免两个 fighter 实例共享并互相改写 Shape2D 资源。
func _initialize_shape() -> void:
	_rectangle = (shape as RectangleShape2D).duplicate() as RectangleShape2D
	shape = _rectangle
	_stand_size = _rectangle.size
	_stand_offset = position
