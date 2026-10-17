@tool
@icon("res://addons/fray/assets/icons/hit_attribute.svg")
class_name CombatHurtboxAttribute
extends FrayHitboxAttribute
## Project-owned defender collision data used by the combat resolver.
##
## Fray only supplies the generic FrayHitboxAttribute contract. Keeping this
## concrete type in scripts/ prevents the project from depending on custom files
## inside addons/fray.

## Debug/editor tint used for hurtbox collision shapes.
@export var color: Color = Color(0.15, 0.65, 1.0, 0.34)


func _get_color_impl() -> Color:
	return color


func _allows_detection_of_impl(attribute: FrayHitboxAttribute) -> bool:
	return attribute is CombatAttackAttribute
