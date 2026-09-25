extends Area3D
class_name Ladder

# Climbable ladder zone. Add two Marker3D children:
#
#   BottomMarker   where the player stands to grab the ladder. Its Y rotation
#                  sets which way the player faces while climbing (flip it 180
#                  if they mount facing away from the rungs).
#   TopMarker      where the player steps off at the top. Place it on solid
#                  ground just past the ladder, not on the rungs.
#
# Size the Area3D's CollisionShape3D to cover the full climb so the player
# stays "nearby" the whole way up.

@onready var bottom_marker : Marker3D = $BottomMarker
@onready var top_marker    : Marker3D = $TopMarker


func _ready() -> void:
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("_register_nearby_ladder"):
		body._register_nearby_ladder(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("_unregister_nearby_ladder"):
		body._unregister_nearby_ladder(self)


func get_mount_position() -> Vector3:
	return bottom_marker.global_position


func get_climb_facing_angle() -> float:
	return bottom_marker.global_rotation.y


func get_top_y() -> float:
	return top_marker.global_position.y


func get_bottom_y() -> float:
	return bottom_marker.global_position.y


func get_top_stand_position() -> Vector3:
	return top_marker.global_position
