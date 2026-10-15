@tool
@icon("res://addons/fray/assets/icons/hit_attribute.svg")
class_name FrayAttackAttribute
extends FrayHitboxAttribute
## Generic attack attribute for Fray hitboxes.
##
## Timing is expressed in gameplay frames. The demo maps one gameplay frame to one
## physics tick, so frame data stays deterministic and easy to compare with
## traditional fighting-game frame data.

## Unique attack identifier, often matching an attack hit state name.
@export var id: StringName = &"attack"

## Traditional guard category used by combat resolvers.
enum GuardType {
	HIGH,
	MID,
	LOW,
	OVERHEAD,
	THROW,
	UNBLOCKABLE,
}

## Determines whether the move is crouch-evadable, stand/crouch blockable, overhead, throw, or unblockable.
@export_enum("High", "Mid", "Low", "Overhead", "Throw", "Unblockable") var guard_type: int = GuardType.MID

## When false, an airborne defender cannot block this attack.
@export var can_air_block: bool = true

## Distinguishes projectile rules without moving combat values to a parallel table.
@export var is_projectile: bool = false

## Fighter 施放投射物动作的总持续帧；仅在 is_projectile 为 true 时使用。
@export_range(1, 180, 1) var projectile_cast_duration_frames: int = 36

## 施放动作中生成投射物的帧；从 1 开始计数。
@export_range(1, 180, 1) var projectile_spawn_frame: int = 14

## 投射物每秒水平移动速度；仅在 is_projectile 为 true 时使用。
@export_range(0.0, 2000.0, 1.0) var projectile_speed: float = 360.0

## Amplify 成功后进入的 Fray 状态；空值表示本攻击不能强化。
@export var amplify_target_state: StringName = &""

## 施法动作中开始接受 Amplify 键的帧，包含该帧；负值表示没有 Amplify 窗口。
@export_range(-1, 180, 1) var amplify_start_frame: int = -1

## 施法动作中最后接受 Amplify 键的帧，包含该帧；负值表示持续到投射物生成前一帧。
@export_range(-1, 180, 1) var amplify_end_frame: int = -1

## Amplify 成功时支付的统一气条数量。
@export_range(0, 9999, 1) var amplify_meter_cost: int = 0

## Reserved throw-tech input window. Throw resolution is game-specific and optional.
@export_range(0, 120, 1) var throw_tech_frames: int = 0

## Total attack duration, in gameplay frames.
@export var duration_frames: int = 10

## Frames before the attack hitbox becomes active.
@export var startup_frames: int = 3

## Number of frames the attack hitbox remains active.
@export var active_frames: int = 3

## First frame where this attack may cancel into a scripted follow-up.
## Negative values mean the attack has no follow-up cancel window.
@export var cancel_start_frame: int = -1

## Last frame where this attack may cancel into a scripted follow-up, inclusive.
## Negative values mean the cancel window stays open until the attack ends.
@export var cancel_end_frame: int = -1

## 取消窗口需要满足的接触结果。
enum CancelRequirement {
	ALWAYS,
	ON_HIT,
	ON_BLOCK,
	ON_HIT_OR_BLOCK,
}

## 决定取消窗口是无条件开放，还是要求命中、格挡或任一接触结果。
@export_enum("Always", "On Hit", "On Block", "On Hit Or Block")
var cancel_requirement: int = CancelRequirement.ALWAYS

## 本攻击可取消到的 Fray 状态名；具体输入仍由 Fray transition 处理。
@export var cancel_target_states: PackedStringArray = PackedStringArray()

## Health removed when the attack connects cleanly.
@export var damage: int = 10

## Health removed when the attack is blocked.
@export var block_damage: int = 1

## Hitstun duration applied on clean hit, in gameplay frames.
@export var hitstun_frames: int = 10

## Blockstun duration applied on block, in gameplay frames.
@export var blockstun_frames: int = 5

## Shared pause applied to both fighters after a clean hit, in gameplay frames.
@export_range(0, 60, 1) var hitstop_frames: int = 4

## Shared pause applied to both fighters after a blocked hit, in gameplay frames.
@export_range(0, 60, 1) var blockstop_frames: int = 2

