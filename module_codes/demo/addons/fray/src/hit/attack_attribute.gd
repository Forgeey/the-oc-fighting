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
	MID,
	LOW,
	OVERHEAD,
	THROW,
	UNBLOCKABLE,
}

## Determines which grounded guard posture, if any, can stop this attack.
@export_enum("Mid", "Low", "Overhead", "Throw", "Unblockable") var guard_type: int = GuardType.MID

## When false, an airborne defender cannot block this attack.
@export var can_air_block: bool = true

## Distinguishes projectile rules without moving combat values to a parallel table.
@export var is_projectile: bool = false

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

## Optional vertical launch velocity applied on hit.
@export var launch_y_velocity: float = 0.0

## Debug color used by Fray hitbox collision shapes.
@export var color: Color = Color(1.0, 0.18, 0.12, 0.45)


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


func has_cancel_window() -> bool:
	return cancel_start_frame >= 0


func is_cancel_frame(frame: int) -> bool:
	if not has_cancel_window():
		return false
	var end_frame := cancel_end_frame if cancel_end_frame >= 0 else duration_frames - 1
	return frame >= cancel_start_frame and frame <= end_frame


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




