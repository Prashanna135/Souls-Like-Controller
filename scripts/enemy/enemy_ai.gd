extends Node2D

# Enemy AI. Owns perception (the detectarea/behind Area3D signals), the
# idle -> chase -> combat state machine, patrol-point wandering, and the
# close-range strafe/retreat/attack decisions. It writes _has_aggro back onto
# the enemy root, which hud.gd and the player's auto-sheathe read by name.
#
# The root calls update() every physics frame and then dispatches movement off
# the state this exposes (see enemy.gd's _physics_process).

var enemy: CharacterBody3D = null

enum State { IDLE, CHASE, COMBAT, ATTACK }
var current_state : State = State.IDLE

enum CombatAction { NONE, STRAFE_LEFT, STRAFE_RIGHT, RETREAT }
var _combat_action   : CombatAction = CombatAction.NONE
var _in_attack_range := false
var _decision_timer  := 0.0

var player_target : Node3D = null

# Perception (driven by the detectarea / behind Area3D signals)
var _player_in_detect_zone := false
var _player_in_blind_spot  := false

# Patrol runtime state
var _patrol_origin : Node3D = null
var _patrol_target := Vector3.ZERO
var _patrol_wait   := 0.0
var _has_patrol    := false


func setup(p_enemy: CharacterBody3D) -> void:
	enemy = p_enemy

	enemy.navigation_agent_3d.path_desired_distance   = 0.5
	enemy.navigation_agent_3d.target_desired_distance = 0.5

	if enemy.detectarea != null:
		enemy.detectarea.body_entered.connect(_on_detect_body_entered)
		enemy.detectarea.body_exited.connect(_on_detect_body_exited)
	else:
		push_warning("Enemy '%s' has no 'detectarea' Area3D — it will never detect the player." % enemy.name)

	if enemy.behind != null:
		enemy.behind.body_entered.connect(_on_behind_body_entered)
		enemy.behind.body_exited.connect(_on_behind_body_exited)
	else:
		push_warning("Enemy '%s' has no 'behind' Area3D — it will have no blind spot." % enemy.name)

	# Deferred so the rest of the scene (including the player) is fully ready.
	call_deferred("_find_player")
	call_deferred("_claim_patrol_point")


# Returns the distance to the player (INF if there isn't one) so the root can
# reuse it instead of measuring again.
func update() -> float:
	var dist := INF
	if player_target != null:
		dist = enemy.global_position.distance_to(player_target.global_position)

	if not enemy._has_aggro and _player_in_detect_zone and not _player_in_blind_spot:
		enemy._has_aggro = true

	if not enemy._has_aggro or player_target == null or dist > enemy.lose_range:
		enemy._has_aggro = false
		current_state = State.IDLE
	elif current_state == State.COMBAT:
		# Stay in combat until the player clears the range by the hysteresis
		# margin — prevents CHASE/COMBAT flicker at the boundary.
		if dist > enemy.combat_range + enemy.combat_range_hysteresis:
			current_state = State.CHASE
		else:
			current_state = State.COMBAT
	elif dist <= enemy.combat_range:
		current_state = State.COMBAT
	else:
		current_state = State.CHASE

	if current_state != State.COMBAT:
		_combat_action = CombatAction.NONE

	return dist


func is_idle() -> bool:
	return current_state == State.IDLE


func is_combat() -> bool:
	return current_state == State.COMBAT


func is_chasing() -> bool:
	return current_state == State.CHASE


# Called by the weapon when a combo ends or a hit interrupts the enemy, so the
# next combat tick re-rolls immediately instead of waiting out the old timer.
func reset_decision() -> void:
	_combat_action  = CombatAction.NONE
	_decision_timer = 0.0


func nav_direction() -> Vector3:
	if player_target == null:
		return Vector3.ZERO
	return _nav_direction_to(player_target.global_position)


func _nav_direction_to(target_pos: Vector3) -> Vector3:
	enemy.navigation_agent_3d.target_position = target_pos

	if enemy.navigation_agent_3d.is_navigation_finished():
		return Vector3.ZERO

	var next_pos: Vector3 = enemy.navigation_agent_3d.get_next_path_position()
	var dir: Vector3 = next_pos - enemy.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return Vector3.ZERO
	return dir.normalized()


