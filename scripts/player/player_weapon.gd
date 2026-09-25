extends Node2D

# Everything to do with the equipped weapon: equipping, draw/sheathe (manual
# and auto), the three-hit attack combo, and the hitbox window that decides
# when a swing can actually deal damage.
#
# The weapon scene itself is instanced by WeaponEquipper (see
# weapon_equipper.gd) — this node owns the timing and state around it. The
# "am I mid-swing" flag lives on the Player root so movement and the other
# systems can read it alongside the rest of the shared state.

var player: CharacterBody3D = null

var equipper: WeaponEquipper = null

var _attack_step := 0       # 0 = none, 1 = A, 2 = B, 3 = C
var _attack_buffered := false
var _attack_entered := false

# Draw/sheathe timing. MeleeLib/WeaponChange_back has no Call Method Track, so
# a fixed delay after the one-shot goes active is what commits the swap.
var _swap_entered := false
var _swap_timer := 0.0

# Auto draw/sheathe: attacking while sheathed draws first, then swings; out of
# combat long enough, the weapon slides back onto the back.
var _attack_after_draw := false
var _combat_timer := 0.0

# The hitbox is switched on for as long as the state machine sits in a swing
# state, tracked so re-entering the same state doesn't re-clear the per-swing
# hit list every frame.
var _hitbox_swing_state := ""


func setup(p_player: CharacterBody3D) -> void:
	player = p_player
	# The equipper instances the weapon scene and wires its hitbox; see
	# weapon_equipper.gd. It's created here so this node fully owns the weapon.
	equipper = WeaponEquipper.new(
		player.weaponattachment,
		self.player,
		player.animation_tree,
		player.WEAPON_CHANGEBACK_ONE_SHOT,
		[&"enemies"],
		player.wepondisplayback,
		player.weapon_sheath_marker)


func is_drawn() -> bool:
	return equipper != null and equipper.is_drawn


func is_swapping() -> bool:
	return equipper != null and equipper.is_swapping


func update_swap(delta: float) -> void:
	_update_swap(delta)


func update_attack() -> void:
	_update_attack_state()


func update_combat(delta: float) -> void:
	_update_combat_timer(delta)
	if _should_auto_sheathe():
		_sheathe()


func equip(weapon: WeaponItem) -> void:
	if weapon == null:
		return
	equipper.equip(weapon)
	# Keep the inventory in sync so the UI knows which row is "equipped".
	player.inventory.equipped_weapon = weapon
	player.inventory.weapon_equipped.emit(weapon)
	player.inventory.inventory_changed.emit()


func start_attack() -> void:
	player.is_attacking = true
	_attack_step = 1
	_attack_buffered = false
	_attack_entered = false
	player.attack_playback.travel(player.STATE_A)


func buffer_attack() -> void:
	if _attack_step < 3:
		_attack_buffered = true


func _update_attack_state() -> void:
	var current: String = player.attack_playback.get_current_node()

	match current:
		player.STATE_A:
			_attack_step = 1
			_attack_entered = true
		player.STATE_B:
			if _attack_step != 2:
				_attack_step = 2
				_attack_buffered = false
			_attack_entered = true
		player.STATE_C:
			if _attack_step != 3:
				_attack_step = 3
				_attack_buffered = false
			_attack_entered = true
		player.STATE_IDLE:
			# Only a real "finished" if a swing was actually entered — otherwise
			# this is just the machine still sitting on SwordIdle while travel()
			# waits for its Immediate switch into Sword_Regular_A.
			if _attack_entered:
				_end_attack()

	_update_hitbox_window(current)

	player.animation_tree.set(player.COND_CHAIN_B, _attack_buffered and _attack_step == 1)
	player.animation_tree.set(player.COND_NO_CHAIN_B, not (_attack_buffered and _attack_step == 1))
	player.animation_tree.set(player.COND_CHAIN_C, _attack_buffered and _attack_step == 2)
	player.animation_tree.set(player.COND_NO_CHAIN_C, not (_attack_buffered and _attack_step == 2))


func _end_attack() -> void:
	player.is_attacking = false
	_attack_step = 0
	_attack_buffered = false
	_attack_entered = false
	player.current_speed = player.sprint_speed
	_close_hitbox_window()


# Interrupts a swing (e.g. when hit) and resets the chain conditions.
func abort_attack() -> void:
	player.is_attacking = false
	_attack_step = 0
	_attack_buffered = false
	_attack_entered = false
	_close_hitbox_window()
	player.animation_tree.set(player.COND_CHAIN_B, false)
	player.animation_tree.set(player.COND_NO_CHAIN_B, true)
	player.animation_tree.set(player.COND_CHAIN_C, false)
	player.animation_tree.set(player.COND_NO_CHAIN_C, true)


