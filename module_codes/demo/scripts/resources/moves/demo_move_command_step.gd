@tool
class_name DemoMoveCommandStep
extends Resource

## Fray 招式指令中的一个步骤；同一步骤内的多个输入需要同时按下。
@export var inputs: PackedStringArray = PackedStringArray()
@export_range(1, 2000, 1, "suffix:ms") var max_delay_ms := 280


## 生成可比较和去重的稳定签名。
func get_signature() -> String:
	var normalized := Array(inputs)
	normalized.sort()
	return "+".join(normalized)
