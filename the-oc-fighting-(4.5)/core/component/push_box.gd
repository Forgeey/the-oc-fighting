extends Area2D
class_name Pushbox

@onready var collisionshape : CollisionShape2D = $"CollisionShape2D"

func _physics_process(_delta: float) -> void:
	var overlapping_areas : Array = get_overlapping_areas()
	for i in overlapping_areas.size():
		var overlap = overlapping_areas[i]
		if overlap is Pushbox:
			var colliding_pushbox : Pushbox = overlap
			var opposing_player : CharacterBody2D = colliding_pushbox.get_parent()
			
			# Defines the left and right extents of the player's pushbox collision shape
			var self_pushbox_left : float = global_position.x - (collisionshape.position[0] / 2)
			var self_pushbox_right : float = global_position.x + (collisionshape.position[0] / 2)
			# Opposing player pushbox left/right
			var colliding_pushbox_left : float = colliding_pushbox.global_position.x - (colliding_pushbox.collisionshape.position[0] / 2)
			var colliding_pushbox_right : float = colliding_pushbox.global_position.x + (colliding_pushbox.collisionshape.position[0] / 2)
			# Finds the overlap between the two collision shapes.
			var right_overlap : float = abs(self_pushbox_right - colliding_pushbox_left)
			var left_overlap : float = abs(colliding_pushbox_right - self_pushbox_left)
			# The position adjustment will be used to push the players apart.
			var position_adjustment : float
			# Whichever overlap is the smallest out of the two will be used as the position adjustment.
			if (right_overlap <= left_overlap):
				position_adjustment = right_overlap
			elif (left_overlap <= right_overlap):
				position_adjustment = -left_overlap
			# Finally, the position adjustment is halfed.
			position_adjustment *= 0.5

			opposing_player.global_position.x += position_adjustment
