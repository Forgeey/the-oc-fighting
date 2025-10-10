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

	# 目前检测到的是hurtbox，攻击框返回false，意味着不允许其他判定框作用于攻击框
	# 导致攻击框源不会收到攻击框区域进入判定框的信号
	return false