func run_combat(delta: float, dist: float) -> void:
	if player_target == null:
		return

	# Hysteresis: close until well inside attack_range, and once engaged don't
	# drop back to approach until the player steps clearly past it.
	var engage_range: float = enemy.attack_range if _in_attack_range else enemy.attack_range + enemy.attack_range_hysteresis
	if dist > engage_range:
		_in_attack_range = false
		enemy.move_in_direction(nav_direction(), delta)
		return
	_in_attack_range = true

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_pick_combat_action()

	match _combat_action:
		CombatAction.STRAFE_LEFT, CombatAction.STRAFE_RIGHT:
			_strafe(delta, _combat_action)
		CombatAction.RETREAT:
			_retreat(delta)
		CombatAction.NONE:
			# Just committed to an attack this tick (or is between decisions).
			enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.sprint_speed * 2.0)
			enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.sprint_speed * 2.0)
			enemy.face_target(delta)


func _pick_combat_action() -> void:
	_decision_timer = randf_range(enemy.decision_interval_min, enemy.decision_interval_max)

	if enemy.weapon.is_cooling_down():
		# Still cooling down from the last combo — never stand still waiting it
		# out, always reposition so the fight keeps moving.
		var roll := randf()
		if roll < 0.5:
			_combat_action = CombatAction.RETREAT
		elif roll < 0.75:
			_combat_action = CombatAction.STRAFE_LEFT
		else:
			_combat_action = CombatAction.STRAFE_RIGHT
		return

	var roll := randf()
	if roll < enemy.attack_chance and enemy.is_on_floor():
		_combat_action = CombatAction.NONE
		enemy.weapon.start_attack()
	elif roll < enemy.attack_chance + enemy.strafe_chance:
		_combat_action = CombatAction.STRAFE_LEFT if randf() < 0.5 else CombatAction.STRAFE_RIGHT
	else:
		_combat_action = CombatAction.RETREAT


func _strafe(delta: float, direction: CombatAction) -> void:
	var to_target := player_target.global_position - enemy.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return

	var fwd      := to_target.normalized()
	var right    := fwd.cross(Vector3.UP)
	var move_dir := right if direction == CombatAction.STRAFE_LEFT else -right

	enemy.velocity.x = move_dir.x * enemy.strafe_speed
	enemy.velocity.z = move_dir.z * enemy.strafe_speed
	enemy.face_target(delta)


func _retreat(delta: float) -> void:
	var away := enemy.global_position - player_target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		return
	away = away.normalized()

	var dist_now := enemy.global_position.distance_to(player_target.global_position)
	if dist_now >= enemy.retreat_distance:
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.sprint_speed * 2.0)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.sprint_speed * 2.0)
	else:
		enemy.velocity.x = away.x * enemy.strafe_speed
		enemy.velocity.z = away.z * enemy.strafe_speed

	enemy.face_target(delta)


# Claims the nearest unclaimed marker in patrol_points_group at spawn and tags
# it via metadata so other enemies skip it. No markers: idles in place.
func _claim_patrol_point() -> void:
	var best   : Node3D = null
	var best_d := INF
	for m in enemy.get_tree().get_nodes_in_group(enemy.patrol_points_group):
		if not (m is Node3D):
			continue
		if m.has_meta("patrol_claimed"):
			continue
		var d : float = enemy.global_position.distance_to((m as Node3D).global_position)
		if d < best_d:
			best_d = d
			best   = m
	# Ignore markers too far away so an enemy on the far side of the map doesn't
	# trek across the level to a marker it never spawned near.
	if best != null and best_d > enemy.patrol_max_claim_distance:
		best = null
	if best != null:
		best.set_meta("patrol_claimed", true)
		_patrol_origin = best
		_has_patrol    = true
		_patrol_target = best.global_position
		_patrol_wait   = randf_range(enemy.patrol_wait_min, enemy.patrol_wait_max)


func run_patrol(delta: float) -> void:
	if not _has_patrol or _patrol_origin == null or not is_instance_valid(_patrol_origin):
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.sprint_speed * 2.0)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.sprint_speed * 2.0)
		return

	# Pause a moment at each point before choosing the next.
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.sprint_speed * 2.0)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.sprint_speed * 2.0)
		return

	var to := _patrol_target - enemy.global_position
	to.y = 0.0
	if to.length() < 0.6:
		_patrol_wait = randf_range(enemy.patrol_wait_min, enemy.patrol_wait_max)
		_pick_patrol_target()
		return

	enemy.move_in_direction(_nav_direction_to(_patrol_target), delta)


func _pick_patrol_target() -> void:
	var ang := randf() * TAU
	var r   : float = randf() * enemy.patrol_radius
	_patrol_target = _patrol_origin.global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _find_player() -> void:
	var found := enemy.get_tree().get_first_node_in_group("player")
	if found == null:
		found = enemy.get_tree().current_scene.find_child("Player", true, false)
	player_target = found


# detectarea is the front sight radius, behind is the blind spot punched out of it.
func _on_detect_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_detect_zone = true


func _on_detect_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_detect_zone = false


func _on_behind_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_blind_spot = true


func _on_behind_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_blind_spot = false
