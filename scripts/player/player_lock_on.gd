extends Node2D

# Lock-on targeting. Picks the nearest enemies, cycles through them on repeat
# presses, and keeps the camera + on-screen reticle aimed at the active one.
# Owned by the Player root (see player.gd), which calls handle_input() and
# update() from its physics step.

var player: CharacterBody3D = null

var target: Node3D = null
var is_locked_on := false
var _candidates: Array = []
var _index := -1

@export var max_range := 15.0


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


# One lock_on press: grab the nearest enemy, or cycle/unlock if already locked.
func handle_input() -> void:
	if is_locked_on:
		_cycle_or_unlock()
	else:
		_try_lock_on()


# Drop the lock if the target died or got freed, so the camera and reticle
# don't keep tracking a corpse. Runs every physics frame.
func update() -> void:
	if not is_locked_on:
		return
	if target == null or not is_instance_valid(target) or (("is_dead" in target) and target.is_dead):
		clear()


func _try_lock_on() -> void:
	var found: Array = []
	for body in player.get_tree().get_nodes_in_group("enemies"):
		if body is Node3D:
			var d := player.global_position.distance_to(body.global_position)
			if d < max_range:
				found.append({ "node": body, "dist": d })

	if found.is_empty():
		return

	found.sort_custom(func(a, b): return a["dist"] < b["dist"])
	_candidates = found.map(func(e): return e["node"])
	_index = 0
	_apply(_candidates[0])


func _cycle_or_unlock() -> void:
	if _candidates.is_empty():
		clear()
		return

	_index += 1
	if _index >= _candidates.size():
		clear()
	else:
		_apply(_candidates[_index])


func _apply(new_target: Node3D) -> void:
	# Never lock onto something already dead — it's out of the group, but a
	# corpse could still be mid-cycle here.
	if new_target == null or not is_instance_valid(new_target) or (("is_dead" in new_target) and new_target.is_dead):
		clear()
		return

	# Wipe the marker off whoever we were tracking before (covers both a fresh
	# lock and cycling between enemies).
	if target != null and target.has_method("set_lock_indicator"):
		target.set_lock_indicator(false)

	target = new_target
	is_locked_on = true
	player.cam_script.lock_target = new_target
	player.cam_script.is_locked_on = true

	if target.has_method("set_lock_indicator"):
		target.set_lock_indicator(true)
	if player.lock_reticle != null:
		player.lock_reticle.set_target(new_target)

	# Locking on means a fight is about to start — get the weapon out.
	player.draw_weapon_if_sheathed()


func clear() -> void:
	if target != null and target.has_method("set_lock_indicator"):
		target.set_lock_indicator(false)

	is_locked_on = false
	target = null
	_index = -1
	_candidates = []
	player.cam_script.is_locked_on = false
	player.cam_script.lock_target = null

	if player.lock_reticle != null:
		player.lock_reticle.set_target(null)
