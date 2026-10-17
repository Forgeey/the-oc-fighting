@tool
@icon("res://addons/fray/assets/icons/hit_attribute.svg")
class_name CombatAttackAttribute
extends FrayHitboxAttribute
## Project-owned fighting-game attack data layered on FrayHitboxAttribute.
##
## This class is intentionally outside addons/fray. The official plugin only defines
## the generic hitbox attribute contract; combat timing and damage rules belong here.

## Unique attack identifier, normally matching its Fray attack state.
@export var id: StringName = &"attack"

enum GuardType {
	HIGH,
	MID,
	LOW,
	OVERHEAD,
	THROW,
	UNBLOCKABLE,
}

## Grounded guard category interpreted by the combat resolver.
@export_enum("High", "Mid", "Low", "Overhead", "Throw", "Unblockable") var guard_type: int = GuardType.MID

## Whether an airborne defender may block this attack.
@export var can_air_block: bool = true

@export_group("Projectile")
## Marks this attribute as projectile combat data.
@export var is_projectile: bool = false
## Total cast duration before the projectile state completes.
@export_range(1, 600, 1) var projectile_cast_duration_frames: int = 36
## Cast frame on which the projectile is spawned.
@export_range(1, 600, 1) var projectile_spawn_frame: int = 14
## Projectile travel speed in pixels per second.
@export_range(0.0, 5000.0, 1.0) var projectile_speed: float = 360.0

@export_subgroup("Amplify")
## State entered when this cast is amplified. Empty disables amplification.
@export var amplify_target_state: StringName = &""
## First cast frame that accepts amplification.
@export var amplify_start_frame: int = -1
## Last cast frame that accepts amplification; negative means until spawn.
@export var amplify_end_frame: int = -1
## Meter paid when amplification succeeds.
@export_range(0, 100000, 1) var amplify_meter_cost: int = 0

@export_group("Timing")
## Reserved throw-tech input window.
@export_range(0, 120, 1) var throw_tech_frames: int = 0
## Total attack duration in gameplay frames.
@export_range(1, 600, 1) var duration_frames: int = 10
## Frames before the strike becomes active.
@export_range(0, 600, 1) var startup_frames: int = 3
## Number of active strike frames.
@export_range(0, 600, 1) var active_frames: int = 3

@export_group("Cancel")
## First frame where a cancel is permitted; negative disables the window.
@export var cancel_start_frame: int = -1
## Last cancel frame, inclusive; negative means until the attack ends.
@export var cancel_end_frame: int = -1

enum CancelRequirement {
	ALWAYS,
	ON_HIT,
	ON_BLOCK,
	ON_HIT_OR_BLOCK,
}

## Contact result required before a cancel route becomes legal.
@export_enum("Always", "On Hit", "On Block", "On Hit Or Block") var cancel_requirement: int = CancelRequirement.ALWAYS
## Fray state names that this attack may cancel into.
@export var cancel_target_states: PackedStringArray = PackedStringArray()

@export_group("Damage")
@export var damage: int = 10
@export var block_damage: int = 1
@export var hitstun_frames: int = 10
@export var blockstun_frames: int = 5
@export_range(0, 60, 1) var hitstop_frames: int = 4
@export_range(0, 60, 1) var blockstop_frames: int = 2
@export_range(-1, 60, 1) var attacker_hitstop_frames: int = -1
@export_range(-1, 60, 1) var defender_hitstop_frames: int = -1

@export_group("Presentation")
@export var hit_spark_scene: PackedScene
@export var block_spark_scene: PackedScene
@export var hit_sfx: AudioStream
@export var block_sfx: AudioStream
@export_range(0.0, 100.0, 0.1) var screen_shake_strength: float = 0.0
@export_range(0, 60, 1) var screen_shake_frames: int = 0

@export_group("Combo")
@export_range(0.1, 1.0, 0.01) var combo_initial_scale: float = 1.0
@export_range(0, 100000, 1) var attacker_meter_gain_hit: int = 120
@export_range(0, 100000, 1) var attacker_meter_gain_block: int = 60
@export_range(0, 100000, 1) var defender_meter_gain_hit: int = 80
@export_range(0, 100000, 1) var defender_meter_gain_block: int = 40

@export_group("Juggle")
@export_range(0, 20, 1) var juggle_start: int = 0
@export_range(0, 20, 1) var juggle_increment: int = 1
@export_range(0, 50, 1) var juggle_limit: int = 6
@export_range(0.1, 1.0, 0.01) var air_hitstun_decay: float = 0.9
@export_range(0.1, 3.0, 0.05) var gravity_scale_on_hit: float = 1.0

enum KnockdownType {
	NONE,
	SOFT,
	HARD,
}

@export_group("Knockdown")
@export_enum("None", "Soft", "Hard") var knockdown_type: int = KnockdownType.NONE
@export_range(0, 240, 1) var knockdown_frames: int = 0
@export var hard_knockdown: bool = false
@export_range(0, 240, 1) var untechable_frames: int = 0

@export_group("Movement")
@export var knockback: float = 220.0
@export var lunge_frames: int = 0
@export var lunge_speed: float = 0.0
## Launch velocity used when the defender was grounded before this hit.
@export var launch_y_velocity: float = 0.0
## Launch velocity used when the defender was already airborne before this hit.
@export var airborne_launch_y_velocity: float = 0.0

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


func can_cancel_to(target_state: StringName) -> bool:
	return has_cancel_window() and not target_state.is_empty() and target_state in cancel_target_states


func cancel_requires_contact() -> bool:
	return cancel_requirement != CancelRequirement.ALWAYS


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


func has_amplify_window() -> bool:
	return not amplify_target_state.is_empty() and amplify_start_frame >= 0


func can_amplify_to(target_state: StringName) -> bool:
	return not amplify_target_state.is_empty() and amplify_target_state == target_state


func is_amplify_frame(frame: int) -> bool:
	if amplify_target_state.is_empty() or amplify_start_frame < 0:
		return false
	var end_frame := amplify_end_frame
	if end_frame < 0:
		end_frame = maxi(projectile_spawn_frame - 1, amplify_start_frame)
	return frame >= amplify_start_frame and frame <= end_frame


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


func get_attacker_hitstop_frames(blocked := false) -> int:
	var shared_frames := blockstop_frames if blocked else hitstop_frames
	return attacker_hitstop_frames if attacker_hitstop_frames >= 0 else shared_frames


func get_defender_hitstop_frames(blocked := false) -> int:
	var shared_frames := blockstop_frames if blocked else hitstop_frames
	return defender_hitstop_frames if defender_hitstop_frames >= 0 else shared_frames


func get_lunge_seconds() -> float:
	return frames_to_seconds(lunge_frames)


func get_launch_y_velocity(defender_was_airborne: bool) -> float:
	return airborne_launch_y_velocity if defender_was_airborne else launch_y_velocity


func _get_color_impl() -> Color:
	return color


func _allows_detection_of_impl(attribute: FrayHitboxAttribute) -> bool:
	return attribute is CombatHurtboxAttribute
