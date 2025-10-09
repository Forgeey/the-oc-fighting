@tool
extends FrayHitboxAttribute
class_name AttackAttribute

# 设置一个独特的颜色用于调试时区分
func _get_color_impl() -> Color:
	return Color(255, 0, 0, 0.5)

# 定义核心规则：这个攻击框应该检测谁？
func _allows_detection_of_impl(other_attribute: FrayHitboxAttribute) -> bool:
	# 这里应该有问题，应该需要进行同源检测？但同源检测的代码在FrayHitbox脚本中的can_detected()中。
	# 如果碰到的也是玩家自己的攻击，则不检测（防止自己的拳头打自己的另一个拳头）
	if other_attribute is AttackAttribute:
		return false
	# 如果碰到的是玩家自己的受击框，也不检测（防止打自己）
	if other_attribute is HurtboxAttribute:
		return false

	# 除此之外，允许检测所有其他东西（比如敌人的受击框）
	return true
