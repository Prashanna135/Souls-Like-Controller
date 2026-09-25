extends CharacterBody3D

# Root of the player scene. Owns the shared state (velocity, health, the state
# flags every system reads) and drives each subsystem's update in the right
# order every physics frame. The actual behavior lives in the child nodes:
#
#   LockOn      target pick/cycle, camera + reticle        player_lock_on.gd
#   Weapon      equip, draw/sheathe, attack combo          player_weapon.gd
#   Reaction    damage, hurt/knockback/get-up, death       player_reaction.gd
#   Ladder      mount / climb / dismount                   player_ladder.gd
#   Consumable  drink + delayed heal                       player_consumable.gd
#   Door        door interaction                           player_door.gd
#
# Every system reaches back through `player` for shared state, so there's a
# single source of truth for velocity/health/flags instead of each node keeping
# its own copy.

@export var sprint_speed := 8.0
@export var roll_speed   := 6.0
var current_speed := sprint_speed

const JUMP_VELOCITY = 4.5

# Air control: airborne horizontal speed is capped to a fraction of ground
# speed and steering is gradual, so a running jump doesn't glide at full sprint.
@export var air_speed_scale := 0.55
@export var air_steer_accel := 8.0
@export var air_drag        := 6.0

# Systems set these; movement and the animation tree read them. Kept on the
# root rather than duplicated per node.
var is_rolling   := false
var is_jumpback  := false
var jumpback_started := false

var is_attacking := false   # owned by the Weapon system, read widely

var is_dead      := false
var is_hard_landing := false

@export var max_health := 100.0
var current_health := 0.0

@export var heavy_damage_threshold   := 25.0
@export var hurt_push_force          := 1.5
@export var knockback_force          := 5.0
@export var knockback_lift           := 2.0
@export var heavy_knockdown_max_time := 4.0

var _death_blend := 0.0
var _death_param_ok := false
var _death_timer := 0.0
var _hud: PlayerHUD = null

@export var fall_loop_delay              := 0.35
@export var hard_land_velocity_threshold := 8.0
@export var hard_land_max_time           := 2.0
@export var fall_damage_min_speed := 12.0
@export var fall_damage_max_speed := 30.0
@export var fall_damage_max       := 100.0

var _hardland_entered := false
var _hardland_timer   := 0.0
var _air_time         := 0.0
var _fall_peak_speed  := 0.0

@export var consume_max_time  := 3.0
@export var consume_heal_time := 1.2

@export var ladder_climb_speed  := 2.0
@export var ladder_snap_epsilon := 0.05
@export var ladder_instant_dismount := true
@export var ladder_dismount_forward_nudge := 0.5
@export var ladder_mount_max_time    := 3.0
@export var ladder_dismount_max_time := 3.0

@export var dooropen_max_time := 3.0

@export var starting_weapon           : WeaponItem
@export var starting_consumable       : ConsumableItem
@export var starting_consumable_count := 5
@export var weaponswap_max_time     := 2.0
@export var weaponswap_commit_delay := 0.48
@export var auto_sheathe_delay       := 3.0
@export var auto_sheathe_enemy_range := 8.0

var inventory     : Inventory   = Inventory.new()
var inventory_ui  : InventoryUI = null

# What the "consume" hotkey drinks; defaults to starting_consumable in _ready().
var selected_consumable : ConsumableItem = null

@onready var animation_tree : AnimationTree    = $AnimationTree
@onready var standcoll      : CollisionShape3D = $Standcoll
@onready var h_pivot        : Node3D           = $h
@onready var camera         : Camera3D         = $h/v/Camera3D
@onready var cam_script     : Node3D           = $h
@onready var mannequin      : Node3D           = $soulslikebody
@onready var skeleton       : Skeleton3D       = $soulslikebody/GeneralSkeleton
@onready var attack_playback : AnimationNodeStateMachinePlayback = animation_tree.get(ATTACK_PLAYBACK)
@onready var ladder_playback : AnimationNodeStateMachinePlayback = animation_tree.get(LADDER_PLAYBACK)
@onready var weaponattachment : BoneAttachment3D = $soulslikebody/GeneralSkeleton/weaponattachment
@onready var wepondisplayback : BoneAttachment3D = $soulslikebody/GeneralSkeleton/wepondisplayback
@onready var weapon_sheath_marker : Marker3D = $soulslikebody/GeneralSkeleton/wepondisplayback/SheathPoint if has_node("soulslikebody/GeneralSkeleton/wepondisplayback/SheathPoint") else null
@onready var lock_reticle : Control = $LockOnUI/LockReticle

