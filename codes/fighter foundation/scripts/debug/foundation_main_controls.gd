extends Node2D
## Main 学习场景的外部生命周期控制器。
##
## 这些按键只调用 FoundationFighter 的集中生命周期与外部战斗事件 API，不参与角色输入转移。

@onready var _fighter: FoundationFighter = $FighterFoundation
var _spawn_transform: Transform2D
var _paused: bool = false


## 缓存初始出生点，供 R 键回合重置。
func _ready() -> void:
	_spawn_transform = _fighter.global_transform


## 处理 Main 场景专用的 reset、lock、pause 与受击流程调试按键。
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			_paused = false
			_fighter.reset_for_round(_spawn_transform, 1)
		KEY_L:
			_fighter.set_control_locked(not _fighter.is_control_locked(), &"debug_toggle")
		KEY_P:
			_paused = not _paused
			_fighter.set_simulation_paused(_paused, false)
		KEY_H:
			_paused = not _paused
			_fighter.set_simulation_paused(_paused, true)
		KEY_1:
			_fighter.request_external_state(&"hitstun")
		KEY_2:
			_fighter.request_external_state(&"blockstun")
		KEY_3:
			_fighter.request_external_state(&"knockdown")
		KEY_4:
			_fighter.request_external_state(&"wakeup")
		KEY_5:
			_fighter.request_external_state(&"ko")
