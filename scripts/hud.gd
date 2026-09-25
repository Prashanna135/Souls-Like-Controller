extends Control
class_name PlayerHUD

# Screen-space HUD drawn with _draw(), so it needs no textures or scene setup:
#   * Player health bar, top-left.
#   * Boss health bar, top-center, shown only while an aggroed boss is alive.
#
# player.gd creates it in _ready():
#   var layer := CanvasLayer.new()
#   add_child(layer)
#   var hud := PlayerHUD.new()
#   layer.add_child(hud)
#   hud.setup(self)

@export var player_color := Color(0.72, 0.1, 0.08, 1.0)
@export var back_color   := Color(0.06, 0.06, 0.06, 0.82)
@export var border_color := Color(0.85, 0.85, 0.85, 0.9)
@export var boss_color   := Color(0.72, 0.1, 0.08, 1.0)

const PLAYER_BAR_SIZE  := Vector2(320.0, 20.0)
const BOSS_BAR_SIZE    := Vector2(620.0, 22.0)
const PLAYER_MARGIN    := Vector2(28.0, 24.0)
# Boss bar sits at the very top of the screen, centered — lower than this and
# it reads as a second player bar stacked under the top-left one.
const BOSS_TOP_MARGIN  := 18.0

var player : Node = null
var _boss  : Node = null


func setup(p_player: Node) -> void:
	player = p_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	_boss = _find_boss()
	queue_redraw()


func _find_boss() -> Node:
	if player == null or not is_instance_valid(player):
		return null
	var best : Node = null
	var best_dist := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not ("is_boss" in e) or not e.is_boss:
			continue
		if ("is_dead" in e) and e.is_dead:
			continue
		# Only show the bar once the boss is actually fighting.
		if ("_has_aggro" in e) and not e._has_aggro:
			continue
		var d : float = player.global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _get_ratio(node: Node) -> float:
	if node == null or not ("current_health" in node) or not ("max_health" in node):
		return 0.0
	if node.max_health <= 0.0:
		return 0.0
	return clampf(node.current_health / node.max_health, 0.0, 1.0)


func _draw() -> void:
	_draw_bar(PLAYER_MARGIN, PLAYER_BAR_SIZE, _get_ratio(player), player_color)

	if _boss != null:
		# Center against the real viewport width, not `size` — this Control
		# lives on a bare CanvasLayer, so its own size isn't guaranteed to
		# track the screen and `size.x` centered the bar on the left edge.
		var view_w := get_viewport_rect().size.x
		var bx     := (view_w - BOSS_BAR_SIZE.x) * 0.5
		_draw_bar(Vector2(bx, BOSS_TOP_MARGIN), BOSS_BAR_SIZE, _get_ratio(_boss), boss_color)


func _draw_bar(pos: Vector2, bar_size: Vector2, ratio: float, fill: Color) -> void:
	var rect := Rect2(pos, bar_size)
	draw_rect(rect, back_color)
	if ratio > 0.0:
		draw_rect(Rect2(pos, Vector2(bar_size.x * ratio, bar_size.y)), fill)
	draw_rect(rect, border_color, false, 2.0)
