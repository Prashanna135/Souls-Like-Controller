extends CharacterBody3D

# Root of the enemy scene. Owns the shared state (velocity, health, the flags
# every system reads) and drives each subsystem's update in order every physics
# frame. Behavior lives in the child nodes:
#
#   AI        perception, state machine, patrol, combat      enemy_ai.gd
#   Weapon    attack combo, equip, hitbox window             enemy_weapon.gd
#   Reaction  damage, hurt/knockback/get-up, death           enemy_reaction.gd
#
# The subsystems reach back through `enemy` for shared state, so velocity and
# the combat flags have one source of truth. hud.gd, the player's lock-on and
# the auto-sheathe check all read _has_aggro / is_dead / is_attacking by name
# off this node, which is why those stay here rather than on a subsystem.

var sprint_speed  := 5.5
var current_speed := sprint_speed
@export var patrol_speed := 2.0   # walk speed while patrolling (much slower than sprint_speed)

# Sight range comes from the detectarea Area3D's sphere shape; the behind
# Area3D punches a blind spot out of it.
@export var lose_range        := 18.0   # give up the chase entirely past this distance
@export var combat_range      := 3.2    # close enough to stop chasing and start maneuvering
@export var attack_range      := 2.0    # actual swing distance, checked inside combat AI
@export var attack_cooldown   := 1.0    # seconds to wait after a combo finishes

# Each enemy claims the nearest unclaimed Marker3D in patrol_points_group and
# wanders within patrol_radius of it while idle. One marker per enemy. With no
# markers, enemies just idle in place.
@export var patrol_points_group := &"patrol_points"
@export var patrol_radius       := 6.0
# Only claim a marker within this distance of the spawn point, so distant
# enemies don't cross the level to reach one.
@export var patrol_max_claim_distance := 15.0
@export var patrol_wait_min     := 1.5   # seconds to pause at each patrol point
@export var patrol_wait_max     := 3.5

# Dead-zones around the chase/combat and approach/attack boundaries so the AI
# doesn't flicker between states when the player hovers right on a threshold.
@export var combat_range_hysteresis := 0.8
@export var attack_range_hysteresis := 0.6

# Inside combat_range the enemy re-rolls between strafing, backing off to reset
# spacing, and attacking, instead of chase-and-swing on repeat.
@export var strafe_speed          := 3.0
@export var retreat_distance      := 3.5    # how far back it tries to hop before stopping
@export var decision_interval_min := 0.8
@export var decision_interval_max := 1.8
@export_range(0.0, 1.0) var attack_chance := 0.5
@export_range(0.0, 1.0) var strafe_chance := 0.35
# (remaining probability goes to retreat)

# See weapon_item.gd / weapon_equipper.gd — same weapon-scene system as the
# player, minus the inventory/UI (enemies just spawn already equipped).
@export var starting_weapon : WeaponItem

# Read by other scripts by name, so these live on the root. The Weapon and
# Reaction subsystems own writes; movement and the animation tree read them.
var is_attacking := false

var is_dead := false    # left false until the death path sets it; take_damage() no-ops once true

# Normal enemies show a floating bar once hurt (WorldHealthBar). A boss (tick
# is_boss) drives the top-center HUD bar instead.
@export var max_health := 100.0
@export var is_boss    := false
var current_health := 0.0

@export var heavy_damage_threshold   := 25.0   # incoming damage at/above this triggers Knockback instead of the light Hurt stagger
@export var hurt_push_force          := 1.5    # small backward shove that plays alongside the light Hurt1 stagger
@export var knockback_force          := 5.0    # horizontal shove applied on a heavy hit
@export var knockback_lift           := 2.0    # vertical pop applied on a heavy hit
@export var heavy_knockdown_max_time := 4.0    # safety fallback if the Knockback animation never reports itself finished

# _has_aggro is written by the AI but read by hud.gd and player_weapon.gd
# (auto-sheathe), so it stays on the root.
var _has_aggro := false

@onready var animation_tree      : AnimationTree     = $AnimationTree
@onready var standcoll           : CollisionShape3D  = $Standcoll
@onready var mannequin           : Node3D            = $soulslikebody
@onready var skeleton            : Skeleton3D        = $soulslikebody/GeneralSkeleton
@onready var attack_playback     : AnimationNodeStateMachinePlayback = animation_tree.get(ATTACK_PLAYBACK)
@onready var navigation_agent_3d : NavigationAgent3D = $NavigationAgent3D
@onready var weaponattachment    : BoneAttachment3D  = $soulslikebody/GeneralSkeleton/weaponattachment
# The SwordHitbox isn't a static child — weapon_equipper instances it under
# weaponattachment at runtime whenever a WeaponItem is equipped.
@onready var detectarea          : Area3D            = $detectarea
@onready var behind              : Area3D            = $behind

