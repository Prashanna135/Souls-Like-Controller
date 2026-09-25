extends Node3D

# Third-person camera rig with optional lock-on. Attach to a pivot node with a
# SpringArm3D + Camera3D child. The character script sets `lock_target` and
# `is_locked_on` when lock-on changes, and toggles `input_enabled` while a menu
# owns the mouse.

@export var cam_v_max       := 75.0
@export var cam_v_min       := -55.0
@export var h_sensitivity   := 0.01
@export var v_sensitivity   := 0.01
@export var h_acceleration  := 10.0
@export var v_acceleration  := 10.0
@export var lock_acceleration := 6.0   # how fast the camera tracks the target when locked

# Tighter pitch range while locked on so a close target can't drag the view
# into the floor or sky.
@export var lock_v_max        := 35.0
@export var lock_v_min        := -30.0
@export var lock_min_distance := 2.5   # floor for the horizontal distance used in the pitch calc

# Child node on the target to aim at. Same anchor lock_reticle.gd uses, so the
# camera and reticle agree on the aim point.
@export var target_anchor_path := NodePath("LockIndicator")

# Extra upward pitch that eases in as the target closes in, so you don't stare
# down at their feet at close range.
@export var lock_close_up_bias_deg := 10.0

# Dynamic zoom-out: pull the spring arm back as the target closes in so both
# characters stay framed. Fades in between lock_zoom_far_dist and
# lock_zoom_near_dist.
@export var lock_zoom_max_length  := 3.5
@export var lock_zoom_near_dist   := 1.5
@export var lock_zoom_far_dist    := 5.0
@export var lock_zoom_smooth      := 5.0

var camrot_h := 0.0
var camrot_v := 0.0

var input_enabled := true

var lock_target : Node3D = null
var is_locked_on := false

# Whether we were locked on last frame, so _physics_process can detect the
# exact frame lock-on engages.
var _was_locked_on := false

var _base_spring_length := 2.0

@onready var h_pivot  : Node3D      = $"."
@onready var v_pivot  : SpringArm3D = $v
@onready var camera_3d: Camera3D    = $v/Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_base_spring_length = v_pivot.spring_length


func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	# Free-look only; while locked on the camera drives itself below.
	if not is_locked_on and event is InputEventMouseMotion:
		camrot_h -= event.relative.x * h_sensitivity
		camrot_v -= event.relative.y * v_sensitivity


# Aim at the target's anchor node if it has one, otherwise its origin.
func _get_aim_point(target: Node3D) -> Vector3:
	var anchor := target.get_node_or_null(target_anchor_path)
	return anchor.global_position if anchor != null else target.global_position


func _physics_process(delta: float) -> void:
	camrot_v = clamp(camrot_v, deg_to_rad(cam_v_min), deg_to_rad(cam_v_max))

	if is_locked_on and lock_target != null:
		# On the frame lock-on engages, snap the free-look targets to the
		# camera's actual rotation. Otherwise the lerp starts from a stale
		# value left by a fast mouse flick and the camera visibly swings.
		if not _was_locked_on:
			camrot_h = h_pivot.rotation.y
			camrot_v = v_pivot.rotation.x

		var aim_point := _get_aim_point(lock_target)
		var to_target := aim_point - h_pivot.global_position

		# Floor the horizontal distance so the pitch doesn't spike to vertical
		# when the target is very close.
		var flat_dist : float = maxf(Vector2(to_target.x, to_target.z).length(), lock_min_distance)
		var real_dist : float = global_position.distance_to(aim_point)

		# Near-zero horizontal offset makes atan2's heading noisy, so hold the
		# last heading below a small threshold instead of recomputing.
		var target_h := camrot_h
		if Vector2(to_target.x, to_target.z).length() > 0.05:
			target_h = atan2(-to_target.x, -to_target.z)

		var target_v : float = atan2(to_target.y, flat_dist)

		# Ease in the upward bias as the target closes, over the same range as
		# the zoom pull-back below.
		var prox_t : float = clamp(inverse_lerp(lock_zoom_far_dist, lock_zoom_near_dist, real_dist), 0.0, 1.0)
		target_v += deg_to_rad(lock_close_up_bias_deg) * prox_t
		target_v  = clamp(target_v, deg_to_rad(lock_v_min), deg_to_rad(lock_v_max))

		camrot_h = lerp_angle(camrot_h, target_h, delta * lock_acceleration)
		camrot_v = lerp_angle(camrot_v, target_v, delta * lock_acceleration)

		h_pivot.rotation.y = camrot_h
		v_pivot.rotation.x = clamp(camrot_v, deg_to_rad(lock_v_min), deg_to_rad(lock_v_max))

		var target_length : float = lerp(_base_spring_length, lock_zoom_max_length, prox_t)
		v_pivot.spring_length = lerp(v_pivot.spring_length, target_length, delta * lock_zoom_smooth)

		_was_locked_on = true
	else:
		h_pivot.rotation.y = lerp_angle(h_pivot.rotation.y, camrot_h, delta * h_acceleration)
		v_pivot.rotation.x = lerp_angle(v_pivot.rotation.x, camrot_v, delta * v_acceleration)

		# Ease back to the normal follow distance once unlocked.
		v_pivot.spring_length = lerp(v_pivot.spring_length, _base_spring_length, delta * lock_zoom_smooth)

		_was_locked_on = false
