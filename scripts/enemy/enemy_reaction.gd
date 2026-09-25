extends Node2D

# Damage, hit reactions and death. take_damage() is what weapon hitboxes reach
# (routed through enemy.gd); it chains hurt -> knocked_down -> getting_up, or
# kills the enemy at 0 health. The floating health bar lives here too — bosses
# skip it and drive the top-center HUD bar instead (see hud.gd).

var enemy: CharacterBody3D = null

var is_hurt         := false
var is_knocked_down := false
var is_getting_up   := false
var _knockdown_timer := 0.0

# Entry-confirmation gates: a one-shot's "active" flag doesn't go true on the
# frame it's requested, so the finish check needs these to avoid ending early.
var _hurt_entered      := false
var _knockback_entered := false
var _getup_entered     := false

var _health_bar     : WorldHealthBar = null
var _death_blend    := 0.0
var _death_param_ok := false
var _death_timer    := 0.0


func setup(p_enemy: CharacterBody3D) -> void:
	enemy = p_enemy
	_death_param_ok = enemy.has_anim_param(enemy.DEATH_BLEND_AMOUNT)

	# Bosses drive the top-center HUD bar instead of a floating one.
	if not enemy.is_boss:
		_health_bar = WorldHealthBar.new()
		enemy.add_child(_health_bar)
		_health_bar.setup(enemy, 2.1)
		_health_bar.set_ratio(1.0)


func is_stunned() -> bool:
	return is_hurt or is_knocked_down or is_getting_up


# Called by enemy.gd when a weapon hitbox connects. Reduces health, updates the
# bar, and triggers a hurt or knockback reaction (or death at 0).
# `source_position` is where the hit came from, used to face and shove.
func take_damage(amount: float, source_position: Vector3) -> void:
	if enemy.is_dead:
		return

	enemy.current_health = maxf(0.0, enemy.current_health - amount)
	if _health_bar != null:
		_health_bar.set_ratio(enemy.current_health / enemy.max_health)

	if enemy.current_health <= 0.0:
		die()
		return

	if is_stunned():
		return

	var away_dir := _face_hit_source(source_position)

	if amount >= enemy.heavy_damage_threshold:
		_start_knockback(away_dir)
	else:
		_start_hurt(away_dir)


func _face_hit_source(source_position: Vector3) -> Vector3:
	# Cancel whatever the enemy was mid-doing — getting hit interrupts
	# everything except another hit reaction.
	if enemy.is_attacking:
		enemy.weapon.abort_attack()
	enemy.ai.reset_decision()

	var to_source := source_position - enemy.global_position
	to_source.y = 0.0
	if to_source.length() > 0.01:
		enemy.mannequin.rotation.y = atan2(to_source.x, to_source.z)
		return -to_source.normalized()

	# No usable source — stagger straight backward from current facing.
	return -Vector3(sin(enemy.mannequin.rotation.y), 0.0, cos(enemy.mannequin.rotation.y))


func _start_hurt(away_dir: Vector3) -> void:
	is_hurt       = true
	_hurt_entered = false
	enemy.velocity.x = away_dir.x * enemy.hurt_push_force
	enemy.velocity.z = away_dir.z * enemy.hurt_push_force
	enemy.animation_tree.set(enemy.HURT_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _start_knockback(away_dir: Vector3) -> void:
	is_knocked_down    = true
	_knockback_entered = false
	_knockdown_timer   = 0.0
	enemy.velocity   = away_dir * enemy.knockback_force
	enemy.velocity.y = enemy.knockback_lift
	enemy.animation_tree.set(enemy.KNOCKBACK_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# Advances hurt -> knocked_down -> getting_up. Nothing else should touch those
# flags except take_damage().
func update(delta: float) -> void:
	if is_hurt:
		var hurt_active : bool = enemy.animation_tree.get(enemy.HURT_ACTIVE)
		if hurt_active:
			_hurt_entered = true
		elif _hurt_entered:
			is_hurt = false

	if is_knocked_down:
		_knockdown_timer += delta
		var knockback_active : bool = enemy.animation_tree.get(enemy.KNOCKBACK_ACTIVE)
		if knockback_active:
			_knockback_entered = true
		if (_knockback_entered and not knockback_active) or _knockdown_timer >= enemy.heavy_knockdown_max_time:
			is_knocked_down = false
			is_getting_up   = true
			_getup_entered  = false
			enemy.animation_tree.set(enemy.LAYTOIDLE_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	if is_getting_up:
		var getup_active : bool = enemy.animation_tree.get(enemy.LAYTOIDLE_ACTIVE)
		if getup_active:
			_getup_entered = true
		elif _getup_entered:
			is_getting_up = false


func die() -> void:
	enemy.is_dead = true
	enemy.weapon.reset_attack()
	enemy.ai.reset_decision()
	is_hurt         = false
	is_knocked_down = false
	is_getting_up   = false
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if enemy.detectarea != null:
		enemy.detectarea.set_deferred("monitoring", false)
	if enemy.behind != null:
		enemy.behind.set_deferred("monitoring", false)
	if _health_bar != null:
		_health_bar.visible = false
	if _death_param_ok:
		enemy.animation_tree.set(enemy.DEATH_BLEND_AMOUNT, 0.0)
	_death_timer = 0.0
	# Leave the "enemies" group so the player can't lock onto (or cycle to) a
	# corpse, and drop the lock-on indicator if we were the locked target.
	enemy.remove_from_group("enemies")
	enemy.add_to_group("dead_enemies")
	if enemy.lock_indicator != null:
		enemy.lock_indicator.visible = false


func update_death(delta: float) -> void:
	_death_timer += delta
	_death_blend = move_toward(_death_blend, 1.0, delta * 2.0)
	if _death_param_ok:
		enemy.animation_tree.set(enemy.DEATH_BLEND_AMOUNT, _death_blend)
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.current_speed * 2.0)
	enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.current_speed * 2.0)
