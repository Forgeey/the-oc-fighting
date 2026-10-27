class_name FighterHitStateDefinition
extends Resource
## 保存完整判定姿态场景及其进入时使用的默认掩码。

## 场景根为 FrayHitState2D，框为它的直接子节点。
@export var hit_state_scene: PackedScene
## 按直接子 FrayHitbox2D 的顺序设置默认启用位。
@export var default_active_hitboxes: int = 0
