extends CanvasLayer
class_name InventoryUI

# Slot-based inventory / equip menu, built entirely in code. Toggle it with
# the "inventory" input action (see Project Settings -> Input Map).
#
# Usage:
#   inventory_ui = InventoryUI.new()
#   add_child(inventory_ui)
#   inventory_ui.setup(self, inventory)
#
# Layout: a Weapon slot and a Consumable slot up top, each with < > arrows to
# cycle owned items, plus the full owned lists below. `is_open` is public so
# player.gd can gate movement input while the menu has the mouse.
#
# The bottom-right quickbar is a small always-visible readout (equipped weapon
# and selected consumable) that stays on screen whether the panel is open or
# closed, and shares the same _refresh() pass as the panel.

var player    : Node      = null
var inventory : Inventory = null

var is_open := false

var _panel            : PanelContainer
var _weapon_list       : VBoxContainer
var _consumable_list   : VBoxContainer

var _weapon_slot_icon   : TextureRect
var _weapon_slot_name   : Label
var _consumable_slot_icon : TextureRect
var _consumable_slot_name : Label

var _quickbar               : PanelContainer
var _quickbar_weapon_icon    : TextureRect
var _quickbar_consumable_icon : TextureRect
var _quickbar_consumable_count : Label

const PANEL_SIZE      := Vector2(420, 560)
const SLOT_ICON_SIZE  := Vector2(64, 64)
const LIST_ICON_SIZE  := Vector2(32, 32)
const QUICKBAR_ICON_SIZE := Vector2(48, 48)
const QUICKBAR_MARGIN    := 24


func setup(p_player: Node, p_inventory: Inventory) -> void:
	player    = p_player
	inventory = p_inventory
	inventory.inventory_changed.connect(_refresh)
	_build_ui()
	_refresh()
	_set_menu_open(false)


func _build_ui() -> void:
	layer = 10

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.position               = Vector2(-PANEL_SIZE.x - 40, -PANEL_SIZE.y * 0.5)
	_panel.custom_minimum_size    = PANEL_SIZE
	_panel.mouse_filter           = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# ── EQUIPMENT SLOTS ───────────────────────────────────────────────────
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 16)
	vbox.add_child(slots_row)

	var weapon_slot := _make_slot_box("Weapon")
	slots_row.add_child(weapon_slot["box"])
	_weapon_slot_icon = weapon_slot["icon"]
	_weapon_slot_name = weapon_slot["name_label"]
	weapon_slot["prev"].pressed.connect(_on_weapon_slot_cycle.bind(-1))
	weapon_slot["next"].pressed.connect(_on_weapon_slot_cycle.bind(1))

	var consumable_slot := _make_slot_box("Consumable")
	slots_row.add_child(consumable_slot["box"])
	_consumable_slot_icon = consumable_slot["icon"]
	_consumable_slot_name = consumable_slot["name_label"]
	consumable_slot["prev"].pressed.connect(_on_consumable_slot_cycle.bind(-1))
	consumable_slot["next"].pressed.connect(_on_consumable_slot_cycle.bind(1))

	vbox.add_child(HSeparator.new())

	vbox.add_child(_make_section_label("Owned Weapons"))
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_weapon_list)

	vbox.add_child(_make_section_label("Owned Consumables"))
	_consumable_list = VBoxContainer.new()
	_consumable_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_consumable_list)

	# ── QUICKBAR (always visible, bottom-right) ────────────────────────────
	_build_quickbar(root)


# Small persistent readout in the bottom-right corner: equipped weapon icon
# on the left, selected consumable icon + "xN" count on the right. Built
# under `root` (not `_panel`) and never touched by _set_menu_open(), so it
# stays on screen regardless of whether the full inventory panel is open.
func _build_quickbar(root: Control) -> void:
	_quickbar = PanelContainer.new()
	_quickbar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_quickbar.position         = Vector2(-QUICKBAR_MARGIN, -QUICKBAR_MARGIN)
	_quickbar.grow_horizontal  = Control.GROW_DIRECTION_BEGIN
	_quickbar.grow_vertical    = Control.GROW_DIRECTION_BEGIN
	_quickbar.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	root.add_child(_quickbar)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	_quickbar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_quickbar_weapon_icon = _make_quickbar_icon()
	row.add_child(_quickbar_weapon_icon)

	row.add_child(VSeparator.new())

	var consumable_box := HBoxContainer.new()
	consumable_box.add_theme_constant_override("separation", 6)
	row.add_child(consumable_box)

	_quickbar_consumable_icon = _make_quickbar_icon()
	consumable_box.add_child(_quickbar_consumable_icon)

	_quickbar_consumable_count = Label.new()
	_quickbar_consumable_count.text = "x0"
	_quickbar_consumable_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quickbar_consumable_count.add_theme_font_size_override("font_size", 18)
	consumable_box.add_child(_quickbar_consumable_count)


