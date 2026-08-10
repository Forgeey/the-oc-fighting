@tool
class_name DemoMoveCommand
extends Resource

## 由有序语义输入步骤组成的 Fray 招式指令；保存方向和动作名称而非物理按键，以支持重绑定和朝向镜像。
@export var steps: Array[DemoMoveCommandStep] = []

const VALID_INPUTS := [
	"up",
	"down",
	"forward",
	"back",
	"left",
	"right",
	"light",
	"heavy",
	"special",
	"block",
]
const ATTACK_INPUTS := ["light", "heavy", "special"]
const MAX_STEPS := 12


## 判断指令是否仅包含一次单键输入。
func is_simple_press() -> bool:
	return steps.size() == 1 and steps[0].inputs.size() == 1


## 返回单键指令的输入名称；复杂指令返回空名称。
func get_simple_input() -> StringName:
	if not is_simple_press():
		return &""
	return StringName(steps[0].inputs[0])


## 计算用于输入匹配排序的指令复杂度。
func get_complexity() -> int:
	var result := steps.size() * 10
	for step in steps:
		result += maxi(0, step.inputs.size() - 1) * 5
	return result


## 生成可比较和去重的稳定签名。
func get_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for step in steps:
		parts.append(step.get_signature())
	return ">".join(parts)


## 返回当前指令的首个验证错误。
func get_validation_error() -> String:
	if steps.is_empty():
		return "Command cannot be empty."
	if steps.size() > MAX_STEPS:
		return "Command cannot contain more than %d steps." % MAX_STEPS
	for step in steps:
		if step == null or step.inputs.is_empty():
			return "Every command step must contain at least one input."
		var seen: Dictionary = {}
		for input_name in step.inputs:
			if not VALID_INPUTS.has(input_name):
				return "Unknown command input: %s" % input_name
			if seen.has(input_name):
				return "A command step cannot repeat %s." % input_name
			seen[input_name] = true
	var final_step := steps.back() as DemoMoveCommandStep
	var has_attack_input := false
	for input_name in final_step.inputs:
		if ATTACK_INPUTS.has(input_name):
			has_attack_input = true
			break
	if not has_attack_input:
		return "The final command step must include light, heavy, or special."
	return ""