## Optional attacker-specific hitstop override. Negative values use the shared stop value.
@export_range(-1, 60, 1) var attacker_hitstop_frames: int = -1

## Optional defender-specific hitstop override. Negative values use the shared stop value.
@export_range(-1, 60, 1) var defender_hitstop_frames: int = -1

## Optional scene instantiated at the contact point after a clean hit.
@export var hit_spark_scene: PackedScene

## Optional scene instantiated at the contact point after a blocked hit.
@export var block_spark_scene: PackedScene

## Optional sound played after a clean hit.
@export var hit_sfx: AudioStream

## Optional sound played after a blocked hit.
@export var block_sfx: AudioStream

## Optional camera shake intensity for this attack.
@export_range(0.0, 100.0, 0.1) var screen_shake_strength: float = 0.0

## Optional camera shake duration for this attack, in gameplay frames.
@export_range(0, 60, 1) var screen_shake_frames: int = 0

## Per-move proration applied before the normal combo decay.
## Keep this at 1.0 for ordinary starters; projectiles, throws, or supers may opt into a lower value.
@export_group("Combo")
@export_range(0.1, 1.0, 0.01) var combo_initial_scale: float = 1.0

## Meter awarded to the attacker after this attribute lands as a clean hit.
@export_group("Meter")
@export_range(0, 3000, 1) var attacker_meter_gain_hit: int = 120

## Meter awarded to the attacker after this attribute is blocked.
@export_range(0, 3000, 1) var attacker_meter_gain_block: int = 60

## Meter awarded to the defender after taking this attribute as a clean hit.
@export_range(0, 3000, 1) var defender_meter_gain_hit: int = 80

## Meter awarded to the defender after blocking this attribute.
@export_range(0, 3000, 1) var defender_meter_gain_block: int = 40

## Juggle points assigned when this move launches a grounded target.
@export_group("Juggle")
@export_range(0, 20, 1) var juggle_start: int = 0

## Juggle points consumed when this move hits an already-airborne target.
@export_range(0, 20, 1) var juggle_increment: int = 1

## Maximum accumulated juggle points at which this move may connect.
@export_range(0, 50, 1) var juggle_limit: int = 6

## Multiplier applied once per previous airborne hit to this move's air hitstun.
@export_range(0.1, 1.0, 0.01) var air_hitstun_decay: float = 0.9

## Gravity multiplier used while the defender is in air hitstun from this move.
@export_range(0.1, 3.0, 0.05) var gravity_scale_on_hit: float = 1.0

## Knockdown behavior requested after this move hits.
enum KnockdownType {
	NONE,
	SOFT,
	HARD,
}

@export_group("Knockdown")
@export_enum("None", "Soft", "Hard") var knockdown_type: int = KnockdownType.NONE

## Time spent down before wakeup begins, in gameplay frames.
@export_range(0, 240, 1) var knockdown_frames: int = 0

## Hard knockdowns cannot be escaped with the demo tech-roll input.
@export var hard_knockdown: bool = false

## Earliest frame at which a soft knockdown can be tech rolled.
@export_range(0, 240, 1) var untechable_frames: int = 0

@export_group("Movement")
## Horizontal knockback strength.
@export var knockback: float = 220.0

## Duration of attack lunge movement, in gameplay frames.
@export var lunge_frames: int = 0

## Horizontal lunge speed during the lunge window.
@export var lunge_speed: float = 0.0

## Optional vertical launch velocity applied when the defender was grounded.
@export var launch_y_velocity: float = 0.0

## 已浮空目标再次被本攻击命中时使用的垂直速度；0 表示沿用 launch_y_velocity。
## 负值向上，正值向下，用于让每个招式的数据资源独立控制浮空续接力度。
@export var airborne_launch_y_velocity: float = 0.0

## Debug color used by Fray hitbox collision shapes.
@export var color: Color = Color(1.0, 0.18, 0.12, 0.45)