@onready var lock_on    = $LockOn
@onready var weapon     = $Weapon
@onready var reaction   = $Reaction
@onready var ladder     = $Ladder
@onready var consumable = $Consumable
@onready var door       = $Door

const STAND_BLEND_POS   = "parameters/standmovement/blend_position"
const BLEND2_AMOUNT     = "parameters/Blend2/blend_amount"
const JUMP_BLEND_AMOUNT = "parameters/jump/blend_amount"
const ROLL_ONE_SHOT     = "parameters/roll_shot/request"
const JUMPBACK_ONE_SHOT = "parameters/jumpback_shot/request"
const SWORDBLEND_AMOUNT = "parameters/swordblend/blend_amount"
const ATTACK_PLAYBACK   = "parameters/swordstate/playback"
const COND_CHAIN_B      = "parameters/swordstate/conditions/chain_b"
const COND_NO_CHAIN_B   = "parameters/swordstate/conditions/no_chain_b"
const COND_CHAIN_C      = "parameters/swordstate/conditions/chain_c"
const COND_NO_CHAIN_C   = "parameters/swordstate/conditions/no_chain_c"

const DEATH_BLEND_AMOUNT = "parameters/deathblend/blend_amount"

const WEAPON_CHANGEBACK_ONE_SHOT = "parameters/weaponchangeback/request"
const WEAPON_CHANGEBACK_ACTIVE   = "parameters/weaponchangeback/active"

const DOOROPEN_ONE_SHOT = "parameters/openoor/request"
const DOOROPEN_ACTIVE   = "parameters/openoor/active"

const HURT_ONE_SHOT      = "parameters/hurt/request"
const HURT_ACTIVE        = "parameters/hurt/active"
const KNOCKBACK_ONE_SHOT = "parameters/Knockback/request"
const KNOCKBACK_ACTIVE   = "parameters/Knockback/active"
const LAYTOIDLE_ONE_SHOT = "parameters/laytoidle/request"
const LAYTOIDLE_ACTIVE   = "parameters/laytoidle/active"

const CONSUME_ONE_SHOT = "parameters/consume/request"
const CONSUME_ACTIVE   = "parameters/consume/active"

const FALLINGSWITCH_BLEND = "parameters/fallingswitch/blend_amount"
const LANDHARD_ONE_SHOT   = "parameters/landhard/request"
const LANDHARD_ACTIVE     = "parameters/landhard/active"

const SWORDORLADDER_BLEND = "parameters/swordorladderblend/blend_amount"
const LADDER_PLAYBACK     = "parameters/ladderstate/playback"

const LADDER_STATE_IDLE     = "ladder_idle"
const LADDER_STATE_CLIMB    = "ladder_climbing"
const LADDER_STATE_MOUNT    = "ladderbuttom_mount"
const LADDER_STATE_DISMOUNT = "laddertop_dismount"

const LADDER_ANIM_MOUNT    = &"MeleeLib/LadderBottom_mount"
const LADDER_ANIM_DISMOUNT = &"MeleeLib/LadderTop_dismount"

const STATE_IDLE = "SwordIdle"
const STATE_A    = "Sword_Regular_A"
const STATE_B    = "Sword_Regular_B"
const STATE_C    = "Sword_Regular_C"

const BLEND_SMOOTH         := 12.0
const BLEND2_ROLL_SMOOTH   := 6.0
const JUMP_BLEND_SMOOTH    := 8.0
const SWORDBLEND_SMOOTH    := 10.0
const LADDER_BLEND_SMOOTH  := 10.0
const FALLING_BLEND_SMOOTH := 8.0
const ROT_SPEED_FREE       := 10.0
const ROT_SPEED_LOCKED     := 14.0

# Blend values, lerped toward their targets each frame in _update_animation_tree().
var _stand_blend_pos    := Vector2.ZERO
var _jump_blend_value   := 0.0
var _roll_blend_value   := 0.0
var _swordblend_value   := 0.0
var _ladder_blend_value := 0.0
var _falling_blend_value := 0.0

