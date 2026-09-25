# Souls-like Third-Person Controller

A third-person melee controller for Godot 4, built around an AnimationTree state
machine. It started as my own project and I pulled it out because the hard parts
(combo chaining, hit reactions, lock-on, weapon swapping) took me long enough
that I figured someone else might want a base to build on.

It's two scenes: a Player and an Enemy. The enemy exists mostly so you have
something to hit while you're testing, but it's a full AI with its own state
machine and uses the same weapon/hitbox system as the player.

Godot 4.x. Built and tested on 4.7.

## What's in the box

**Player**

- Sprint, free movement, air control that doesn't let you glide at full speed
- Roll (dodge) with a direction, and a backstep if you roll while standing still
- Lock-on: picks the nearest enemy, cycles targets on repeat presses, screen-space
  reticle that hides behind walls
- Melee combat with a 3-hit combo. You can buffer the next swing during the
  current one; the combo branches through the AnimationTree conditions rather
  than hardcoded timers
- Weapon draw/sheathe, both manual (a key) and automatic (draws when you attack
  from sheathed, sheathes again after you've been out of combat a few seconds)
- Hit reactions: light hits stagger you, heavy hits knock you down and you get
  back up. Getting hit cancels whatever you were doing
- Ladders: mount, climb, dismount. The mount/dismount are one-shot animations,
  the climb loop is driven by input
- Doors: walk up, press interact
- Consumables with a delayed heal (the heal lands partway through the drink
  animation, not the instant you press the button)
- Fall damage and a hard-landing animation past a velocity threshold
- Inventory + HUD, plus a boss health bar that appears when an aggroed boss is
  alive

**Enemy**

- Perception through two Area3Ds: a sight sphere and a "behind" area that punches
  a blind spot out of it, so you can sneak up on them
- Idle / chase / combat state machine, with hysteresis on the range thresholds so
  it doesn't flicker between states when you're standing right on the boundary
- Patrol points. Drop Marker3Ds into a group and each enemy claims the nearest
  unclaimed one at spawn. No markers, no patrol — it just stands there
- In combat it rolls between strafing, backing off to reset spacing, and attacking
  instead of just chasing and swinging on loop
- Same combo and hitbox system as the player, driven by the AI instead of input
- Floating health bar for normal enemies, top-center bar for anything ticked as
  a boss

## How it's put together

Both scenes are a root `CharacterBody3D` that owns the shared state (velocity,
health, the flags everything reads) and drives a few child nodes, one per system.
The children hold a reference back to the root and read/write shared state through
it.

Player children: `LockOn`, `Weapon`, `Reaction`, `Ladder`, `Consumable`, `Door`.
Enemy children: `AI`, `Weapon`, `Reaction`.

So `player.gd` is the root and the actual behaviour is split across
`player_lock_on.gd`, `player_weapon.gd`, and so on. Same deal on the enemy side.
If you're looking for where something lives, the header comment on each root
script lists the mapping.

The shared weapon system is `weapon_equipper.gd` — a plain `RefCounted` that
instances a weapon scene under the hand bone, wires up its hitbox, and handles
moving it to the back when sheathed. Both the player and enemy use it. A weapon
is a `WeaponItem` resource pointing at a `.tscn` whose root is an `Area3D` named
`SwordHitbox`. The name matters — the attack animations reference it by path.

## Setup

This won't run out of the box, because it depends on assets I can't ship (the
character model is a VRM, and the animations are from an asset pack).

1. **Input map.** You need these actions defined in Project Settings > Input Map:
   `forward`, `backward`, `leftward`, `rightward`, `roll`, `attack`, `interact`,
   `lock_on`, `consume`, `sheath_weapon`. The scripts warn on startup if any are
   missing.
2. **Model + animations.** Swap in your own. The scenes are built around a humanoid
   rig with a Root bone for root motion; the combo anims are named
   `Sword_Regular_A/B/C` in a library called `MeleeLib`. Rename or rewire to suit.
3. **A weapon.** Make a `WeaponItem` resource pointing at a weapon scene with an
   `Area3D` named `SwordHitbox` at its root, then assign it to `starting_weapon`
   on the player. Without one, attacks do nothing (it warns you).
4. **Sheath point.** The player expects a `Marker3D` at
   `soulslikebody/GeneralSkeleton/wepondisplayback/SheathPoint`. Place it where
   you want the weapon to rest on the back. Skip it and sheathing still works but
   the weapon will sit wherever the offsets put it, which is usually wrong.

## Known rough edges

I'll be honest about the bits that aren't clean:

- The hitbox is toggled off the AnimationTree's current state rather than Call
  Method Tracks on the animations. It works, but if your attack anims have a
  proper hitbox-on/hitbox-off track you'd want to switch to that.
- The weapon swap commit uses a fixed delay if the animation has no Call Method
  Track. There's a hook (`_on_weapon_swap_commit`) for the clean version if you
  add the track.
- Fall damage and hard-landing share the same impact value; tune the two
  thresholds if you want them decoupled.
- No save system, no menu, no audio. It's a controller, not a game template.

## Licence

Do whatever you want with it. Credit's nice but not required.
