class_name BasicAttackState
extends FighterState
## 读取招式配置并记录本次单段攻击的进度。

enum Phase { STARTUP, ACTIVE, RECOVERY, DONE }
var elapsed_frames: int = 0
var move: FighterMoveDefinition


## 读取本次招式并重置计时和播放动画。
func _enter_impl(args: Dictionary) -> void:
	move = args["move"]
	elapsed_frames = 0
	movement.stop_horizontal()
	play_state_animation()


## 推进动作计时并保持地面碰撞。
func _physics_process_impl(delta: float) -> void:
	elapsed_frames += 1
	# 活动叶子提交唯一移动，保留重力和地面碰撞。
	movement.step_grounded(0.0, delta)


## 按已执行逻辑帧返回当前攻击阶段。
func get_phase() -> Phase:
	if elapsed_frames >= move.total_frames():
		return Phase.DONE
	if elapsed_frames < move.startup_frames:
		return Phase.STARTUP
	if elapsed_frames < move.startup_frames + move.active_frames:
		return Phase.ACTIVE
	return Phase.RECOVERY


## 判断本次攻击是否完成全部逻辑帧。
func _is_done_processing_impl() -> bool:
	return elapsed_frames >= move.total_frames()
