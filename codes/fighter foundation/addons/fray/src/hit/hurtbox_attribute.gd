@tool
@icon("res://addons/fray/assets/icons/hit_attribute.svg")
class_name FrayHurtboxAttribute
extends FrayHitboxAttribute
## Generic hurtbox attribute for Fray hitboxes.
##
## Hurtboxes are intended to be detected by attack hitboxes, not to initiate
## detection themselves.

## Debug color used by Fray hitbox collision shapes.
@export var color: Color = Color(0.15, 0.65, 1.0, 0.34)


func _get_color_impl() -> Color:
	return color


func _allows_detection_of_impl(_attribute: FrayHitboxAttribute) -> bool:
	return false
