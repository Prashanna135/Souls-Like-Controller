extends Area3D
class_name ItemPickup

# World pickup. Place this Area3D (with a CollisionShape3D and whatever mesh
# you like under it) in a level, assign `item` and `count` in the Inspector,
# and it adds that item to the player's inventory on contact, then frees
# itself.
#
# A WeaponItem is only added to the inventory, not auto-equipped — the player
# equips it from the inventory UI.

@export var item  : Item = null
@export var count : int  = 1

@onready var mesh : Node3D = get_node_or_null("Mesh")   # optional, just spins

const SPIN_SPEED := 1.5   # radians/sec


func _ready() -> void:
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if mesh != null:
		mesh.rotation.y += SPIN_SPEED * delta


func _on_body_entered(body: Node3D) -> void:
	if item == null or not body.is_in_group("player"):
		return
	if not body.has_method("_grant_item"):
		return

	body._grant_item(item, count)
	queue_free()
