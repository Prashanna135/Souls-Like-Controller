extends Node3D
class_name WorldHealthBar

# Floating enemy health bar, drawn above a target and shown only after it takes
# damage. Built from two billboarded quads, so it needs no texture or scene
# setup.
#
# Usage:
#   var bar := WorldHealthBar.new()
#   owner.add_child(bar)
#   bar.setup(owner, 2.1)          owner node, height above its origin
#   bar.set_ratio(current / max)   update whenever health changes

@export var bar_width  := 1.1
@export var bar_height := 0.11
@export var fill_color := Color(0.78, 0.08, 0.06, 1.0)
@export var back_color := Color(0.05, 0.05, 0.05, 0.85)
@export var hide_when_full := true

var _owner_node : Node3D = null
var _height     : float  = 2.1
var _ratio      : float  = 1.0
var _back : MeshInstance3D
var _fill : MeshInstance3D


func setup(owner_node: Node3D, height_above: float = 2.1) -> void:
	_owner_node = owner_node
	_height     = height_above


func _ready() -> void:
	_back = _make_quad(back_color, 0.0)
	_fill = _make_quad(fill_color, 0.01)
	add_child(_back)
	add_child(_fill)
	set_ratio(1.0)


func _make_quad(col: Color, z_offset: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(bar_width, bar_height)
	mi.mesh = quad
	mi.position.z = z_offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.disable_receive_shadows = true
	mi.material_override = mat
	return mi


func set_ratio(r: float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	if _fill == null:
		return

	var quad := _fill.mesh as QuadMesh
	quad.size = Vector2(bar_width * _ratio, bar_height)
	# Shrink from the right so the left edge stays fixed. A QuadMesh is centered,
	# so resizing alone moves both edges; offset the geometry to compensate.
	quad.center_offset = Vector3(-bar_width * (1.0 - _ratio) * 0.5, 0.0, 0.0)
	visible = not (hide_when_full and _ratio >= 0.999)


func _process(_delta: float) -> void:
	if _owner_node != null and is_instance_valid(_owner_node):
		global_position = _owner_node.global_position + Vector3(0.0, _height, 0.0)
