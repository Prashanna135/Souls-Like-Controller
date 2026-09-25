extends RefCounted
class_name WeaponEquipper

# Instances a weapon scene under the wielder's hand bone and wires up its
# hitbox. Shared by player.gd and enemy.gd so weapon swapping behaves the same
# for both. Plain RefCounted — construct one in _ready() and call equip()
# whenever the weapon changes:
#
#   weapon_equipper = WeaponEquipper.new(weaponattachment, self, animation_tree,
#       WEAPON_CHANGEBACK_ONE_SHOT, [&"enemies"], wepondisplayback, sheath_marker)
#   weapon_equipper.equip(starting_weapon)
#
# Weapon scene: a standalone .tscn whose root node is an Area3D named
# "SwordHitbox" with sword_hitbox.gd attached. The name matters — the attack
# animations reference "weaponattachment/SwordHitbox" by path.
#
# Sheathe / draw: pass a second BoneAttachment3D as `back_attachment` (e.g. the
# player's wepondisplayback) to allow stowing the weapon on the back. Pass a
# Marker3D child of it as `sheath_marker` to set the resting pose with the 3D
# gizmo; per-weapon sheath_position_offset/sheath_rotation_deg in WeaponItem
# then nudge it further. Weapons are swapped onto the new bone partway through
# the "MeleeLib/WeaponChange_back" clip, driven by player.gd's
# _update_weapon_swap() (or a Call Method Track via _on_weapon_swap_commit()).
# Left null (as enemy.gd does), sheathing is simply unavailable.

var _hand_attachment : BoneAttachment3D
var _back_attachment  : BoneAttachment3D
var _sheath_marker     : Node3D
var _wielder                  : Node3D
var _animation_tree            : AnimationTree
var _changeback_request_path    : String
var _target_groups             : Array[StringName]

var current_weapon    : WeaponItem = null
var current_hitbox    : Area3D     = null
var _current_instance  : Node3D    = null
# The weapon_scene's root transform exactly as authored (captured the moment
# it's instanced, before anything reparents/repositions it) — this is what
# "in-hand" gets reset back to. Without this, once a weapon had been
# sheathed even once, drawing it again left it sitting at its last sheathed
# position/rotation forever, since nothing ever told it to go back.
var _hand_pose_transform : Transform3D = Transform3D.IDENTITY

# true = weapon instanced under _hand_attachment and ready to swing; false =
# weapon instanced under _back_attachment (if any) and the wielder is
# effectively bare-handed. Starts drawn so existing behavior (starting_weapon
# appearing in-hand at spawn) is unchanged.
var is_drawn : bool = true

# true from the moment a draw/sheathe is requested until
# apply_pending_draw_state() actually confirms the resting pose — wielder
# scripts should treat this like any other busy one-shot (block attacking/
# rolling/re-toggling) and call apply_pending_draw_state() once the
# changeback one-shot's "active" param goes false again.
var is_swapping    : bool = false
var _pending_drawn : bool = true


func _init(attachment: BoneAttachment3D, wielder: Node3D, animation_tree: AnimationTree, changeback_request_path: String, target_groups: Array[StringName] = [&"enemies"], back_attachment: BoneAttachment3D = null, sheath_marker: Node3D = null) -> void:
	_hand_attachment         = attachment
	_back_attachment         = back_attachment
	_sheath_marker           = sheath_marker
	_wielder                 = wielder
	_animation_tree          = animation_tree
	_changeback_request_path = changeback_request_path
	_target_groups           = target_groups


