extends Node2D

# Door interaction. Doors register themselves while the player stands in their
# zone (see door.gd) and this plays the matching open one-shot. Ladders have
# their own system; this only covers doors.

var player: CharacterBody3D = null

var _nearby_door: Door = null
var is_opening := false
var _entered := false
var _timer := 0.0


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func register(door: Door) -> void:
	_nearby_door = door


func unregister(door: Door) -> void:
	if _nearby_door == door:
		_nearby_door = null


# True if there's an open-able door in range and the open one-shot was fired.
func can_open() -> bool:
	return _nearby_door != null and not _nearby_door.is_open


func try_open() -> bool:
	if _nearby_door == null or _nearby_door.is_open:
		return false
	_open()
	return true


func _open() -> void:
	is_opening = true
	_entered = false
	_timer = 0.0
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	_nearby_door.open()
	player.animation_tree.set(player.DOOROPEN_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func update(delta: float) -> void:
	if not is_opening:
		return

	_timer += delta
	var active: bool = player.animation_tree.get(player.DOOROPEN_ACTIVE)
	if active:
		_entered = true

	if (_entered and not active) or _timer >= player.dooropen_max_time:
		is_opening = false
		player.current_speed = player.sprint_speed

func cancel() -> void:
	is_opening = false
