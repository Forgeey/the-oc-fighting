@tool
class_name DemoMoveDefinition
extends Resource

## 一个角色招式的数据驱动定义。
## 固定招式的 FrayHitState2D 直接放在角色场景中，战斗数值来自其中 strike 的 FrayAttackAttribute。
@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## 仅投射物招式直接引用攻击属性；固定招式留空，避免和 strike 重复引用。
@export var attack_attribute: FrayAttackAttribute
## 指定指令允许触发的角色姿态。
@export_enum("ground", "crouch", "air") var activation_context := "ground"
@export var state_tags: PackedStringArray = PackedStringArray()
@export var priority := 0
## 当前招式可在 FrayAttackAttribute 取消帧内转入的目标招式标识。
@export var cancel_target_move_ids: PackedStringArray = PackedStringArray()
## 仅能通过 Fray 取消转移进入的后续招式应关闭中立触发。
@export var neutral_available := true
## 招式表连段路线中的前置招式；中立起手招式留空。
@export var combo_parent_move_id: StringName = &""
## 连段终结招式在招式表中显示的可选完整名称。
@export var move_list_name := ""

const CONTEXT_GROUND := "ground"
const CONTEXT_CROUCH := "crouch"
const CONTEXT_AIR := "air"
const CONTEXTS := [CONTEXT_GROUND, CONTEXT_CROUCH, CONTEXT_AIR]


## 判断该招式是否使用独立投射物命中框。
func uses_projectile_attack() -> bool:
	return attack_attribute is DemoProjectileAttackAttribute


## 返回该招式进入状态所需的 Fray 条件。
func get_input_prereqs() -> PackedStringArray:
	match activation_context:
		CONTEXT_AIR:
			return PackedStringArray(["is_airborne"])
		CONTEXT_CROUCH:
			return PackedStringArray(["wants_crouch", "!is_airborne"])
		CONTEXT_GROUND:
			# Ground means any grounded stance. Command moves commonly finish on
			# down-forward, while dedicated crouch moves add wants_crouch below.
			return PackedStringArray(["!is_airborne"])
		_:
			return PackedStringArray()


## 返回该招式所属的地面或空中攻击标签。
func get_required_state_tag() -> StringName:
	return &"air_attack" if activation_context == CONTEXT_AIR else &"ground_attack"


## 返回招式列表名称。
func get_move_list_name() -> String:
	return move_list_name if not move_list_name.is_empty() else display_name


## 判断该招式是否带有特殊技标签。
func is_special_move() -> bool:
	return state_tags.has("special_move")


## 判断该招式是否带有连段终结标签。
func is_combo_ender() -> bool:
	return state_tags.has("combo_ender")


## 验证招式标识、投射物属性、上下文和标签配置。
func is_valid() -> bool:
	if id == &"":
		return false
	if attack_attribute != null and (not uses_projectile_attack() or attack_attribute.id != id):
		return false
	if not CONTEXTS.has(activation_context):
		return false
	if combo_parent_move_id == id:
		return false
	if not neutral_available and combo_parent_move_id == &"":
		return false
	return state_tags.has(String(get_required_state_tag()))