# Lock-on anchor: this Sprite3D is no longer drawn in 3D (LockReticle draws the
# marker in screen space). Its position is still used as the aim point.
@onready var lock_indicator : Sprite3D = $LockIndicator
var _lock_indicator_active := false

@onready var ai       = $AI
@onready var weapon   = $Weapon
@onready var reaction = $Reaction

const STAND_BLEND_POS   = "parameters/standmovement/blend_position"
const JUMP_BLEND_AMOUNT = "parameters/jump/blend_amount"
const SWORDBLEND_AMOUNT = "parameters/swordblend/blend_amount"
const ATTACK_PLAYBACK   = "parameters/swordstate/playback"
const COND_CHAIN_B      = "parameters/swordstate/conditions/chain_b"
const COND_NO_CHAIN_B   = "parameters/swordstate/conditions/no_chain_b"
const COND_CHAIN_C      = "parameters/swordstate/conditions/chain_c"
const COND_NO_CHAIN_C   = "parameters/swordstate/conditions/no_chain_c"

# Death blend — 0 = normal (whatever is layered below), 1 = the Die1 clip.
# Mirrors player.tscn's own deathblend. Only used if the tree actually has it.
const DEATH_BLEND_AMOUNT = "parameters/deathblend/blend_amount"

# Weapon sheath/unsheathe one-shot — fired by weapon_equipper when the equipped
# weapon changes (see WeaponEquipper.equip()).
const WEAPON_CHANGEBACK_ONE_SHOT = "parameters/weaponchangeback/request"

# Hit reaction one-shots (see AnimationTree: hurt -> Knockback -> laytoidle,
# layered in that order on top of the sword blend)
const HURT_ONE_SHOT      = "parameters/hurt/request"
const HURT_ACTIVE        = "parameters/hurt/active"
const KNOCKBACK_ONE_SHOT = "parameters/Knockback/request"
const KNOCKBACK_ACTIVE   = "parameters/Knockback/active"
const LAYTOIDLE_ONE_SHOT = "parameters/laytoidle/request"
const LAYTOIDLE_ACTIVE   = "parameters/laytoidle/active"

# Sword state names (must match the state machine node names exactly)
const STATE_IDLE = "SwordIdle"
const STATE_A    = "Sword_Regular_A"
const STATE_B    = "Sword_Regular_B"
const STATE_C    = "Sword_Regular_C"

# Smoothing
const BLEND_SMOOTH      := 12.0
const JUMP_BLEND_SMOOTH := 8.0
const SWORDBLEND_SMOOTH := 10.0
const ROT_SPEED_CHASE   := 8.0
const ROT_SPEED_FACE    := 14.0

# Stored blend positions for smooth lerping
var _stand_blend_pos  := Vector2.ZERO
var _jump_blend_value := 0.0
var _swordblend_value := 0.0


func _ready() -> void:
	animation_tree.active = true
	# Root motion needs to be sampled on the same tick it's applied in, so drive
	# the AnimationTree on the physics step instead of idle frames.
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	add_to_group("enemies")
	current_health = max_health

	# Bosses drive the top-center HUD bar instead of a floating one.
	if is_boss:
		add_to_group("bosses")

	_setup_lock_indicator()

	# Wire up the subsystems before anything reads them. AI last, since it runs
	# the deferred player lookup / patrol claim in its own setup().
	weapon.setup(self)
	reaction.setup(self)
	ai.setup(self)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if is_dead:
		reaction.update_death(delta)
		move_and_slide()
		return

	weapon.tick(delta)

	reaction.update(delta)
	var stunned: bool = reaction.is_stunned()

	# ai.update() also flips _has_aggro based on the sight/blind-spot zones.
	var dist: float = ai.update()

	# Patrol walks (slowly); chase/combat use full sprint speed.
	current_speed = patrol_speed if ai.is_idle() else sprint_speed

	if is_attacking:
		weapon.update_attack(dist, ai.player_target != null)

	if reaction.is_getting_up:
		# Standing back up shouldn't involve any horizontal drift at all —
		# hard-stop here instead of the gradual decay below, otherwise any
		# velocity still trickling off from the knockback carries the enemy
		# sliding across the ground for the whole LayToIdle animation.
		velocity.x = 0.0
		velocity.z = 0.0
	elif stunned:
		# is_hurt / is_knocked_down: no AI control while reacting to a hit —
		# let the knockback impulse (if any) and gravity carry it, bleeding off
		# horizontal speed as the animation settles.
		velocity.x = move_toward(velocity.x, 0.0, sprint_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, sprint_speed * 2.0)
	elif is_attacking:
		face_target(delta)
		weapon.apply_root_motion(delta)
	elif ai.is_combat():
		ai.run_combat(delta, dist)
	elif ai.is_chasing():
		move_in_direction(ai.nav_direction(), delta)
	else:
		# Idle: patrol if this enemy claimed a patrol marker, otherwise hold still.
		ai.run_patrol(delta)

	move_and_slide()

	_update_animation_tree(delta)