# Swaps to `weapon`, instancing its weapon_scene under whichever attachment
# matches the current drawn/sheathed state and firing the sheathe/unsheathe
# one-shot. Passing null just removes whatever's currently equipped
# (bare-handed, nothing on the back either) without instancing a replacement.
# This is a full loadout change (different WeaponItem), not a draw/sheathe
# toggle, so it applies immediately rather than going through the
# request/apply swap below.
#
# The changeback one-shot only plays while the weapon is actually DRAWN —
# swapping loadout while sheathed just silently swaps the model sitting at
# the sheath point, since there's no in-hand motion for the animation to
# cover up and the new weapon already appears in the right place with
# nothing to "change back" from.
func equip(weapon: WeaponItem) -> void:
	if weapon == current_weapon:
		return

	if _animation_tree != null and _changeback_request_path != "" and is_drawn:
		_animation_tree.set(_changeback_request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	if _current_instance != null:
		_current_instance.queue_free()
		_current_instance = null
		current_hitbox    = null

	current_weapon = weapon

	if weapon == null or weapon.weapon_scene == null:
		return

	var instance := weapon.weapon_scene.instantiate()
	_current_instance    = instance as Node3D
	_hand_pose_transform = _current_instance.transform
	_target_attachment().add_child(instance)
	_apply_pose_for_current_state()

	var hitbox : Area3D = instance as Area3D
	if hitbox == null:
		hitbox = instance.find_child("SwordHitbox", true, false)

	if hitbox == null:
		push_warning("Weapon scene '%s' has no Area3D named 'SwordHitbox' — this weapon won't deal damage." % weapon.weapon_scene.resource_path)
		return

	hitbox.wielder             = _wielder
	hitbox.damage              = weapon.damage
	hitbox.valid_target_groups = _target_groups
	current_hitbox              = hitbox

	# Fresh equips start with the hitbox off (matches disable_hitbox() default).
	if hitbox.has_method("disable_hitbox"):
		hitbox.disable_hitbox()


# ── DRAW / SHEATHE (two-phase) ───────────────────────────────────────────────
# Phase 1: fires the changeback one-shot and records the target state, but
# leaves the weapon on its current bone so it follows the animation. is_drawn
# only changes in phase 2 (apply_pending_draw_state).
func request_drawn(drawn: bool) -> bool:
	if drawn == is_drawn or is_swapping:
		return false
	if not drawn and _back_attachment == null:
		push_warning("WeaponEquipper.request_drawn(false) called with no back_attachment configured — nothing to sheathe onto.")
		return false

	_pending_drawn = drawn
	is_swapping    = true

	# Stop a mid-swing weapon from dealing damage as it leaves the hand.
	if current_hitbox != null and current_hitbox.has_method("disable_hitbox"):
		current_hitbox.disable_hitbox()

	if _animation_tree != null and _changeback_request_path != "":
		_animation_tree.set(_changeback_request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	return true


func toggle_drawn() -> bool:
	return request_drawn(not is_drawn)


# Phase 2: reparents the weapon onto the target bone, snaps it to the resting
# pose, and flips is_drawn. Called from _update_weapon_swap() (or a Call Method
# Track via _on_weapon_swap_commit). Safe to call when nothing is pending.
func apply_pending_draw_state(from_track: bool = false) -> void:
	if not is_swapping:
		return

	is_drawn    = _pending_drawn
	is_swapping = false

	if not from_track:
		push_warning("Weapon draw/sheathe resolved via the entered/timeout fallback, not the Call Method Track — check that 'MeleeLib/WeaponChange_back' has a Call Method Track calling the wielder's _on_weapon_swap_commit() (or equivalent) at the reach-point frame, and that its NodePath actually resolves to the wielder.")

	if _current_instance == null:
		return   # bare-handed already — state flipped, nothing to reparent

	var target     := _target_attachment()
	var old_parent := _current_instance.get_parent()
	if old_parent != target:
		if old_parent != null:
			old_parent.remove_child(_current_instance)
		target.add_child(_current_instance)

	_apply_pose_for_current_state()


func _target_attachment() -> BoneAttachment3D:
	return _attachment_for(is_drawn)


func _attachment_for(drawn: bool) -> BoneAttachment3D:
	if drawn or _back_attachment == null:
		return _hand_attachment
	return _back_attachment


# Applies the resting pose for the current state. In-hand it restores the
# scene's authored transform; sheathed it uses the sheath marker (plus the
# weapon's per-item offset).
func _apply_pose_for_current_state() -> void:
	if _current_instance == null:
		return

	var pose := _pose_transform_for(is_drawn)
	_current_instance.position         = pose.origin
	_current_instance.rotation_degrees = pose.basis.get_euler() * (180.0 / PI)


# Pure lookup of the resting pose for a given drawn state.
func _pose_transform_for(drawn: bool) -> Transform3D:
	if drawn or _back_attachment == null:
		return _hand_pose_transform

	var base_position := Vector3.ZERO
	var base_rotation  := Vector3.ZERO
	if _sheath_marker != null:
		base_position = _sheath_marker.position
		base_rotation = _sheath_marker.rotation_degrees

	var sheath_pos_offset := current_weapon.sheath_position_offset if current_weapon != null else Vector3.ZERO
	var sheath_rot_offset := current_weapon.sheath_rotation_deg    if current_weapon != null else Vector3.ZERO

	var pose := Transform3D.IDENTITY
	pose.origin = base_position + sheath_pos_offset
	pose.basis  = Basis.from_euler((base_rotation + sheath_rot_offset) * (PI / 180.0))
	return pose
