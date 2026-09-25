extends Item
class_name ArmorItem

# Placeholder for a future armor system. Armor can be picked up and stored, but
# there is no equip slot or defense stat wired up yet.

@export var defense : float  = 0.0
@export var slot     : String = "chest"   # "head" / "chest" / "legs" / ...