func _make_quickbar_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = QUICKBAR_ICON_SIZE
	icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


# Builds one "Weapon" / "Consumable" slot box: a bordered panel with an
# icon, an item-name label, and < > cycle buttons underneath. Returned as a
# Dictionary of the pieces the caller needs to hook up rather than a custom
# class, since this is only ever used twice, right here.
func _make_slot_box(label_text: String) -> Dictionary:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(inner)

	var header := Label.new()
	header.text                   = label_text
	header.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate               = Color(0.8, 0.8, 0.8)
	header.add_theme_font_size_override("font_size", 14)
	inner.add_child(header)

	var icon := TextureRect.new()
	icon.custom_minimum_size = SLOT_ICON_SIZE
	icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var icon_bg := PanelContainer.new()
	icon_bg.custom_minimum_size = SLOT_ICON_SIZE
	icon_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_bg.add_child(icon)
	inner.add_child(icon_bg)

	var name_label := Label.new()
	name_label.text                   = "-"
	name_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_label)

	var arrows := HBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	arrows.add_theme_constant_override("separation", 8)
	inner.add_child(arrows)

	var prev_button := Button.new()
	prev_button.text = "<"
	arrows.add_child(prev_button)

	var next_button := Button.new()
	next_button.text = ">"
	arrows.add_child(next_button)

	return {
		"box":        box,
		"icon":       icon,
		"name_label": name_label,
		"prev":       prev_button,
		"next":       next_button,
	}


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text     = text
	label.modulate = Color(0.8, 0.8, 0.8)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text     = text
	label.modulate = Color(0.6, 0.6, 0.6)
	return label


