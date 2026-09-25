extends Item
class_name ConsumableItem

# A usable item such as a healing potion. player.gd's consume action heals by
# heal_amount once the drink animation finishes.
#
# Set max_stack on the base Item (e.g. 99) so potions stack into one slot.

@export var heal_amount : float = 40.0


func _init() -> void:
	max_stack = 99
