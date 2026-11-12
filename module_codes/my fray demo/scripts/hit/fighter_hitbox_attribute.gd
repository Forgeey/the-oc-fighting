@tool
class_name FighterHitboxAttribute
extends FrayHitboxAttribute
## 统一配置框类型、检测关系和调试颜色；攻击类型额外使用只读帧窗口。

enum Kind { HURT, ATTACK, PUSH }

## 指定本逻辑框的用途。
@export var kind: Kind = Kind.HURT
## 仅 ATTACK 使用；Hurt／Push 不参与动作时长或攻击窗口。
@export_group("Attack Timing")
@export_range(0, 600) var startup_frames: int = 10
@export_range(0, 600) var active_frames: int = 4
@export_range(0, 600) var recovery_frames: int = 10


func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames if kind == Kind.ATTACK else 0


## 有效区间为 [startup, startup+active)，运行进度由各状态实例保存。
func is_active_at(frame: int) -> bool:
	return kind == Kind.ATTACK and frame >= startup_frames and frame < startup_frames + active_frames


## 为判定调试显示用途对应的颜色。
func _get_color_impl() -> Color:
	match kind:
		Kind.HURT:
			return Color(0.15, 0.85, 0.3, 0.4)
		Kind.ATTACK:
			return Color(1.0, 0.2, 0.15, 0.45)
		Kind.PUSH:
			return Color(0.2, 0.45, 1.0, 0.4)
	return Color.TRANSPARENT


## 攻击仅检测受击框，推挤仅检测推挤框，同源过滤继续交给 Fray。
func _allows_detection_of_impl(other: FrayHitboxAttribute) -> bool:
	if not other is FighterHitboxAttribute:
		return false
	return (kind == Kind.ATTACK and other.kind == Kind.HURT
		or kind == Kind.PUSH and other.kind == Kind.PUSH)
