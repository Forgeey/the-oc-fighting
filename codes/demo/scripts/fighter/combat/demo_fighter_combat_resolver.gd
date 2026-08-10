class_name DemoFighterCombatResolver
extends RefCounted

const DAMAGE_DECAY := 0.9
const MIN_DAMAGE_SCALE := 0.3
const MIN_AIR_HITSTUN_FRAMES := 4

## 通过角色的 Fray 状态机结算格挡、连段缩放、浮空限制、倒地、停帧和击倒。
## 基础受击数据始终来自 FrayAttackAttribute；投技仅发送请求信号，等待具体游戏实现后续流程。
var fighter: DemoFighter
var combo_attacker: DemoFighter
var combo_hit_count := 0
var combo_total_damage := 0
var juggle_points := 0
var air_hit_count := 0


## 保存运行所需依赖并完成初始化。
func setup(p_fighter: DemoFighter) -> void:
	fighter = p_fighter


## 接收并处理命中。
func receive_hit(attacker: DemoFighter, attack: FrayAttackAttribute) -> bool:
	if fighter.has_current_state_tag(&"ko"):
		return false
	# The demo has no attack-side OTG attribute yet, so Fray reaction tags make
	# knockdown and recovery invulnerable instead of maintaining per-state exceptions.
	if fighter.has_current_state_tag(&"knockdown") or fighter.has_current_state_tag(&"recovery"):
		return false

	if attack.guard_type == FrayAttackAttribute.GuardType.THROW:
		fighter.throw_contact_requested.emit(attacker, fighter, attack)
		return true

	var knock_dir := signf(fighter.global_position.x - attacker.global_position.x)
	if knock_dir == 0.0:
		knock_dir = 1.0

	var blocked := is_guarding_against(attacker, attack)
	if blocked:
		_resolve_block(attacker, attack, knock_dir)
		return true

	var airborne_before_hit := not fighter.is_grounded()
	var combo_result := {
		"damage": attack.damage,
		"hitstun_frames": attack.hitstun_frames,
	}
	if not _can_accept_combo_hit(attacker, attack, airborne_before_hit):
		return false
	combo_result = _register_combo_hit(attacker, attack, airborne_before_hit)
	var damage := int(combo_result.get("damage", attack.damage))
	fighter.health = maxi(0, fighter.health - damage)
	fighter.velocity.x = knock_dir * attack.knockback
	if not is_zero_approx(attack.launch_y_velocity):
		fighter.velocity.y = attack.launch_y_velocity

	if attack.causes_knockdown():
		fighter.queue_knockdown(attack)
	elif not airborne_before_hit:
		fighter.clear_pending_knockdown()

	if fighter.health <= 0:
		fighter.state_machine.goto(&"ko")
	else:
		var becomes_airborne := airborne_before_hit or not is_zero_approx(attack.launch_y_velocity)
		var immediate_knockdown := attack.causes_knockdown() and not becomes_airborne
		if immediate_knockdown:
			fighter.state_machine.goto(&"knockdown")
		else:
			var hitstun_frames := int(combo_result.get("hitstun_frames", attack.hitstun_frames))
			fighter.state_machine.goto(&"hitstun", {
				"duration": FrayAttackAttribute.frames_to_seconds(hitstun_frames),
				"airborne": becomes_airborne,
				"gravity_scale": attack.gravity_scale_on_hit,
			})

	_finish_contact(attacker, attack, false)
	return true

## 判断当前连段是否正在进行。
func is_combo_active() -> bool:
	return combo_attacker != null and combo_hit_count > 0


## 结束当前连段，通知 HUD 并清空防守方保存的双人对战连段数据。
func reset_combo() -> void:
	if is_combo_active():
		fighter.combo_ended.emit(
			combo_attacker,
			fighter,
			combo_hit_count,
			combo_total_damage
		)
	combo_attacker = null
	combo_hit_count = 0
	combo_total_damage = 0
	juggle_points = 0
	air_hit_count = 0


## 判断防守方当前连段是否允许本次空中命中。
func _can_accept_combo_hit(
	attacker: DemoFighter,
	attack: FrayAttackAttribute,
	airborne_before_hit: bool
) -> bool:
	if not airborne_before_hit:
		return true
	var current_points := juggle_points if is_combo_active() and combo_attacker == attacker else 0
	return current_points + maxi(0, attack.juggle_increment) <= maxi(0, attack.juggle_limit)


