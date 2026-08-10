class_name CombatCoreProjectileAttackState
extends FoundationState
## 使用 FrayAttackAttribute 施放帧数据驱动的投射物攻击状态。
##
## 普通波与强化波状态共享一次施法运行时；Amplify 仍由 Fray press transition 驱动，
## 状态只负责延续施法计时、支付资源和发出生成请求。

const STATE_PROJECTILE: StringName = &"projectile"
const STATE_ENHANCED_PROJECTILE: StringName = &"enhanced_projectile"

var _state_id: StringName
var _cast_runtime: Dictionary
var _attribute: FrayAttackAttribute


## 创建供普通波与强化波状态共享的单次施法运行时。
static func create_cast_runtime() -> Dictionary:
	return {
		"active": false,
		"attribute": null,
		"elapsed_frames": 0,
		"spawned": false,
		"handoff_pending": false,
	}


## 创建按状态 ID 读取普通波或强化波资源的投射物施放状态。
func _init(state_id: StringName, cast_runtime: Dictionary) -> void:
	_state_id = state_id
	_cast_runtime = cast_runtime


## 返回当前普通波施法是否可通过 Fray guard press 转入指定强化状态。
func can_amplify_to(target_state: StringName) -> bool:
	if _state_id != STATE_PROJECTILE or _attribute == null:
		return false
	if not bool(_cast_runtime.get("active", false)) or bool(_cast_runtime.get("spawned", false)):
		return false
	if not _attribute.can_amplify_to(target_state):
		return false
	var elapsed_frames := int(_cast_runtime.get("elapsed_frames", 0))
	return (
		_attribute.is_amplify_frame(elapsed_frames)
		and fighter.can_spend_meter(_attribute.amplify_meter_cost)
	)


## 进入普通波时开始新施法；进入强化波时继承原计时、支付气条并替换攻击资源。
func _enter_impl(_args: Dictionary) -> void:
	var next_attribute := fighter.get_projectile_attack_attribute(_state_id) as FrayAttackAttribute
	if next_attribute == null or not next_attribute.is_projectile:
		push_error("投射物施放状态缺少有效的 FrayAttackAttribute。")
		_attribute = null
		return
	if _state_id == STATE_ENHANCED_PROJECTILE:
		_enter_amplified_cast(next_attribute)
	else:
		_begin_cast(next_attribute)
	if _attribute != null:
		movement.stop_horizontal()


## 延续普通波的共享施法计时，并在成功支付资源后切换为强化攻击资源。
func _enter_amplified_cast(next_attribute: FrayAttackAttribute) -> void:
	var source_attribute := _cast_runtime.get("attribute") as FrayAttackAttribute
	var elapsed_frames := int(_cast_runtime.get("elapsed_frames", 0))
	if (
		not bool(_cast_runtime.get("active", false))
		or not bool(_cast_runtime.get("handoff_pending", false))
		or source_attribute == null
		or not source_attribute.can_amplify_to(_state_id)
		or not source_attribute.is_amplify_frame(elapsed_frames)
		or bool(_cast_runtime.get("spawned", false))
	):
		push_error("强化投射物状态只能由普通波的有效 Amplify 转移进入。")
		_reset_cast_runtime()
		_attribute = null
		return
	if not fighter.try_spend_meter(
		source_attribute.amplify_meter_cost,
		&"projectile_amplify",
		next_attribute
	):
		push_error("强化投射物转移成立后支付气条失败。")
		_reset_cast_runtime()
		_attribute = null
		return
	_cast_runtime["attribute"] = next_attribute
	_cast_runtime["handoff_pending"] = false
	_attribute = next_attribute


## 清理旧施法并从第 0 帧开始一次普通投射物施放。
func _begin_cast(attribute: FrayAttackAttribute) -> void:
	_reset_cast_runtime()
	_cast_runtime["active"] = true
	_cast_runtime["attribute"] = attribute
	_attribute = attribute


## 按当前攻击资源推进共享施法计时，并在同一生成帧发出一次投射物请求。
func _physics_process_impl(delta: float) -> void:
	if _attribute == null or not bool(_cast_runtime.get("active", false)):
		return
	var elapsed_frames := int(_cast_runtime.get("elapsed_frames", 0)) + 1
	_cast_runtime["elapsed_frames"] = elapsed_frames
	movement.step_ground_attack(_attribute, elapsed_frames, delta)
	if not bool(_cast_runtime.get("spawned", false)) and elapsed_frames >= maxi(_attribute.projectile_spawn_frame, 1):
		_cast_runtime["spawned"] = true
		fighter.request_projectile_spawn(_attribute)


## 施放动作总时长完全读取当前普通或强化 FrayAttackAttribute 的施放帧字段。
func _is_done_processing_impl() -> bool:
	return (
		_attribute == null
		or int(_cast_runtime.get("elapsed_frames", 0))
		>= maxi(_attribute.projectile_cast_duration_frames, 1)
	)


## 普通波在生成前离开时保留一次强化交接；其余离开路径结束共享施法。
func _exit_impl() -> void:
	if (
		_state_id == STATE_PROJECTILE
		and bool(_cast_runtime.get("active", false))
		and not bool(_cast_runtime.get("spawned", false))
	):
		_cast_runtime["handoff_pending"] = true
	else:
		_reset_cast_runtime()
	_attribute = null


## 将共享施法运行时恢复为空闲状态。
func _reset_cast_runtime() -> void:
	_cast_runtime["active"] = false
	_cast_runtime["attribute"] = null
	_cast_runtime["elapsed_frames"] = 0
	_cast_runtime["spawned"] = false
	_cast_runtime["handoff_pending"] = false