func _make_icon_rect(icon: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = LIST_ICON_SIZE
	rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture             = icon
	return rect


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_set_menu_open(not _panel.visible)
		get_viewport().set_input_as_handled()
		return
	# Escape always closes the panel if it's open (and only then — otherwise Esc
	# stays free for other uses like pausing).
	if _panel.visible and event.is_action_pressed("ui_cancel"):
		_set_menu_open(false)
		get_viewport().set_input_as_handled()


# Single place that flips the panel visible/hidden AND everything that needs
# to change alongside it - the mouse mode and the camera's mouse-look input.
# Previously only `_panel.visible` was toggled, so the mouse stayed captured
# (invisible, locked to screen center) the whole time the menu was open,
# making the Equip/Use buttons unreachable. Deliberately doesn't touch
# `_quickbar` — that stays visible whether the panel is open or closed.
func _set_menu_open(open: bool) -> void:
	_panel.visible = open
	is_open        = open

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

	if player != null and "cam_script" in player and player.cam_script != null:
		player.cam_script.input_enabled = not open

	if open:
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(_weapon_list):
		return

	for child in _weapon_list.get_children():
		child.queue_free()
	for child in _consumable_list.get_children():
		child.queue_free()

	var weapons := inventory.get_weapons()
	for weapon in weapons:
		_weapon_list.add_child(_make_weapon_row(weapon))
	if weapons.is_empty():
		_weapon_list.add_child(_make_empty_label("No weapons"))

	var consumables := inventory.get_consumables()
	for entry in consumables:
		_consumable_list.add_child(_make_consumable_row(entry["item"], entry["count"]))
	if consumables.is_empty():
		_consumable_list.add_child(_make_empty_label("No consumables"))

	_refresh_slots(weapons, consumables)


# Updates the two equipment slots at the top from whatever's currently
# equipped/selected. Called after every inventory change so picking
# something up, using a potion, or equipping from the list below all stay
# in sync with the slots automatically. Also drives the always-on quickbar
# so it never falls out of sync with the full panel.
func _refresh_slots(weapons: Array[WeaponItem], consumables: Array[Dictionary]) -> void:
	var equipped_weapon : WeaponItem = inventory.equipped_weapon
	if equipped_weapon != null:
		_weapon_slot_icon.texture = equipped_weapon.icon
		_weapon_slot_name.text    = equipped_weapon.item_name
	else:
		_weapon_slot_icon.texture = null
		_weapon_slot_name.text    = "Unarmed"

	var selected : ConsumableItem = player.selected_consumable if player != null else null
	var selected_count := 0
	if selected != null:
		selected_count = inventory.get_count(selected)
		_consumable_slot_icon.texture = selected.icon
		_consumable_slot_name.text    = "%s x%d" % [selected.item_name, selected_count]
	elif not consumables.is_empty():
		selected           = consumables[0]["item"]
		selected_count      = consumables[0]["count"]
		_consumable_slot_icon.texture = selected.icon
		_consumable_slot_name.text    = "%s x%d" % [selected.item_name, selected_count]
	else:
		_consumable_slot_icon.texture = null
		_consumable_slot_name.text    = "None"

	_refresh_quickbar(equipped_weapon, selected, selected_count)


func _refresh_quickbar(equipped_weapon: WeaponItem, selected_consumable: ConsumableItem, selected_count: int) -> void:
	if not is_instance_valid(_quickbar):
		return

	_quickbar_weapon_icon.texture = equipped_weapon.icon if equipped_weapon != null else null

	if selected_consumable != null:
		_quickbar_consumable_icon.texture = selected_consumable.icon
		_quickbar_consumable_count.text   = "x%d" % selected_count
	else:
		_quickbar_consumable_icon.texture = null
		_quickbar_consumable_count.text   = "x0"


func _make_weapon_row(weapon: WeaponItem) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	row.add_child(_make_icon_rect(weapon.icon))

	var is_equipped := inventory.equipped_weapon == weapon

	var label := Label.new()
	label.text                     = weapon.item_name + ("  (equipped)" if is_equipped else "")
	label.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	if is_equipped:
		label.modulate = Color(0.6, 1.0, 0.6)
	row.add_child(label)

	var button := Button.new()
	button.text     = "Equip"
	button.disabled = is_equipped
	button.pressed.connect(_on_equip_pressed.bind(weapon))
	row.add_child(button)

	return row


func _make_consumable_row(item: ConsumableItem, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	row.add_child(_make_icon_rect(item.icon))

	var is_selected : bool = player != null and player.selected_consumable == item

	var label := Label.new()
	label.text                  = "%s x%d" % [item.item_name, count] + ("  (selected)" if is_selected else "")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_selected:
		label.modulate = Color(0.6, 1.0, 0.6)
	row.add_child(label)

	var select_button := Button.new()
	select_button.text     = "Select"
	select_button.disabled = is_selected
	select_button.pressed.connect(_on_select_consumable_pressed.bind(item))
	row.add_child(select_button)

	var use_button := Button.new()
	use_button.text = "Use"
	use_button.pressed.connect(_on_use_pressed.bind(item))
	row.add_child(use_button)

	return row


func _on_equip_pressed(weapon: WeaponItem) -> void:
	if player != null and player.has_method("equip_weapon"):
		player.equip_weapon(weapon)
		_refresh()


func _on_use_pressed(item: ConsumableItem) -> void:
	if player != null and player.has_method("use_consumable"):
		player.use_consumable(item)


func _on_select_consumable_pressed(item: ConsumableItem) -> void:
	if player != null:
		player.selected_consumable = item
		_refresh()


# ── SLOT CYCLING ─────────────────────────────────────────────────────────────
# < > on the Weapon slot equips the next/previous owned weapon; on the
# Consumable slot it just changes `selected_consumable` (what the "consume"
# hotkey drinks) without spending anything.

func _on_weapon_slot_cycle(direction: int) -> void:
	var weapons := inventory.get_weapons()
	if weapons.is_empty() or player == null:
		return

	var current_index := weapons.find(inventory.equipped_weapon)
	var next_index     := current_index + direction
	if current_index == -1:
		next_index = 0
	else:
		next_index = wrapi(next_index, 0, weapons.size())

	player.equip_weapon(weapons[next_index])
	_refresh()


func _on_consumable_slot_cycle(direction: int) -> void:
	var consumables := inventory.get_consumables()
	if consumables.is_empty() or player == null:
		return

	var items : Array = consumables.map(func(e): return e["item"])
	var current_index := items.find(player.selected_consumable)
	var next_index     := current_index + direction
	if current_index == -1:
		next_index = 0
	else:
		next_index = wrapi(next_index, 0, items.size())

	player.selected_consumable = items[next_index]
	_refresh()