## 记录一次连段命中，并返回由 FrayAttackAttribute 计算出的缩放结算数据。
func _register_combo_hit(
	attacker: DemoFighter,
	attack: FrayAttackAttribute,
	airborne_before_hit: bool
) -> Dictionary:
	if is_combo_active() and combo_attacker != attacker:
		reset_combo()
	if not is_combo_active():
		combo_attacker = attacker

	var damage_scale := maxf(
		MIN_DAMAGE_SCALE,
		pow(DAMAGE_DECAY, float(combo_hit_count)) * clampf(attack.combo_initial_scale, 0.1, 1.0)
	)
	var scaled_damage := int(round(float(maxi(0, attack.damage)) * damage_scale))
	if attack.damage > 0:
		scaled_damage = maxi(1, scaled_damage)
	var applied_damage := mini(fighter.health, scaled_damage)

	if airborne_before_hit:
		juggle_points += maxi(0, attack.juggle_increment)
		air_hit_count += 1
	elif not is_zero_approx(attack.launch_y_velocity):
		juggle_points = maxi(juggle_points, maxi(0, attack.juggle_start))
		air_hit_count = 0

	combo_hit_count += 1
	combo_total_damage += applied_damage
	var hitstun_scale := 1.0
	if airborne_before_hit:
		hitstun_scale = pow(
			clampf(attack.air_hitstun_decay, 0.1, 1.0),
			float(maxi(0, air_hit_count - 1))
		)
	var hitstun_frames := maxi(
		MIN_AIR_HITSTUN_FRAMES if airborne_before_hit else 1,
		int(round(float(attack.hitstun_frames) * hitstun_scale))
	)
	fighter.combo_changed.emit(
		combo_attacker,
		fighter,
		combo_hit_count,
		combo_total_damage
	)
	return {
		"damage": applied_damage,
		"damage_scale": damage_scale,
		"hitstun_frames": hitstun_frames,
		"juggle_points": juggle_points,
	}

## 判断当前防御姿态能否格挡本次攻击。
func is_guarding_against(_attacker: DemoFighter, attack: FrayAttackAttribute) -> bool:
	if not is_blocking():
		return false
	if attack.guard_type in [
		FrayAttackAttribute.GuardType.THROW,
		FrayAttackAttribute.GuardType.UNBLOCKABLE,
	]:
		return false

	var airborne := not fighter.is_grounded()
	if airborne:
		return attack.can_air_block and (
			fighter.has_current_state_tag(&"airborne") or fighter.get_current_state() == &"blockstun"
		)

	if not fighter.is_in_neutral_state() and fighter.get_current_state() != &"blockstun":
		return false

	var crouching_guard := fighter.wants_crouch()
	match attack.guard_type:
		FrayAttackAttribute.GuardType.LOW:
			return crouching_guard
		FrayAttackAttribute.GuardType.OVERHEAD:
			return not crouching_guard
		_:
			return true


## 判断是否格挡。
func is_blocking() -> bool:
	return fighter.controller.is_pressed(fighter.fray_input(&"block"))




## 解析并处理格挡。
func _resolve_block(attacker: DemoFighter, attack: FrayAttackAttribute, knock_dir: float) -> void:
	fighter.health = maxi(0, fighter.health - attack.block_damage)
	fighter.velocity.x = knock_dir * attack.knockback * 0.42
	if fighter.health <= 0:
		fighter.state_machine.goto(&"ko")
	else:
		fighter.state_machine.goto(&"blockstun", {
			"duration": attack.get_blockstun_seconds(),
			"airborne": not fighter.is_grounded(),
		})
	_finish_contact(attacker, attack, true)


## 完成命中停帧、战斗信号和生命值通知。
func _finish_contact(attacker: DemoFighter, attack: FrayAttackAttribute, blocked: bool) -> void:
	_apply_attack_stop(attacker, attack, blocked)
	fighter.attack_connected.emit(attacker, fighter, attack, blocked)
	fighter.health_changed.emit(fighter, fighter.health, fighter.max_health)


## 分别为攻防双方应用攻击属性定义的停帧。
func _apply_attack_stop(attacker: DemoFighter, attack: FrayAttackAttribute, blocked: bool) -> void:
	fighter.apply_hitstop(attack.get_defender_hitstop_frames(blocked))
	attacker.apply_hitstop(attack.get_attacker_hitstop_frames(blocked))


