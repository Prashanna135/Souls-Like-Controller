extends Control
class_name LockReticle

# Lock-on marker drawn in screen space at the target's projected position,
# rather than as a 3D object. A screen-space draw avoids depth-buffer issues
# with the target/player meshes, uses a line-of-sight raycast so it hides
# behind walls, and keeps a fixed pixel size regardless of distance.
#
# Scene setup (player.tscn):
#   Player
#     LockOnUI (CanvasLayer)
#       LockReticle (Control, this script, Anchor Preset: Full Rect)
#
# player.gd sets `player` and `camera` in _ready() and calls set_target() from
# its lock-on code.

@export var reticle_size  := 28.0
@export var reticle_color := Color(0.95, 0.15, 0.1, 1.0)
@export var outline_color := Color(0.3, 0.02, 0.0, 0.9)
@export var pulse_speed   := 180.0
@export var pulse_amount  := 0.12

# Child node on the target to aim at (chest/neck height anchor).
@export var target_anchor_path := NodePath("LockIndicator")

var player : Node3D   = null
var camera : Camera3D = null
var target : Node3D   = null

var _has_los    := false
var _screen_pos := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if ("is_dead" in target) and target.is_dead:
		visible = false
		return

	_has_los = _update_screen_position()
	visible  = _has_los
	if _has_los:
		queue_redraw()


func set_target(new_target: Node3D) -> void:
	target   = new_target
	_has_los = false
	visible  = false


func _get_anchor_position() -> Variant:
	if target == null or not is_instance_valid(target):
		return null
	var anchor := target.get_node_or_null(target_anchor_path)
	return (anchor.global_position if anchor != null else target.global_position)


func _update_screen_position() -> bool:
	if not is_instance_valid(target) or camera == null:
		return false

	var world_pos = _get_anchor_position()
	if world_pos == null:
		return false

	if camera.is_position_behind(world_pos):
		return false

	if not _has_line_of_sight(world_pos):
		return false

	_screen_pos = camera.unproject_position(world_pos)
	return true


func _draw() -> void:
	if not _has_los:
		return

	var screen_pos := _screen_pos
	var pulse := 1.0 + pulse_amount * sin(Time.get_ticks_msec() / pulse_speed)
	var r      := reticle_size * 0.5 * pulse

	var outline_points := PackedVector2Array([
		screen_pos + Vector2(0.0, -r),
		screen_pos + Vector2(r, 0.0),
		screen_pos + Vector2(0.0, r),
		screen_pos + Vector2(-r, 0.0),
	])
	draw_colored_polygon(outline_points, outline_color)

	var inner := r * 0.6
	var inner_points := PackedVector2Array([
		screen_pos + Vector2(0.0, -inner),
		screen_pos + Vector2(inner, 0.0),
		screen_pos + Vector2(0.0, inner),
		screen_pos + Vector2(-inner, 0.0),
	])
	draw_colored_polygon(inner_points, reticle_color)


func _has_line_of_sight(world_pos: Vector3) -> bool:
	if player == null:
		return true

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, world_pos)

	# Exclude the target and the player so the ray doesn't hit either of their
	# own colliders (the camera can sit close to the player's capsule at range).
	var exclude : Array[RID] = []
	if target != null and target.has_method("get_rid"):
		exclude.append(target.get_rid())
	if player.has_method("get_rid"):
		exclude.append(player.get_rid())
	query.exclude = exclude

	query.collide_with_areas  = false
	query.collide_with_bodies = true

	var hit := space_state.intersect_ray(query)
	return hit.is_empty()