# The swing clips have no Call Method Tracks switching the hitbox on, so it's
# toggled off the AnimationTree's current state instead — on for as long as the
# machine sits in a swing state, off the instant it leaves.
func _update_hitbox_window(current_state: String) -> void:
	if equipper == null or equipper.current_hitbox == null:
		return
	var is_swing: bool = current_state == player.STATE_A or current_state == player.STATE_B or current_state == player.STATE_C
	if is_swing and current_state != _hitbox_swing_state:
		equipper.current_hitbox.enable_hitbox()
		_hitbox_swing_state = current_state
	elif not is_swing and _hitbox_swing_state != "":
		equipper.current_hitbox.disable_hitbox()
		_hitbox_swing_state = ""


func _close_hitbox_window() -> void:
	if _hitbox_swing_state != "" and equipper != null and equipper.current_hitbox != null:
		equipper.current_hitbox.disable_hitbox()
	_hitbox_swing_state = ""


# The swing's forward/back travel is baked into the Root bone track. Read the
# frame's delta out of the AnimationTree and rotate it into world space with
# the skeleton's basis so it moves the way the character is facing.
func apply_attack_root_motion(delta: float) -> void:
	var root_motion: Vector3 = player.animation_tree.get_root_motion_position()
	var world_motion: Vector3 = player.skeleton.global_transform.basis * root_motion
	world_motion.y = 0.0   # gravity already handles vertical movement
	if delta > 0.0:
		player.velocity.x = world_motion.x / delta
		player.velocity.z = world_motion.z / delta
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0


func toggle_draw() -> void:
	if equipper == null or equipper.current_weapon == null:
		return   # bare-handed — nothing to sheathe or draw
	if equipper.request_drawn(not equipper.is_drawn):
		_swap_entered = false
		_swap_timer = 0.0
		_combat_timer = 0.0   # a manual toggle counts as combat, so it isn't instantly re-sheathed


# Left-clicked while sheathed: start the draw and swing once it commits.
func request_draw_for_attack() -> void:
	if equipper == null or equipper.current_weapon == null:
		return
	if equipper.request_drawn(true):
		_swap_entered = false
		_swap_timer = 0.0
		_attack_after_draw = true
		_combat_timer = 0.0


# Draws the equipped weapon if it's sheathed and nothing is mid-swap.
func draw_if_sheathed() -> void:
	if equipper == null or equipper.current_weapon == null:
		return
	if equipper.is_drawn or equipper.is_swapping:
		return
	if equipper.request_drawn(true):
		_swap_entered = false
		_swap_timer = 0.0
		_combat_timer = 0.0


func _sheathe() -> void:
	if equipper == null or equipper.current_weapon == null:
		return
	if equipper.request_drawn(false):
		_swap_entered = false
		_swap_timer = 0.0


# Commits the swap weaponswap_commit_delay seconds after the one-shot goes
# active; weaponswap_max_time is a fallback if the active flag never registers.
func _update_swap(delta: float) -> void:
	if equipper == null or not equipper.is_swapping:
		return
	_swap_timer += delta
	if player.animation_tree.get(player.WEAPON_CHANGEBACK_ACTIVE):
		_swap_entered = true

	if _swap_entered and _swap_timer >= player.weaponswap_commit_delay:
		equipper.apply_pending_draw_state(true)
		_try_queued_attack()
		return
	if _swap_timer >= player.weaponswap_max_time:
		equipper.apply_pending_draw_state()
		_try_queued_attack()


# Optional: call from a Call Method Track on MeleeLib/WeaponChange_back at the
# exact sheath/hilt frame instead of relying on weaponswap_commit_delay.
func on_swap_commit() -> void:
	if equipper != null:
		equipper.apply_pending_draw_state(true)
	_try_queued_attack()


func _try_queued_attack() -> void:
	if not _attack_after_draw:
		return
	_attack_after_draw = false
	if equipper == null or not equipper.is_drawn:
		return
	if player.is_attacking or player.is_rolling or player.is_jumpback or player.reaction.is_stunned() or player.is_dead:
		return
	if not player.is_on_floor():
		return
	start_attack()


func mark_in_combat() -> void:
	_combat_timer = 0.0


func _update_combat_timer(delta: float) -> void:
	if player.lock_on.is_locked_on or player.is_attacking or _attack_after_draw or _enemy_aggroed_near():
		_combat_timer = 0.0
	else:
		_combat_timer += delta


func _enemy_aggroed_near() -> bool:
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e is Node3D \
				and (not ("is_dead" in e) or not e.is_dead) \
				and ("_has_aggro" in e) and e._has_aggro \
				and player.global_position.distance_to(e.global_position) <= player.auto_sheathe_enemy_range:
			return true
	return false


func _should_auto_sheathe() -> bool:
	if equipper == null or equipper.current_weapon == null:
		return false
	if not equipper.is_drawn or equipper.is_swapping:
		return false
	if player.is_attacking or player.is_rolling or player.is_jumpback or player.reaction.is_stunned() or player.is_hard_landing or player.consumable.is_consuming or player.door.is_opening or player.is_dead:
		return false
	if player.ladder.is_busy():
		return false
	return _combat_timer >= player.auto_sheathe_delay
