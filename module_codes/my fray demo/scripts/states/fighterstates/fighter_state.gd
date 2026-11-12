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


## 直接播放状态定义中的必填动画，不提供空键跳过或备用动画。
func play_state_animation() -> void:
	fighter.play_animation(state_definition.animation_key)


## 每次进入状态都选择其判定姿态并切换到定义的动画。
func _enter_impl(_args: Dictionary) -> void:
	fighter.select_hit_state(state_definition.hit_state_definition)
	play_state_animation()


## 退出状态时完全关闭旧姿态，防止中断或重入残留判定。
func _exit_impl() -> void:
	fighter.clear_hit_state()

## 基础移动可转向，具体动作可覆盖权限；本方法不自行寻找对手。
func can_update_facing() -> bool:
	return true
