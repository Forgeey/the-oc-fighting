@tool
extends FrayHitboxAttribute
class_name AttackAttribute

# 设置一个独特的颜色用于调试时区分
func _get_color_impl() -> Color:
	return Color(255, 0, 0, 0.5)

# 定义核心规则：这个攻击框应该检测谁？
func _allows_detection_of_impl(other_attribute: FrayHitboxAttribute) -> bool:
	if other_attribute is AttackAttribute:
		return true

	# 除此之外，允许检测所有其他东西（比如敌人的受击框）
	return false
