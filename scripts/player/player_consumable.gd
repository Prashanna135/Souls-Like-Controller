extends Node2D

# Drinking consumables. Both the hotkey and the inventory UI's "Use" button
# route through here; the heal lands partway through the Consume one-shot
# rather than the instant it's used, so the animation reads as the drink doing
# the work.

var player: CharacterBody3D = null

var is_consuming := false
var _entered := false
var _timer := 0.0
var _healed := false
var _active_item: ConsumableItem = null


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


# Returns false (and does nothing) if the player is busy, airborne, already at
# full health, or doesn't hold the item.
func use(item: ConsumableItem) -> bool:
	if item == null or player.is_dead:
		return false
	if player.is_attacking or player.is_rolling or player.is_jumpback or player.is_stunned():
		return false
	if player.ladder.is_busy():
		return false
	if not player.is_on_floor():
		return false
	if not player.inventory.has_item(item, 1) or player.current_health >= player.max_health:
		return false

	_start(item)
	return true


func _start(item: ConsumableItem) -> void:
	is_consuming = true
	_entered = false
	_healed = false
	_timer = 0.0
	# Snapshot the item so switching the selected consumable mid-drink can't
	# change how much gets healed.
	_active_item = item
	player.inventory.remove_item(item, 1)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.animation_tree.set(player.CONSUME_ONE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func update(delta: float) -> void:
	if not is_consuming:
		return

	_timer += delta
	var active: bool = player.animation_tree.get(player.CONSUME_ACTIVE)
	if active:
		_entered = true

	# Heal once — either when the one-shot's active flag drops, or after
	# consume_heal_time. Without the timer fallback a mis-wired tree would
	# swallow the potion silently.
	if not _healed and ((_entered and not active) or _timer >= player.consume_heal_time):
		_heal()

	if (_entered and not active) or _timer >= player.consume_max_time:
		is_consuming = false
		player.current_speed = player.sprint_speed


func _heal() -> void:
	_healed = true
	var amount := _active_item.heal_amount if _active_item != null else 0.0
	player.current_health = minf(player.current_health + amount, player.max_health)
	_active_item = null

func cancel() -> void:
	is_consuming = false
