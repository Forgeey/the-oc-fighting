@tool
class_name FighterHitboxAttribute
extends FrayHitboxAttribute
## 区分战斗框的检测关系和调试颜色，不定义伤害或受击结果。

enum Kind { HURT, ATTACK, PUSH }

## 指定本逻辑框的用途。
@export var kind: Kind = Kind.HURT


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