func take_damage(amount: float, source_position: Vector3 = global_position) -> void:
	reaction.take_damage(amount, source_position)


func set_lock_indicator(active: bool) -> void:
	_lock_indicator_active = active


func move_in_direction(move_dir: Vector3, delta: float) -> void:
	if move_dir.length() > 0.1:
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed

		var target_angle := atan2(move_dir.x, move_dir.z)
		mannequin.rotation.y = lerp_angle(mannequin.rotation.y, target_angle, ROT_SPEED_CHASE * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * 2.0)


func face_target(delta: float) -> void:
	if ai.player_target == null:
		return

	var to_target: Vector3 = ai.player_target.global_position - global_position
	to_target.y = 0.0

	if to_target.length() > 0.01:
		var face_angle := atan2(to_target.x, to_target.z)
		mannequin.rotation.y = lerp_angle(mannequin.rotation.y, face_angle, ROT_SPEED_FACE * delta)


# Called by the player's lock-on system. Kept as a single public entry point so
# the player script doesn't need to know how the enemy exposes its aim point.
func _setup_lock_indicator() -> void:
	if lock_indicator == null:
		push_warning("Enemy '%s' has no 'LockIndicator' node — lock-on will aim at the enemy's origin instead of chest height." % name)
		return
	# Never drawn as a 3D sprite (that rendered through walls and grew with
	# distance — LockReticle draws the screen-space replacement). This node's
	# position is still the reticle's aim point.
	lock_indicator.visible = false


func has_anim_param(param_path: String) -> bool:
	for prop in animation_tree.get_property_list():
		if prop.name == param_path:
			return true
	return false


func _update_animation_tree(delta: float) -> void:
	# Drive the locomotion blend from velocity relative to facing, so combat
	# strafing/retreating reads correctly instead of always showing a forward run.
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	var stand_target := Vector2.ZERO

	if horizontal_vel.length() > 0.1:
		var mrot      := mannequin.rotation.y
		var local_fwd := Vector3(sin(mrot), 0.0, cos(mrot))
		var local_rgt := Vector3(cos(mrot), 0.0, -sin(mrot))

		var move_dir := horizontal_vel.normalized()
		var local_x  := -move_dir.dot(local_rgt)
		var local_z  :=  move_dir.dot(local_fwd)

		# Outside combat (idle/patrol/chase) the enemy only ever walks FORWARD
		# once it's committed to a direction — clamp the side/back components
		# out. Otherwise the facing lerp lags the velocity during a turn and the
		# blend space plays the walk-backward/sideways clip, which is what made
		# patrolling enemies moonwalk. Combat keeps full 8-way blending so
		# strafing/retreating still read correctly.
		if not ai.is_combat() and not is_attacking:
			local_x = 0.0
			local_z = maxf(local_z, 0.0)

		stand_target = Vector2(local_x, -local_z)
		if stand_target.length() > 1.0:
			stand_target = stand_target.normalized()

	_stand_blend_pos = _stand_blend_pos.lerp(stand_target, BLEND_SMOOTH * delta)
	animation_tree.set(STAND_BLEND_POS, _stand_blend_pos)

	var jump_target := 1.0 if not is_on_floor() else 0.0
	_jump_blend_value = lerp(_jump_blend_value, jump_target, JUMP_BLEND_SMOOTH * delta)
	animation_tree.set(JUMP_BLEND_AMOUNT, _jump_blend_value)

	var sword_target := 1.0 if is_attacking else 0.0
	_swordblend_value = lerp(_swordblend_value, sword_target, SWORDBLEND_SMOOTH * delta)
	animation_tree.set(SWORDBLEND_AMOUNT, _swordblend_value)
