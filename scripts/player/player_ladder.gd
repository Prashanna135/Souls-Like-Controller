extends Node2D

# Ladder climbing. Walks the mount -> climb/idle -> dismount state machine in
# the AnimationTree and snaps the player to the ladder's markers. Ladders
# register themselves while the player stands in their zone (see ladder.gd).
#
# The root drives this: it calls update() every physics frame and decides when
# to mount/exit, since doors share the same interact key.

var player: CharacterBody3D = null

var _nearby_ladder: Ladder = null
var _active_ladder: Ladder = null
var is_mounting := false
var is_on_ladder := false
var is_dismounting := false
var _mount_entered := false
var _dismount_entered := false
var _mount_timer := 0.0
var _dismount_timer := 0.0
var _mount_clip_len := 0.0
var _dismount_clip_len := 0.0
# After an instant top release the dismount clip is meant to keep playing as a
# cosmetic layer for its own length without gating movement.
var _dismount_cosmetic := false
var _dismount_cosmetic_time := 0.0


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func register(ladder: Ladder) -> void:
	_nearby_ladder = ladder


func unregister(ladder: Ladder) -> void:
	if _nearby_ladder == ladder:
		_nearby_ladder = null
	# _active_ladder is left alone on purpose — the mount zone spans the whole
	# climb, so leaving it mid-climb shouldn't happen. If it does, the player
	# keeps climbing on stale data rather than being yanked out of the animation.


func can_mount() -> bool:
	return _nearby_ladder != null


func is_busy() -> bool:
	return is_mounting or is_on_ladder or is_dismounting


# Movement is fully locked while transitioning, and during the cosmetic
# climb-out — but not during a plain climb.
func is_locked() -> bool:
	return is_busy() or _dismount_cosmetic


func mount() -> void:
	var ladder := _nearby_ladder
	_active_ladder = ladder
	is_mounting = true
	is_on_ladder = false
	is_dismounting = false
	_mount_entered = false
	_mount_timer = 0.0
	_mount_clip_len = _clip_length(player.LADDER_ANIM_MOUNT)

	# Cancel anything else mid-flight.
	player.is_rolling = false
	player.is_jumpback = false
	player.jumpback_started = false
	player.current_speed = player.sprint_speed
	player.velocity = Vector3.ZERO

	var mount_pos: Vector3 = ladder.get_mount_position()
	player.global_position.x = mount_pos.x
	player.global_position.y = mount_pos.y
	player.global_position.z = mount_pos.z
	player.mannequin.rotation.y = ladder.get_climb_facing_angle()

	player.ladder_playback.travel(player.LADDER_STATE_MOUNT)


func exit() -> void:
	is_mounting = false
	is_on_ladder = false
	is_dismounting = false
	_dismount_clip_len = 0.0


func update(delta: float) -> void:
	if _dismount_cosmetic:
		_dismount_cosmetic_time += delta
		var cos_len := _dismount_clip_len
		if cos_len <= 0.0:
			cos_len = _clip_length(player.LADDER_ANIM_DISMOUNT)
		if cos_len <= 0.0:
			cos_len = 1.0
		if _dismount_cosmetic_time >= cos_len:
			_dismount_cosmetic = false

	if is_mounting:
		_update_mount(delta)
		return
	if is_dismounting:
		_update_dismount(delta)
		return
	if is_on_ladder and _active_ladder != null:
		_update_climb()


func _update_mount(delta: float) -> void:
	player.velocity = Vector3.ZERO
	_mount_timer += delta
	var state: String = player.ladder_playback.get_current_node()
	if state == player.LADDER_STATE_MOUNT:
		_mount_entered = true
		if _mount_clip_len <= 0.0:
			_mount_clip_len = _clip_length(player.LADDER_ANIM_MOUNT)

	var finished: bool = _mount_entered and state != player.LADDER_STATE_MOUNT
	if not finished and _mount_entered and _mount_clip_len > 0.0 and _mount_timer >= _mount_clip_len:
		finished = true

	var timed_out: bool = _mount_timer >= player.ladder_mount_max_time
	if finished or timed_out:
		if timed_out and not finished:
			push_warning("Ladder mount resolved via timeout fallback, not naturally — current_state was '%s', entered=%s. Check the 'ladderbuttom_mount' transitions/animation." % [state, _mount_entered])
		# The tree advanced off the mount node; hand control to the climb loop.
		# The timeout is a safety net in case the clip is left looping.
		is_mounting = false
		is_on_ladder = true


