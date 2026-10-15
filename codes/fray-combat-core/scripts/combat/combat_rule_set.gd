class_name CombatRuleSet
extends Resource
## 第 2 组战斗核心的非招式规则资源。
##
## 单招 damage、硬直、击退、浮空和气条收益仍由 FrayAttackAttribute 独占；
## 本资源只保存跨招式共享的连段、生命与资源上限规则。

## 每名 fighter 的回合生命上限。
@export_range(1, 9999, 1) var max_health: int = 1000

## 统一三格气条上限；每格 1000。
@export_range(1, 9999, 1) var max_meter: int = 3000

## 每次续接连段时应用的逐击伤害衰减。
@export_range(0.1, 1.0, 0.01) var combo_decay: float = 0.90

## 连段伤害缩放下限。
@export_range(0.01, 1.0, 0.01) var minimum_damage_scale: float = 0.05

## 连续使用相同 attribute.id 时额外应用的重复招式修正。
@export_range(0.1, 1.0, 0.01) var repeated_move_scale: float = 0.90

## 最后一次命中后超过该帧数则结束连段。
@export_range(1, 600, 1) var combo_timeout_frames: int = 90

## 防御推退与伤害结算中使用的固定物理帧率。
@export_range(1, 240, 1) var gameplay_fps: int = 60


## 返回资源配置错误；空数组表示可用于战斗。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_health <= 0:
		errors.append("max_health 必须大于 0。")
	if max_meter <= 0:
		errors.append("max_meter 必须大于 0。")
	if combo_decay <= 0.0 or combo_decay > 1.0:
		errors.append("combo_decay 必须位于 (0, 1]。")
	if minimum_damage_scale <= 0.0 or minimum_damage_scale > 1.0:
		errors.append("minimum_damage_scale 必须位于 (0, 1]。")
	if repeated_move_scale <= 0.0 or repeated_move_scale > 1.0:
		errors.append("repeated_move_scale 必须位于 (0, 1]。")
	return errors
