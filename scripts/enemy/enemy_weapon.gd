extends Node2D

# The enemy's weapon: the three-hit attack combo, the equip hookup, and the
# hitbox window that decides when a swing can actually deal damage. Same
# weapon-scene system as the player (see weapon_equipper.gd), minus the
# inventory/UI — enemies spawn already equipped.
#
# Swings are driven by the AI (enemy_ai.gd calls start_attack()); this node
# just runs the combo and the hitbox timing.

var enemy: CharacterBody3D = null

var weapon_equipper : WeaponEquipper = null

# 0 = none, 1 = A, 2 = B, 3 = C
var _attack_step     := 0
var _attack_buffered := false
var _attack_entered  := false   # true once the state machine has actually reached A/B/C
var _attack_cooldown_timer := 0.0

# The hitbox is switched on for as long as the state machine sits in a swing
# state, tracked so re-entering the same state doesn't re-clear it every frame.
var _hitbox_swing_state := ""


func setup(p_enemy: CharacterBody3D) -> void:
	enemy = p_enemy
	weapon_equipper = WeaponEquipper.new(enemy.weaponattachment, enemy, enemy.animation_tree, enemy.WEAPON_CHANGEBACK_ONE_SHOT, [&"player"])
	if enemy.starting_weapon != null:
		weapon_equipper.equip(enemy.starting_weapon)
	else:
		push_warning("Enemy '%s' has no 'starting_weapon' assigned — attacks won't deal damage until a weapon is equipped. See weapon_equipper.gd's header comment for how to build one." % enemy.name)


func tick(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta


func is_cooling_down() -> bool:
	return _attack_cooldown_timer > 0.0


func start_attack() -> void:
	enemy.is_attacking = true
	_attack_step     = 1
	_attack_buffered = false
	_attack_entered  = false
	enemy.attack_playback.travel(enemy.STATE_A)


func update_attack(dist: float, has_target: bool) -> void:
	var current : String = enemy.attack_playback.get_current_node()

	match current:
		enemy.STATE_A:
			_attack_step    = 1
			_attack_entered = true
		enemy.STATE_B:
			if _attack_step != 2:
				_attack_step     = 2
				_attack_buffered = false
			_attack_entered = true
		enemy.STATE_C:
			if _attack_step != 3:
				_attack_step     = 3
				_attack_buffered = false
			_attack_entered = true
		enemy.STATE_IDLE:
			# Only a real "attack finished" if we've actually entered the swing
			# at least once — otherwise this is just the state machine still
			# sitting on SwordIdle while travel() waits for its Immediate switch
			# into Sword_Regular_A.
			if _attack_entered:
				_end_attack()

	_update_hitbox_window(current)

	enemy.animation_tree.set(enemy.COND_CHAIN_B,    _attack_buffered and _attack_step == 1)
	enemy.animation_tree.set(enemy.COND_NO_CHAIN_B, not (_attack_buffered and _attack_step == 1))
	enemy.animation_tree.set(enemy.COND_CHAIN_C,    _attack_buffered and _attack_step == 2)
	enemy.animation_tree.set(enemy.COND_NO_CHAIN_C, not (_attack_buffered and _attack_step == 2))

	# Keep chaining as long as the target is still in range; once it steps out
	# (or the combo ends) the state machine returns to SwordIdle on its own.
	_attack_buffered = has_target and _attack_step < 3 and dist <= enemy.attack_range


func _end_attack() -> void:
	enemy.is_attacking     = false
	_attack_step           = 0
	_attack_buffered       = false
	_attack_entered        = false
	_attack_cooldown_timer = enemy.attack_cooldown
	# Force a fresh decision the instant the combo ends instead of waiting out
	# whatever was left on the old timer, so the AI reliably backs off or
	# repositions right after swinging rather than standing there.
	enemy.ai.reset_decision()
	close_hitbox()


# Interrupts a swing without running the cooldown — used when a hit lands
# mid-attack (see enemy_reaction.gd).
func abort_attack() -> void:
	enemy.is_attacking = false
	_attack_step     = 0
	_attack_buffered = false
	_attack_entered  = false
	close_hitbox()
	enemy.animation_tree.set(enemy.COND_CHAIN_B,    false)
	enemy.animation_tree.set(enemy.COND_NO_CHAIN_B, true)
	enemy.animation_tree.set(enemy.COND_CHAIN_C,    false)
	enemy.animation_tree.set(enemy.COND_NO_CHAIN_C, true)


# Death path: drop the swing and the hitbox, but leave the chain conditions
# alone — nothing reads them once the enemy is dead.
func reset_attack() -> void:
	enemy.is_attacking = false
	_attack_step     = 0
	_attack_buffered = false
	_attack_entered  = false
	close_hitbox()


# Same fix as player_weapon.gd's hitbox window. Short version: no Call Method
# Track on Sword_Regular_A/B/C ever calls enable_hitbox()/disable_hitbox(), so
# the hitbox was permanently non-monitoring and swings never connected.
# Toggling it off the AnimationTree's current swing state fixes that without
# touching the .tscn.
func _update_hitbox_window(current_state: String) -> void:
	if weapon_equipper == null or weapon_equipper.current_hitbox == null:
		return

	var is_swing : bool = current_state == enemy.STATE_A or current_state == enemy.STATE_B or current_state == enemy.STATE_C

	if is_swing and current_state != _hitbox_swing_state:
		weapon_equipper.current_hitbox.enable_hitbox()
		_hitbox_swing_state = current_state
	elif not is_swing and _hitbox_swing_state != "":
		weapon_equipper.current_hitbox.disable_hitbox()
		_hitbox_swing_state = ""


func close_hitbox() -> void:
	if _hitbox_swing_state != "" and weapon_equipper != null and weapon_equipper.current_hitbox != null:
		weapon_equipper.current_hitbox.disable_hitbox()
	_hitbox_swing_state = ""


# The swing's travel is baked into the Root bone track. Read the frame's delta
# out of the AnimationTree and rotate it into world space with the skeleton's
# basis so it moves the way the enemy is facing.
func apply_root_motion(delta: float) -> void:
	var root_motion : Vector3 = enemy.animation_tree.get_root_motion_position()
	var world_motion : Vector3 = enemy.skeleton.global_transform.basis * root_motion
	world_motion.y = 0.0   # gravity already handles vertical movement

	if delta > 0.0:
		enemy.velocity.x = world_motion.x / delta
		enemy.velocity.z = world_motion.z / delta
	else:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
