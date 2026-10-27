class_name FighterState
extends FrayState
## 为角色状态提供共用组件引用。

## 保存构建器绑定的只读状态配置，不在共享资源中记录运行进度。
var state_definition: FighterStateDefinition
var fighter: Fighter
var fighter_input: FighterInput
var controller: FrayController
var movement: FighterMovement
var hit_state_manager: FrayHitStateManager2D


## 读取本角色共用组件的引用，子类覆盖时应调用父方法。
func _ready_impl(context: Dictionary) -> void:
	fighter = context["fighter"]
	fighter_input = context["fighter_input"]
	controller = context["controller"]
	movement = context["movement"]
	hit_state_manager = context["hit_state_manager"]


## 在具体状态要求的时机播放其配置动画，空键表示本次不请求动画。
func play_state_animation() -> void:
	if not state_definition.animation_key.is_empty():
		fighter.play_animation(state_definition.animation_key)


## 进入状态时通过 Fighter 选择本状态声明的完整判定姿态。
func _enter_impl(_args: Dictionary) -> void:
	fighter.select_hit_state(state_definition.hit_state_definition)


## 退出状态时完全关闭旧姿态，防止中断或重入残留判定。
func _exit_impl() -> void:
	fighter.clear_hit_state()
