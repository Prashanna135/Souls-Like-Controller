extends Node2D

# Hit reactions and damage. take_damage() is the entry point weapon hitboxes
# call; it chains hurt -> knocked_down -> getting_up, or kills the player.
# Damage that shouldn't stagger (falls) edits health directly from player.gd
# instead of going through here.

var player: CharacterBody3D = null

var is_hurt := false
var is_knocked_down := false
var is_getting_up := false
var _knockdown_timer := 0.0

# Entry-confirmation gates: a one-shot's "active" flag doesn't go true on the
# frame it's requested, so the finish check needs these to avoid ending early.
var _hurt_entered := false
var _knockback_entered := false
var _getup_entered := false


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func is_stunned() -> bool:
	return is_hurt or is_knocked_down or is_getting_up


func take_damage(amount: float, source_position: Vector3) -> void:
	# Climbing and existing hit reactions are untouchable.
	if player.is_dead or is_stunned() or player.ladder.is_busy():
		return

	# Hard-landing / consuming / door-opening are deliberately NOT guarded
	# above — getting hit mid-heal or mid-recovery should interrupt rather than
	# being untouchable.
	player.current_health = maxf(0.0, player.current_health - amount)
	player.is_hard_landing = false
	player.consumable.cancel()
	player.door.cancel()
	player.weapon.mark_in_combat()

	if player.current_health <= 0.0:
		player.die()
		return

	var away_dir := _face_hit_source(source_position)
	if amount >= player.heavy_damage_threshold:
		_start_knockback(away_dir)
	else:
		_start_hurt(away_dir)


func _face_hit_source(source_position: Vector3) -> Vector3:
	# Getting hit interrupts everything except another hit reaction.
	if player.is_attacking:
		player.weapon.abort_attack()
	player.is_rolling = false
	player.is_jumpback = false
	player.jumpback_started = false
	player.current_speed = player.sprint_speed

	var to_source := source_position - player.global_position
	to_source.y = 0.0
	if to_source.length() > 0.01:
		player.mannequin.rotation.y = atan2(to_source.x, to_source.z)
		return -to_source.normalized()

	# No usable source — stagger straight backward from current facing.
	return -Vector3(sin(player.mannequin.rotation.y), 0.0, cos(player.mannequin.rotation.y))


func _start_hurt(away_dir: Vector3) -> void:
	is_hurt = true
	_hurt_entered = false
	player.velocity.x = away_dir.x * player.hurt_push_force
	player.velocity.z = away_dir.z * player.hurt_push_force
	player.animation_tree.set(player.HURT_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _start_knockback(away_dir: Vector3) -> void:
	is_knocked_down = true
	_knockback_entered = false
	_knockdown_timer = 0.0
	player.velocity = away_dir * player.knockback_force
	player.velocity.y = player.knockback_lift
	player.animation_tree.set(player.KNOCKBACK_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func update(delta: float) -> void:
	if is_hurt:
		var active: bool = player.animation_tree.get(player.HURT_ACTIVE)
		if active:
			_hurt_entered = true
		elif _hurt_entered:
			is_hurt = false
			player.current_speed = player.sprint_speed

	if is_knocked_down:
		_knockdown_timer += delta
		var active: bool = player.animation_tree.get(player.KNOCKBACK_ACTIVE)
		if active:
			_knockback_entered = true
		if (_knockback_entered and not active) or _knockdown_timer >= player.heavy_knockdown_max_time:
			is_knocked_down = false
			is_getting_up = true
			_getup_entered = false
			player.animation_tree.set(player.LAYTOIDLE_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	if is_getting_up:
		var active: bool = player.animation_tree.get(player.LAYTOIDLE_ACTIVE)
		if active:
			_getup_entered = true
		elif _getup_entered:
			is_getting_up = false
			player.current_speed = player.sprint_speed
