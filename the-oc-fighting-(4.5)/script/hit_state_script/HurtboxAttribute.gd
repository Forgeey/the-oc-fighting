@tool
extends FrayHitboxAttribute
class_name HurtboxAttribute

# 受击数值


# 受击框用蓝色表示
func _get_color_impl() -> Color:
	return Color(0, 0, 255, 0.5)

# 接收另一个FrayHitbox的FrayAttribute，进行判断返回是否可以允许检测，默认为true
func _allows_detection_of_impl(other_attribute: FrayHitboxAttribute) -> bool:
	if other_attribute is HurtboxAttribute:
		return false
	return true