# Roll direction (world-space, normalized)
var _roll_dir := Vector3.ZERO


func _ready() -> void:
	animation_tree.active = true
	# Root motion has to be sampled on the tick it's applied in, so drive the
	# AnimationTree on the physics step instead of idle frames.
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	current_health = max_health
	_death_param_ok = _has_anim_param(DEATH_BLEND_AMOUNT)

	# HUD.
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	_hud = PlayerHUD.new()
	hud_layer.add_child(_hud)
	_hud.setup(self)

	# Lets enemies filter for the player by group instead of by node name.
	add_to_group("player")

	if lock_reticle != null:
		lock_reticle.player = self
		lock_reticle.camera = camera
	else:
		push_warning("Player has no 'LockOnUI/LockReticle' node — lock-on reticle disabled. See lock_reticle.gd's header comment for setup steps.")

	# Wire up the subsystems before anything reads them.
	lock_on.setup(self)
	weapon.setup(self)
	reaction.setup(self)
	ladder.setup(self)
	consumable.setup(self)
	door.setup(self)

	# Weapon / inventory.
	if weapon_sheath_marker == null:
		push_warning("Player has no 'wepondisplayback/SheathPoint' Marker3D — sheathed weapons will use only WeaponItem's sheath_position_offset/sheath_rotation_deg (likely still poking out oddly). See weapon_equipper.gd's SHEATH POSE comment for how to add one.")

	if not InputMap.has_action("sheath_weapon"):
		push_warning("No 'sheath_weapon' input action defined — add one in Project Settings > Input Map to enable the weapon sheathe/draw toggle.")

	if starting_weapon != null:
		inventory.add_item(starting_weapon)
		equip_weapon(starting_weapon)
	else:
		push_warning("Player has no 'starting_weapon' assigned — attacks won't deal damage until a weapon is equipped. See weapon_equipper.gd's header comment for how to build one.")

	if starting_consumable != null:
		inventory.add_item(starting_consumable, starting_consumable_count)
		selected_consumable = starting_consumable

	inventory_ui = InventoryUI.new()
	add_child(inventory_ui)
	inventory_ui.setup(self, inventory)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	# Ladder flags only flip at discrete mount/dismount moments, so last frame's
	# value is good enough to decide whether gravity should apply.
	var ladder_pre: bool = ladder.is_busy()
	if not was_on_floor and not ladder_pre:
		velocity += get_gravity() * delta

	if is_dead:
		_update_death(delta)
		move_and_slide()
		return

	# Falling / hard-land tracking. Ladders are excluded — climbing also leaves
	# is_on_floor() false the whole way up and would otherwise trip the falling loop.
	if was_on_floor or ladder_pre:
		_air_time = 0.0
		_fall_peak_speed = 0.0
	else:
		_air_time += delta
		_fall_peak_speed = minf(_fall_peak_speed, velocity.y)

	var menu_open := inventory_ui != null and inventory_ui.is_open
	var input_dir := Vector2.ZERO if menu_open else Input.get_vector("leftward", "rightward", "forward", "backward")

	var cam_basis := camera.global_transform.basis
	var cam_fwd   := -cam_basis.z; cam_fwd.y = 0.0; cam_fwd = cam_fwd.normalized()
	var cam_right :=  cam_basis.x; cam_right.y = 0.0; cam_right = cam_right.normalized()
	var move_dir  := cam_right * input_dir.x + cam_fwd * (-input_dir.y)

	# Subsystem updates. Order matters: reactions land before movement is
	# decided, the weapon swap resolves before the attack/roll triggers read
	# is_stunned, and the ladder runs last of the "busy" systems since it owns
	# velocity while climbing.
	reaction.update(delta)
	_update_hard_land(delta)
	consumable.update(delta)
	door.update(delta)
	weapon.update_swap(delta)

	if not menu_open:
		_try_interact()
	ladder.update(delta)
	var ladder_locked: bool = ladder.is_locked()

	# Consume hotkey.
	if not menu_open and Input.is_action_just_pressed("consume"):
		consumable.use(selected_consumable)

	# Roll / jumpback.
	if not menu_open and Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling and not is_jumpback and not is_attacking and not is_stunned() and not ladder_locked:
		_start_roll(move_dir)

	if is_rolling:
		if not animation_tree.get("parameters/roll_shot/active"):
			is_rolling = false
			current_speed = sprint_speed

	if is_jumpback:
		var jumpback_active : bool = animation_tree.get("parameters/jumpback_shot/active")
		if jumpback_started and not jumpback_active:
			is_jumpback = false
			jumpback_started = false
			current_speed = sprint_speed
			velocity.x = 0.0
			velocity.z = 0.0
		elif jumpback_active:
			jumpback_started = true
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, 50.0)
				velocity.z = move_toward(velocity.z, 0.0, 50.0)

	# A left-click always attacks: if the weapon is sheathed it's drawn first and
	# the swing fires the moment the draw commits.
	if not menu_open and Input.is_action_just_pressed("attack") and not ladder_locked:
		if is_attacking:
			weapon.buffer_attack()
		elif not is_rolling and not is_jumpback and not is_stunned() and not weapon.is_swapping() and is_on_floor():
			if weapon.is_drawn():
				weapon.start_attack()
			else:
				weapon.request_draw_for_attack()

	if is_attacking:
		weapon.update_attack()

	# Sheathe / draw toggle.
	if not menu_open and Input.is_action_just_pressed("sheath_weapon") and not ladder_locked:
		if not is_attacking and not is_rolling and not is_jumpback and not is_stunned():
			weapon.toggle_draw()

	# Lock-on: auto-release a dead target, then handle the toggle key.
	lock_on.update()
	if not menu_open and Input.is_action_just_pressed("lock_on") and not ladder_locked:
		lock_on.handle_input()

	# Auto sheathe / combat timer.
	weapon.update_combat(delta)

	# Weapon swapping is excluded so a draw/sheathe mid-run keeps full speed.
	if not is_rolling and not is_jumpback and not is_attacking and not ladder_locked \
			and (not is_stunned() or weapon.is_swapping()):
		current_speed = sprint_speed

	if ladder_locked:
		pass   # velocity is driven by the ladder system
	elif reaction.is_getting_up:
		velocity.x = 0.0
		velocity.z = 0.0
	elif is_stunned() and not weapon.is_swapping():
		velocity.x = move_toward(velocity.x, 0.0, current_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * 2.0)
	elif is_rolling:
		velocity.x = _roll_dir.x * current_speed
		velocity.z = _roll_dir.z * current_speed
	elif is_jumpback:
		pass   # gravity + the jumpback impulse handle it; just block input
	elif is_attacking:
		weapon.apply_attack_root_motion(delta)
	elif not is_on_floor():
		if move_dir.length() > 0.1:
			var air_target := move_dir.normalized() * current_speed * air_speed_scale
			velocity.x = move_toward(velocity.x, air_target.x, air_steer_accel * delta)
			velocity.z = move_toward(velocity.z, air_target.z, air_steer_accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, air_drag * delta)
			velocity.z = move_toward(velocity.z, 0.0, air_drag * delta)
	elif lock_on.is_locked_on and lock_on.target != null:
		_move_locked(move_dir, delta)
	else:
		_move_free(move_dir, delta)

	move_and_slide()

	if not was_on_floor and is_on_floor():
		_handle_landing()

	_update_animation_tree(input_dir, delta, ladder_locked)


