extends Area3D
class_name Door

# Interactable door that opens once and stays open.
#
# Scene setup:
#   Door (Area3D, this script)   zone the player stands in to interact
#     CollisionShape3D           covers the area in front of the door
#     MeshInstance3D             the door leaf
#     AnimationPlayer            an "Open" animation that swings/slides the leaf
#
# If the leaf's collision would still block the open doorway, add a Call Method
# Track to the Open animation that disables it partway through.

signal door_opened

@export var open_animation_name : StringName = &"Open"

@onready var animation_player : AnimationPlayer = get_node_or_null("AnimationPlayer")

var is_open := false


func _ready() -> void:
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("_register_nearby_door"):
		body._register_nearby_door(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("_unregister_nearby_door"):
		body._unregister_nearby_door(self)


func open() -> void:
	if is_open:
		return
	is_open = true

	if animation_player != null and animation_player.has_animation(open_animation_name):
		animation_player.play(open_animation_name)
	else:
		push_warning("Door '%s' has no AnimationPlayer animation named '%s'." % [name, open_animation_name])

	door_opened.emit()
