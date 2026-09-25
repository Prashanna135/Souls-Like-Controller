extends Resource
class_name Item

# Base resource for anything that can go in the inventory. Concrete types
# (WeaponItem, ConsumableItem, ArmorItem) extend this with their own fields;
# Item holds only what every item needs for display.
#
# To create an item: FileSystem -> right click -> New Resource -> pick a type
# (e.g. WeaponItem), save it as a .tres, then fill in the fields in the
# Inspector and drop the .tres onto an @export slot or give it to
# Inventory.add_item().

@export var item_name   : String     = "Item"
@export var description : String     = ""
@export var icon        : Texture2D  = null
@export var max_stack   : int        = 1   # 1 = doesn't stack; higher for consumables
