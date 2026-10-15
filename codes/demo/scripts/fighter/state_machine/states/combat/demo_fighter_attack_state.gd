class_name DemoFighterAttackState
extends FrayState

## 攻击状态：以 FrayAttackAttribute 的整数帧数据为判定和状态时长来源。
## AnimationPlayer 只负责视觉播放；攻击判定窗口由固定物理帧推进。

var state_id: StringName = &""
var attack: FrayAttackAttribute
var fighter: DemoFighter
var attack_frame := 0
var projectile_spawned := false


## 初始化实例并保存构造参数。
func _init(p_attack: FrayAttackAttribute) -> void:
	attack = p_attack
	state_id = attack.id


## 状态就绪时从上下文获取所需依赖。
func _ready_impl(context: Dictionary) -> void:
	fighter = context.get("fighter") as DemoFighter


## 进入状态时初始化该状态的行为和数据。
func _enter_impl(_args: Dictionary) -> void:
	attack_frame = 0
	projectile_spawned = false
	var airborne_attack := fighter.has_current_state_tag(&"air_attack") or not fighter.is_on_floor()
	if attack is DemoProjectileAttackAttribute:
		airborne_attack = false
	fighter.clear_attack_hitboxes()
	fighter.set_hurt_state(&"Air" if airborne_attack else &"Stand")
	fighter.reset_attack_targets()
	fighter.movement.set_jump_air_locked(airborne_attack)
	if fighter.has_move_cancel_targets(state_id):
		fighter.open_move_cancel_window(state_id)
	else:
		fighter.close_combo_input_window(false)
	fighter.animation_player.play(state_id)


## 退出状态时清理该状态产生的运行时数据。
func _exit_impl() -> void:
	if fighter.has_move_cancel_targets(state_id):
		fighter.close_combo_input_window(false)
	fighter.clear_attack_state()


## 每个物理帧更新当前状态行为。
func _physics_process_impl(delta: float) -> void:
	fighter.movement.apply_gravity(delta)
	fighter.movement.apply_attack_motion(attack, attack_frame, delta)
	fighter.movement.move_body()
	_spawn_projectile_if_ready()
	fighter.update_attack_hitbox_window(attack, attack_frame)
	if fighter.has_move_cancel_targets(state_id):
		fighter.update_move_cancel_window(attack, attack_frame)
	attack_frame += 1


## 判断当前状态是否已经完成。
func _is_done_processing_impl() -> bool:
	return attack_frame >= attack.duration_frames


## 在攻击启动帧到达时生成一次投射物。
func _spawn_projectile_if_ready() -> void:
	var projectile_attack := attack as DemoProjectileAttackAttribute
	if projectile_attack == null or projectile_spawned:
		return
	if attack_frame < projectile_attack.startup_frames:
		return

	projectile_spawned = true
	fighter.spawn_projectile_attack(projectile_attack)