## 根据受击者命中前是否浮空返回本攻击唯一生效的垂直速度。
func get_launch_y_velocity(defender_was_airborne: bool) -> float:
	if defender_was_airborne and not is_zero_approx(airborne_launch_y_velocity):
		return airborne_launch_y_velocity
	return launch_y_velocity


static func get_gameplay_frames_per_second() -> float:
	return maxf(1.0, float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)))


static func frames_to_seconds(frames: int) -> float:
	return float(maxi(0, frames)) / get_gameplay_frames_per_second()


func get_duration_seconds() -> float:
	return frames_to_seconds(duration_frames)


func get_startup_seconds() -> float:
	return frames_to_seconds(startup_frames)


func get_active_seconds() -> float:
	return frames_to_seconds(active_frames)


func get_recovery_start_frame() -> int:
	return startup_frames + active_frames


## 返回本攻击是否声明了状态内 Amplify 输入窗口。
func has_amplify_window() -> bool:
	return amplify_start_frame >= 0 and not amplify_target_state.is_empty()


## 返回给定施法帧是否位于 Amplify 窗口内。
func is_amplify_frame(frame: int) -> bool:
	if not has_amplify_window():
		return false
	var default_end_frame := duration_frames - 1
	if is_projectile:
		default_end_frame = projectile_spawn_frame - 1
	var end_frame := amplify_end_frame if amplify_end_frame >= 0 else default_end_frame
	return frame >= amplify_start_frame and frame <= end_frame


## 返回本攻击是否允许通过 Amplify 转入指定 Fray 状态。
func can_amplify_to(target_state: StringName) -> bool:
	return has_amplify_window() and amplify_target_state == target_state


func has_cancel_window() -> bool:
	return cancel_start_frame >= 0


func is_cancel_frame(frame: int) -> bool:
	if not has_cancel_window():
		return false
	var end_frame := cancel_end_frame if cancel_end_frame >= 0 else duration_frames - 1
	return frame >= cancel_start_frame and frame <= end_frame


## 返回给定接触结果是否满足本攻击的数据化取消条件。
func is_cancel_contact_allowed(connected: bool, blocked: bool) -> bool:
	match cancel_requirement:
		CancelRequirement.ALWAYS:
			return true
		CancelRequirement.ON_HIT:
			return connected and not blocked
		CancelRequirement.ON_BLOCK:
			return connected and blocked
		CancelRequirement.ON_HIT_OR_BLOCK:
			return connected
		_:
			return false


## 返回本取消规则是否依赖攻击接触结果。
func cancel_requires_contact() -> bool:
	return cancel_requirement != CancelRequirement.ALWAYS


## 返回目标状态是否由本攻击资源声明为合法取消目标。
func can_cancel_to(target_state: StringName) -> bool:
	return cancel_target_states.has(target_state)


func get_hitstun_seconds() -> float:
	return frames_to_seconds(hitstun_frames)


func get_blockstun_seconds() -> float:
	return frames_to_seconds(blockstun_frames)


func get_knockdown_seconds() -> float:
	return frames_to_seconds(knockdown_frames)


func get_untechable_seconds() -> float:
	return frames_to_seconds(untechable_frames)


func causes_knockdown() -> bool:
	return knockdown_type != KnockdownType.NONE or hard_knockdown


func is_hard_knockdown() -> bool:
	return hard_knockdown or knockdown_type == KnockdownType.HARD


## Returns the hitstop duration for the attacking fighter.
func get_attacker_hitstop_frames(blocked := false) -> int:
	var shared_frames := blockstop_frames if blocked else hitstop_frames
	return attacker_hitstop_frames if attacker_hitstop_frames >= 0 else shared_frames


## Returns the hitstop duration for the defending fighter.
func get_defender_hitstop_frames(blocked := false) -> int:
	var shared_frames := blockstop_frames if blocked else hitstop_frames
	return defender_hitstop_frames if defender_hitstop_frames >= 0 else shared_frames


func get_lunge_seconds() -> float:
	return frames_to_seconds(lunge_frames)


func _get_color_impl() -> Color:
	return color


func _allows_detection_of_impl(attribute: FrayHitboxAttribute) -> bool:
	return attribute != null and not (attribute is FrayAttackAttribute)




