extends Item
class_name WeaponItem

# An equippable weapon. `weapon_scene` is a standalone .tscn whose root node is
# an Area3D named "SwordHitbox" with sword_hitbox.gd attached (see the included
# sword scene for an example). weapon_equipper.gd instances it under the
# wielder's weaponattachment bone when equipped.
#
# `damage` lives here rather than on the hitbox so swapping weapons changes the
# hit strength automatically.

@export var weapon_scene : PackedScene = null
@export var damage        : float      = 15.0

# Free-text note for alternate movesets. Hook this up to a different
# AnimationTree state set if a weapon needs its own attacks.
@export_multiline var moveset_note : String = ""

# Pose applied while the weapon is sheathed on the wielder's back. The back
# bone faces a different direction than the hand, so each weapon needs its own
# offset to sit naturally. Tune these in the Inspector by toggling draw/sheathe
# in-game until the weapon lies across the back correctly.
@export var sheath_position_offset : Vector3 = Vector3.ZERO
@export var sheath_rotation_deg    : Vector3 = Vector3.ZERO