func _update_dismount(delta: float) -> void:
	player.velocity = Vector3.ZERO
	_dismount_timer += delta
	var state: String = player.ladder_playback.get_current_node()
	if state == player.LADDER_STATE_DISMOUNT:
		_dismount_entered = true
		if _dismount_clip_len <= 0.0:
			_dismount_clip_len = _clip_length(player.LADDER_ANIM_DISMOUNT)

	var finished: bool = _dismount_entered and state != player.LADDER_STATE_DISMOUNT
	if not finished and _dismount_entered and _dismount_clip_len > 0.0 and _dismount_timer >= _dismount_clip_len:
		finished = true

	var timed_out: bool = _dismount_timer >= player.ladder_dismount_max_time
	if finished or timed_out:
		if timed_out and not finished:
			push_warning("Ladder dismount resolved via timeout fallback, not naturally — current_state was '%s', entered=%s. Check the 'laddertop_dismount' transitions/animation." % [state, _dismount_entered])
		_finish_dismount()


func _update_climb() -> void:
	var climb_input := 0.0
	if Input.is_action_pressed("forward"):
		climb_input += 1.0
	if Input.is_action_pressed("backward"):
		climb_input -= 1.0

	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.velocity.y = climb_input * player.ladder_climb_speed

	player.ladder_playback.travel(player.LADDER_STATE_CLIMB if climb_input != 0.0 else player.LADDER_STATE_IDLE)

	var top_y: float = _active_ladder.get_top_y()
	var bottom_y: float = _active_ladder.get_bottom_y()

	if climb_input > 0.0 and player.global_position.y >= top_y - player.ladder_snap_epsilon:
		player.global_position.y = top_y
		if player.ladder_instant_dismount:
			_instant_dismount()
		else:
			_start_dismount()
	elif climb_input < 0.0 and player.global_position.y <= bottom_y + player.ladder_snap_epsilon:
		player.global_position.y = bottom_y
		exit()


func _start_dismount() -> void:
	is_on_ladder = false
	is_dismounting = true
	_dismount_entered = false
	_dismount_timer = 0.0
	_dismount_clip_len = _clip_length(player.LADDER_ANIM_DISMOUNT)
	player.velocity = Vector3.ZERO
	player.ladder_playback.travel(player.LADDER_STATE_DISMOUNT)


# Instant top release: snap to the TopMarker, hand control back right away, and
# let the dismount clip play as a cosmetic layer (see _dismount_cosmetic).
func _instant_dismount() -> void:
	var fwd := Vector3(sin(player.mannequin.rotation.y), 0.0, cos(player.mannequin.rotation.y))
	if _active_ladder != null:
		var top_pos: Vector3 = _active_ladder.get_top_stand_position()
		player.global_position.x = top_pos.x
		player.global_position.z = top_pos.z
		player.global_position.y = top_pos.y
	# Nudge up + forward off the ladder lip so gravity doesn't slide the player
	# back off the edge next frame.
	player.global_position += fwd * player.ladder_dismount_forward_nudge
	player.ladder_playback.travel(player.LADDER_STATE_DISMOUNT)
	exit()


func _finish_dismount() -> void:
	if _active_ladder != null:
		var top_pos: Vector3 = _active_ladder.get_top_stand_position()
		player.global_position.x = top_pos.x
		player.global_position.z = top_pos.z
	exit()


# Reads a clip's length from the AnimationTree's libraries. Tries the
# "Library/Animation" name first, then scans for a bare-name match.
func _clip_length(anim_name: StringName) -> float:
	var tree: AnimationTree = player.animation_tree
	if tree == null:
		return 0.0
	var anim: Animation = tree.get_animation(anim_name)
	if anim != null:
		return anim.length
	var parts := String(anim_name).split("/")
	var bare := parts[parts.size() - 1]
	for lib_name in tree.get_animation_library_list():
		var lib: AnimationLibrary = tree.get_animation_library(lib_name)
		if lib != null and lib.has_animation(bare):
			return lib.get_animation(bare).length
	return 0.0
