@tool
extends FrayHitboxAttribute
class_name HurtboxAttribute

# 受击框用蓝色表示
func _get_color_impl() -> Color:
	return Color(0, 0, 255, 0.5)

# 受击框的规则：它不主动“检测”别人，所以可以直接返回false
# 真正重要的是它被别人检测时的身份
func _allows_detection_of_impl(other_attribute: FrayHitboxAttribute) -> bool:
	return false