func get_camera() -> Camera3D:
	return camera


# A system is "busy" if it currently owns the player. Movement and the input
# triggers consult this instead of hand-listing every flag.
func is_stunned() -> bool:
	return reaction.is_stunned() or is_hard_landing or consumable.is_consuming or door.is_opening or weapon.is_swapping()


func take_damage(amount: float, source_position: Vector3 = global_position) -> void:
	reaction.take_damage(amount, source_position)


func equip_weapon(weapon_item: WeaponItem) -> void:
	weapon.equip(weapon_item)


func draw_weapon_if_sheathed() -> void:
	weapon.draw_if_sheathed()


func use_consumable(item: ConsumableItem) -> bool:
	return consumable.use(item)


func _grant_item(item: Item, count: int = 1) -> void:
	inventory.add_item(item, count)


# Called by a Call Method Track on MeleeLib/WeaponChange_back at the exact
# sheath/hilt frame, if the animation ever gets one wired up.
func _on_weapon_swap_commit() -> void:
	weapon.on_swap_commit()


func die() -> void:
	is_dead = true
	is_rolling = false
	is_jumpback = false
	jumpback_started = false
	is_attacking = false
	is_hard_landing = false
	weapon.abort_attack()
	current_speed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_death_timer = 0.0
	if _death_param_ok:
		animation_tree.set(DEATH_BLEND_AMOUNT, 0.0)


