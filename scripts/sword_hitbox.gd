extends Area3D

# Weapon hitbox. Add a CollisionShape3D sized to the blade and parent this
# node under the wielder's weaponattachment bone so it follows the weapon.
#
# Setup:
#   1. player.gd / enemy.gd assign `wielder` on this node at runtime.
#   2. Set `valid_target_groups` in the Inspector (["enemies"] on the player's
#      hitbox, ["player"] on the enemy's) so it only damages the other side.
#   3. From the attack animation, call enable_hitbox() at the frame the blade
#      starts moving and disable_hitbox() once it's past, so standing near
#      someone doesn't chip damage every frame.
#   4. Optionally keyframe `damage` per swing so a heavier finisher deals more.

@export var damage : float = 15.0
@export var valid_target_groups : Array[StringName] = [&"enemies"]

var wielder : Node3D = null
var _hit_this_swing : Array[Node3D] = []


func _ready() -> void:
	monitoring  = false
	monitorable = false
	body_entered.connect(_on_body_entered)


# Open the active window for this swing.
func enable_hitbox() -> void:
	_hit_this_swing.clear()
	monitoring = true


# Close the active window.
func disable_hitbox() -> void:
	monitoring = false


func _on_body_entered(body: Node3D) -> void:
	if body == wielder or _hit_this_swing.has(body):
		return

	var valid := false
	for group in valid_target_groups:
		if body.is_in_group(group):
			valid = true
			break
	if not valid:
		return

	if body.has_method("take_damage"):
		_hit_this_swing.append(body)
		var source := wielder.global_position if wielder != null else global_position
		body.take_damage(damage, source)
