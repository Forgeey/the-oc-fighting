class_name FighterState
extends FrayState

var fighter: Fighter
var fighter_input: FighterInput
var controller: FrayController
var movement: FighterMovement
var hit_state_manager: FrayHitStateManager2D


## 子类覆盖此方法时应调用 super(context)。
func _ready_impl(context: Dictionary) -> void:
	fighter = context["fighter"]
	fighter_input = context["fighter_input"]
	controller = context["controller"]
	movement = context["movement"]
	hit_state_manager = context["hit_state_manager"]