func _move_free(move_dir: Vector3, delta: float) -> void:
	if move_dir.length() > 0.1:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed

		var target_angle := atan2(move_dir.x, move_dir.z)
		mannequin.rotation.y = lerp_angle(mannequin.rotation.y, target_angle, ROT_SPEED_FREE * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * 2.0)


func _move_locked(move_dir: Vector3, delta: float) -> void:
	var to_target: Vector3 = lock_on.target.global_position - global_position
	to_target.y = 0.0

	if to_target.length() > 0.01:
		var face_angle := atan2(to_target.x, to_target.z)
		mannequin.rotation.y = lerp_angle(mannequin.rotation.y, face_angle, ROT_SPEED_LOCKED * delta)

	if move_dir.length() > 0.1:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * 2.0)


func _start_roll(move_dir: Vector3) -> void:
	if move_dir.length() > 0.1:
		is_rolling = true
		current_speed = roll_speed
		_roll_dir = move_dir.normalized()
		mannequin.rotation.y = atan2(_roll_dir.x, _roll_dir.z)
		animation_tree.set(ROLL_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		# No direction held — backstep instead of rolling on the spot.
		is_jumpback = true
		jumpback_started = false
		current_speed = 0.0
		var back := -Vector3(sin(mannequin.rotation.y), 0.0, cos(mannequin.rotation.y))
		velocity = Vector3(back.x * 2.5, JUMP_VELOCITY * 0.4, back.z * 2.5)
		animation_tree.set(JUMPBACK_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _try_interact() -> void:
	if not Input.is_action_just_pressed("interact"):
		return

	# Mid one-shot (mounting/dismounting/opening) — let it resolve before
	# accepting another interact press.
	if ladder.is_mounting or ladder.is_dismounting or door.is_opening:
		return

	if ladder.is_on_ladder:
		ladder.exit()
		return

	var free_to_interact := is_on_floor() and not is_attacking and not is_rolling and not is_jumpback and not is_stunned() and not is_dead
	if ladder.can_mount() and free_to_interact:
		ladder.mount()
		return
	if door.can_open() and free_to_interact:
		door.try_open()


# Called by ladder.gd when the player walks into / out of a ladder zone.
func _register_nearby_ladder(l: Ladder) -> void:
	ladder.register(l)


func _unregister_nearby_ladder(l: Ladder) -> void:
	ladder.unregister(l)


# Called by door.gd — mirrors the ladder registration above.
func _register_nearby_door(d: Door) -> void:
	door.register(d)


func _unregister_nearby_door(d: Door) -> void:
	door.unregister(d)


func _handle_landing() -> void:
	var impact := absf(_fall_peak_speed)

	# Fall damage scales between fall_damage_min_speed (none) and
	# fall_damage_max_speed (full). Applied directly rather than through
	# take_damage() so a landing doesn't also play a hit reaction.
	if impact >= fall_damage_min_speed:
		var span := maxf(fall_damage_max_speed - fall_damage_min_speed, 0.001)
		var t := clampf((impact - fall_damage_min_speed) / span, 0.0, 1.0)
		_apply_fall_damage(t * fall_damage_max)

	if not is_dead and impact >= hard_land_velocity_threshold:
		_start_hard_land()

	_air_time = 0.0
	_fall_peak_speed = 0.0


func _apply_fall_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = maxf(0.0, current_health - amount)
	if current_health <= 0.0:
		die()


func _start_hard_land() -> void:
	is_hard_landing = true
	_hardland_entered = false
	_hardland_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	animation_tree.set(LANDHARD_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _update_hard_land(delta: float) -> void:
	if not is_hard_landing:
		return

	_hardland_timer += delta
	var active: bool = animation_tree.get(LANDHARD_ACTIVE)
	if active:
		_hardland_entered = true

	if (_hardland_entered and not active) or _hardland_timer >= hard_land_max_time:
		is_hard_landing = false
		current_speed = sprint_speed


func _update_death(delta: float) -> void:
	_death_timer += delta
	_death_blend = move_toward(_death_blend, 1.0, delta * 2.0)
	if _death_param_ok:
		animation_tree.set(DEATH_BLEND_AMOUNT, _death_blend)
	velocity.x = move_toward(velocity.x, 0.0, sprint_speed * 2.0)
	velocity.z = move_toward(velocity.z, 0.0, sprint_speed * 2.0)


func _has_anim_param(param_path: String) -> bool:
	for prop in animation_tree.get_property_list():
		if prop.name == param_path:
			return true
	return false


func _update_animation_tree(input_dir: Vector2, delta: float, is_on_ladder_any: bool) -> void:
	var is_busy := is_rolling or is_jumpback

	# 1. Roll Blend2
	var roll_target := 1.0 if is_busy else 0.0
	_roll_blend_value = lerp(_roll_blend_value, roll_target, BLEND2_ROLL_SMOOTH * delta)
	animation_tree.set(BLEND2_AMOUNT, _roll_blend_value)

	# 2. Stand blend — kept updating during roll so it's ready when Blend2 fades back.
	var stand_target := Vector2.ZERO

	if input_dir.length() > 0.01:
		if lock_on.is_locked_on and lock_on.target != null:
			var world_move := Vector3(input_dir.x, 0.0, -input_dir.y)
			var cam_basis  := camera.global_transform.basis
			var cam_fwd2   := -cam_basis.z; cam_fwd2.y = 0.0; cam_fwd2 = cam_fwd2.normalized()
			var cam_right2 :=  cam_basis.x; cam_right2.y = 0.0; cam_right2 = cam_right2.normalized()
			var world_dir  := (cam_right2 * world_move.x + cam_fwd2 * (-world_move.z)).normalized()

			var mrot      := mannequin.rotation.y
			var local_fwd := Vector3(sin(mrot), 0.0, cos(mrot))
			var local_rgt := Vector3(cos(mrot), 0.0, -sin(mrot))

			var local_x := -world_dir.dot(local_rgt)
			var local_z :=  world_dir.dot(local_fwd)

			stand_target = Vector2(local_x, -local_z)
			if stand_target.length() > 1.0:
				stand_target = stand_target.normalized()
		else:
			stand_target = Vector2(0.0, 1.0)

	_stand_blend_pos = _stand_blend_pos.lerp(stand_target, BLEND_SMOOTH * delta)
	animation_tree.set(STAND_BLEND_POS, _stand_blend_pos)

	# 3. Jump blend
	var jump_target := 1.0 if not is_on_floor() else 0.0
	_jump_blend_value = lerp(_jump_blend_value, jump_target, JUMP_BLEND_SMOOTH * delta)
	animation_tree.set(JUMP_BLEND_AMOUNT, _jump_blend_value)

	# 4. Sword combat blend — cross-fades locomotion against the attack machine.
	var sword_target := 1.0 if is_attacking else 0.0
	_swordblend_value = lerp(_swordblend_value, sword_target, SWORDBLEND_SMOOTH * delta)
	animation_tree.set(SWORDBLEND_AMOUNT, _swordblend_value)

	# 5. Sword-or-ladder blend — cross-fades the combat layer into the ladder layer.
	var ladder_target := 1.0 if ladder.is_locked() else 0.0
	_ladder_blend_value = lerp(_ladder_blend_value, ladder_target, LADDER_BLEND_SMOOTH * delta)
	animation_tree.set(SWORDORLADDER_BLEND, _ladder_blend_value)

	# 6. Falling blend — cross-fades the grounded chain into the falling loop
	# once the player has been airborne (off a ledge, not on a ladder) past
	# fall_loop_delay. The landhard one-shot layers on top on touchdown.
	var falling_target := 1.0 if (not is_on_floor() and not is_on_ladder_any and _air_time > fall_loop_delay) else 0.0
	_falling_blend_value = lerp(_falling_blend_value, falling_target, FALLING_BLEND_SMOOTH * delta)
	animation_tree.set(FALLINGSWITCH_BLEND, _falling_blend_value)
