extends RefCounted
class_name Inventory

# Stack-based inventory holding Item resources with a count each. It only
# tracks what's owned and which weapon is marked equipped; equipping a weapon
# onto the skeleton is weapon_equipper.gd's job.
#
#   var inventory := Inventory.new()
#   inventory.add_item(some_consumable, 5)

signal inventory_changed
signal weapon_equipped(weapon: WeaponItem)

# Each entry: { "item": Item, "count": int }
var slots : Array[Dictionary] = []

# The currently equipped weapon, mirrored here so the UI can read it without
# reaching into the player.
var equipped_weapon : WeaponItem = null


func add_item(item: Item, count: int = 1) -> void:
	if item == null or count <= 0:
		return

	if item.max_stack > 1:
		var remaining := count
		# Top up existing stacks first.
		for slot in slots:
			if remaining <= 0:
				break
			if slot["item"] == item and slot["count"] < item.max_stack:
				var space : int = item.max_stack - slot["count"]
				var added : int = mini(space, remaining)
				slot["count"] += added
				remaining      -= added

		# Leftovers become new stacks.
		while remaining > 0:
			var chunk : int = mini(remaining, item.max_stack)
			slots.append({ "item": item, "count": chunk })
			remaining -= chunk
	else:
		# Non-stacking items (weapons, armor) get one slot per unit.
		for i in count:
			slots.append({ "item": item, "count": 1 })

	inventory_changed.emit()


# Removes up to `count` of `item`, newest-added slots first. Returns true if the
# full amount was removed; otherwise whatever was available is still removed.
func remove_item(item: Item, count: int = 1) -> bool:
	if item == null or count <= 0:
		return false

	var remaining := count
	var i := slots.size() - 1
	while i >= 0 and remaining > 0:
		var slot : Dictionary = slots[i]
		if slot["item"] == item:
			var take : int = mini(slot["count"], remaining)
			slot["count"] -= take
			remaining      -= take
			if slot["count"] <= 0:
				slots.remove_at(i)
		i -= 1

	if remaining < count:
		inventory_changed.emit()
	return remaining == 0


func get_count(item: Item) -> int:
	var total := 0
	for slot in slots:
		if slot["item"] == item:
			total += slot["count"]
	return total


func has_item(item: Item, count: int = 1) -> bool:
	return get_count(item) >= count


# Distinct owned weapons, for the inventory UI's weapon list.
func get_weapons() -> Array[WeaponItem]:
	var out : Array[WeaponItem] = []
	for slot in slots:
		if slot["item"] is WeaponItem and not out.has(slot["item"]):
			out.append(slot["item"])
	return out


# One { "item": ConsumableItem, "count": int } row per distinct consumable,
# counts summed across stacks.
func get_consumables() -> Array[Dictionary]:
	var merged : Dictionary = {}
	for slot in slots:
		if slot["item"] is ConsumableItem:
			var item : ConsumableItem = slot["item"]
			merged[item] = merged.get(item, 0) + slot["count"]

	var out : Array[Dictionary] = []
	for item in merged:
		out.append({ "item": item, "count": merged[item] })
	return out
