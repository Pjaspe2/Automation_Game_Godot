extends Control

@onready var _gs: Node = get_node("/root/GameState")
@onready var _map_scroll: ScrollContainer = $HSplit/MapScroll
@onready var _map_view: Control = $HSplit/MapScroll/MapGridView
@onready var _wood_label: Label = $HSplit/Panel/PanelScroll/VBox/WoodLabel
@onready var _wood_rate_label: Label = $HSplit/Panel/PanelScroll/VBox/WoodRateLabel
@onready var _stone_label: Label = $HSplit/Panel/PanelScroll/VBox/StoneLabel
@onready var _stone_rate_label: Label = $HSplit/Panel/PanelScroll/VBox/StoneRateLabel
@onready var _power_rate_label: Label = $HSplit/Panel/PanelScroll/VBox/PowerRateLabel
@onready var _planks_label: Label = $HSplit/Panel/PanelScroll/VBox/PlanksLabel
@onready var _planks_rate_label: Label = $HSplit/Panel/PanelScroll/VBox/PlanksRateLabel
@onready var _shaft_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/ShaftKitsLabel
@onready var _wheel_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/WheelKitsLabel
@onready var _harvester_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/HarvesterKitsLabel
@onready var _factory_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/FactoryKitsLabel
@onready var _storage_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/StorageKitsLabel
@onready var _conveyor_kits_label: Label = $HSplit/Panel/PanelScroll/VBox/ConveyorKitsLabel
@onready var _machine_upgrade_label: Label = $HSplit/Panel/PanelScroll/VBox/MachineUpgradeLabel
@onready var _craft_planks_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftPlanksButton
@onready var _craft_shaft_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftShaftKitButton
@onready var _shaft_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/ShaftPlaceModeButton
@onready var _craft_wheel_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftWheelKitButton
@onready var _craft_harvester_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftHarvesterKitButton
@onready var _craft_factory_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftFactoryKitButton
@onready var _craft_storage_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftStorageKitButton
@onready var _craft_conveyor_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftConveyorKitButton
@onready var _machine_upgrade_button: Button = $HSplit/Panel/PanelScroll/VBox/MachineUpgradeButton
@onready var _wheel_upgrade_button: Button = $HSplit/Panel/PanelScroll/VBox/WheelUpgradeButton
@onready var _factory_upgrade_button: Button = $HSplit/Panel/PanelScroll/VBox/FactoryUpgradeButton
@onready var _wheel_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/WheelPlaceModeButton
@onready var _harvester_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/HarvesterPlaceModeButton
@onready var _factory_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/FactoryPlaceModeButton
@onready var _storage_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/StoragePlaceModeButton
@onready var _conveyor_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/ConveyorPlaceModeButton
@onready var _expand_button: Button = $HSplit/Panel/PanelScroll/VBox/ExpandButton
@onready var _dev_pickup_all_button: Button = $HSplit/Panel/PanelScroll/VBox/DevPickupAllButton
@onready var _hint: Label = $HSplit/Panel/PanelScroll/VBox/HintLabel


func _ready() -> void:
	_craft_planks_button.pressed.connect(_on_craft_planks_pressed)
	_craft_shaft_kit_button.pressed.connect(_on_craft_shaft_kit_pressed)
	_shaft_place_mode_button.pressed.connect(_on_shaft_place_mode_pressed)
	_craft_wheel_kit_button.pressed.connect(_on_craft_wheel_kit_pressed)
	_craft_harvester_kit_button.pressed.connect(_on_craft_harvester_kit_pressed)
	_craft_factory_kit_button.pressed.connect(_on_craft_factory_kit_pressed)
	_craft_storage_kit_button.pressed.connect(_on_craft_storage_kit_pressed)
	_craft_conveyor_kit_button.pressed.connect(_on_craft_conveyor_kit_pressed)
	_machine_upgrade_button.pressed.connect(_on_machine_upgrade_pressed)
	_wheel_upgrade_button.pressed.connect(_on_wheel_upgrade_pressed)
	_factory_upgrade_button.pressed.connect(_on_factory_upgrade_pressed)
	_wheel_place_mode_button.pressed.connect(_on_wheel_place_mode_pressed)
	_harvester_place_mode_button.pressed.connect(_on_harvester_place_mode_pressed)
	_factory_place_mode_button.pressed.connect(_on_factory_place_mode_pressed)
	_storage_place_mode_button.pressed.connect(_on_storage_place_mode_pressed)
	_conveyor_place_mode_button.pressed.connect(_on_conveyor_place_mode_pressed)
	_expand_button.pressed.connect(_on_expand_pressed)
	_dev_pickup_all_button.pressed.connect(_on_dev_pickup_all_pressed)
	_map_scroll.gui_input.connect(_on_map_scroll_gui_input)
	_gs.world_changed.connect(_on_world_changed)
	_on_world_changed()


func _process(_delta: float) -> void:
	_wood_label.text = "Wood: %s" % _fmt(_gs.wood)
	_wood_rate_label.text = "Wood/s: +%s in, -%s use, net %s (auto: %s from %d harvesters)" % [
		_fmt(_gs.get_wood_collection_per_sec()),
		_fmt(_gs.get_wood_usage_per_sec()),
		_fmt(_gs.get_net_wood_per_sec()),
		_fmt(_gs.get_auto_wood_per_sec()),
		_gs.get_powered_harvester_count(),
	]
	_stone_label.text = "Stone: %s" % _fmt(_gs.stone)
	_stone_rate_label.text = "Stone/s: %s (auto from quarry-adjacent harvesters)" % _fmt(_gs.get_total_stone_per_sec())
	_power_rate_label.text = "Power/s: +%s gen, -%s use, net %s" % [
		_fmt(_gs.get_power_generated_per_sec()),
		_fmt(_gs.get_power_consumed_per_sec()),
		_fmt(_gs.get_power_surplus_per_sec()),
	]
	_planks_label.text = "Planks: %s" % _fmt(_gs.planks)
	_planks_rate_label.text = "Planks/s: %s (auto factory)" % _fmt(_gs.get_auto_planks_per_sec())
	_shaft_kits_label.text = "Shaft kits: %s" % _fmt(_gs.shaft_kits)
	_wheel_kits_label.text = "Wheel kits: %s" % _fmt(_gs.wheel_kits)
	_harvester_kits_label.text = "Harvester kits: %s" % _fmt(_gs.harvester_kits)
	_factory_kits_label.text = "Factory kits: %s" % _fmt(_gs.factory_kits)
	_storage_kits_label.text = "Storage kits: %s" % _fmt(_gs.storage_kits)
	_conveyor_kits_label.text = "Conveyor kits: %s" % _fmt(_gs.conveyor_kits)
	_machine_upgrade_label.text = "Machine level: %d (x%s output)" % [
		_gs.machine_upgrade_level,
		_fmt(_gs.get_machine_rate_multiplier()),
	]
	_machine_upgrade_label.text += " | Wheel L%d (x%s power) | Factory L%d (x%s speed)" % [
		_gs.wheel_upgrade_level,
		_fmt(_gs.get_wheel_power_multiplier()),
		_gs.factory_upgrade_level,
		_fmt(_gs.get_factory_rate_multiplier()),
	]
	_craft_planks_button.text = "Craft plank (%s wood)" % _fmt(_gs.PLANK_WOOD_COST)
	_craft_planks_button.disabled = not _gs.can_craft_planks()
	_craft_shaft_kit_button.text = "Craft shaft kit (%s planks + %s stone)" % [
		_fmt(_gs.SHAFT_KIT_PLANK_COST),
		_fmt(_gs.SHAFT_KIT_STONE_COST),
	]
	_craft_shaft_kit_button.disabled = not _gs.can_craft_shaft_kit()
	_craft_wheel_kit_button.text = "Craft wheel kit (%s planks + %s stone)" % [
		_fmt(_gs.WHEEL_KIT_PLANK_COST),
		_fmt(_gs.WHEEL_KIT_STONE_COST),
	]
	_craft_wheel_kit_button.disabled = not _gs.can_craft_wheel_kit()
	_craft_harvester_kit_button.text = "Craft harvester kit (%s planks + %s stone)" % [
		_fmt(_gs.HARVESTER_KIT_PLANK_COST),
		_fmt(_gs.HARVESTER_KIT_STONE_COST),
	]
	_craft_harvester_kit_button.disabled = not _gs.can_craft_harvester_kit()
	_craft_factory_kit_button.text = "Craft factory kit (%s planks + %s stone)" % [
		_fmt(_gs.FACTORY_KIT_PLANK_COST),
		_fmt(_gs.FACTORY_KIT_STONE_COST),
	]
	_craft_factory_kit_button.disabled = not _gs.can_craft_factory_kit()
	_craft_storage_kit_button.text = "Craft storage kit (%s planks + %s stone)" % [
		_fmt(_gs.STORAGE_KIT_PLANK_COST),
		_fmt(_gs.STORAGE_KIT_STONE_COST),
	]
	_craft_storage_kit_button.disabled = not _gs.can_craft_storage_kit()
	_craft_conveyor_kit_button.text = "Craft conveyor kit (%s planks + %s stone -> %s)" % [
		_fmt(_gs.CONVEYOR_KIT_PLANK_COST),
		_fmt(_gs.CONVEYOR_KIT_STONE_COST),
		_fmt(_gs.CONVEYOR_KITS_PER_CRAFT),
	]
	_craft_conveyor_kit_button.disabled = not _gs.can_craft_conveyor_kit()
	_machine_upgrade_button.text = "Upgrade machines (%s planks + %s stone)" % [
		_fmt(_gs.get_machine_upgrade_cost_planks()),
		_fmt(_gs.get_machine_upgrade_cost_stone()),
	]
	_machine_upgrade_button.disabled = not _gs.can_buy_machine_upgrade()
	_wheel_upgrade_button.text = "Upgrade wheels (%s planks + %s stone)" % [
		_fmt(_gs.get_wheel_upgrade_cost_planks()),
		_fmt(_gs.get_wheel_upgrade_cost_stone()),
	]
	_wheel_upgrade_button.disabled = not _gs.can_buy_wheel_upgrade()
	_factory_upgrade_button.text = "Upgrade factories (%s planks + %s stone)" % [
		_fmt(_gs.get_factory_upgrade_cost_planks()),
		_fmt(_gs.get_factory_upgrade_cost_stone()),
	]
	_factory_upgrade_button.disabled = not _gs.can_buy_factory_upgrade()
	_shaft_place_mode_button.text = "Shaft place: %s" % ("ON (grass)" if _gs.shaft_place_mode else "OFF")
	_wheel_place_mode_button.text = "Wheel place: %s" % ("ON (river)" if _gs.wheel_place_mode else "OFF")
	_harvester_place_mode_button.text = "Harvester place: %s" % ("ON (grass)" if _gs.harvester_place_mode else "OFF")
	_factory_place_mode_button.text = "Factory place: %s" % ("ON (grass)" if _gs.factory_place_mode else "OFF")
	_storage_place_mode_button.text = "Storage place: %s" % ("ON (grass)" if _gs.storage_place_mode else "OFF")
	_conveyor_place_mode_button.text = "Conveyor place: %s" % ("ON (grass)" if _gs.conveyor_place_mode else "OFF")
	_shaft_place_mode_button.disabled = _gs.shaft_kits < 1.0 and not _gs.shaft_place_mode
	_wheel_place_mode_button.disabled = _gs.wheel_kits < 1.0 and not _gs.wheel_place_mode
	_harvester_place_mode_button.disabled = _gs.harvester_kits < 1.0 and not _gs.harvester_place_mode
	_factory_place_mode_button.disabled = _gs.factory_kits < 1.0 and not _gs.factory_place_mode
	_storage_place_mode_button.disabled = _gs.storage_kits < 1.0 and not _gs.storage_place_mode
	_conveyor_place_mode_button.disabled = _gs.conveyor_kits < 1.0 and not _gs.conveyor_place_mode
	var cost: float = float(_gs.EXPANSION_WOOD_COST)
	if _gs.territory_expanded:
		_expand_button.text = "Territory expanded"
		_expand_button.disabled = true
	else:
		_expand_button.text = "Expand territory — %s wood" % _fmt(cost)
		_expand_button.disabled = not _gs.can_expand_territory()
	_dev_pickup_all_button.disabled = _gs.get_placed_shafts().is_empty() and _gs.get_placed_wheels().is_empty() and _gs.get_placed_harvesters().is_empty() and _gs.get_placed_factories().is_empty() and _gs.get_placed_storages().is_empty() and _gs.get_placed_conveyors().is_empty()


func _on_expand_pressed() -> void:
	_gs.try_expand_territory()


func _on_dev_pickup_all_pressed() -> void:
	_gs.dev_pickup_all_placeables()


func _on_map_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_map_view.zoom_by_wheel_direction(true)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_map_view.zoom_by_wheel_direction(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var factor: float = 1.0 + float(event.factor)
		if factor > 0.0:
			_map_view.zoom_by_factor(factor)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD:
			_map_view.zoom_by_wheel_direction(true)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_map_view.zoom_by_wheel_direction(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
			_map_view.reset_zoom()
			get_viewport().set_input_as_handled()


func _on_craft_planks_pressed() -> void:
	_gs.craft_planks()


func _on_craft_shaft_kit_pressed() -> void:
	_gs.craft_shaft_kit()


func _on_shaft_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.shaft_place_mode else "shaft")


func _on_craft_wheel_kit_pressed() -> void:
	_gs.craft_wheel_kit()


func _on_craft_harvester_kit_pressed() -> void:
	_gs.craft_harvester_kit()


func _on_craft_factory_kit_pressed() -> void:
	_gs.craft_factory_kit()


func _on_craft_storage_kit_pressed() -> void:
	_gs.craft_storage_kit()


func _on_craft_conveyor_kit_pressed() -> void:
	_gs.craft_conveyor_kit()


func _on_machine_upgrade_pressed() -> void:
	_gs.buy_machine_upgrade()


func _on_wheel_upgrade_pressed() -> void:
	_gs.buy_wheel_upgrade()


func _on_factory_upgrade_pressed() -> void:
	_gs.buy_factory_upgrade()


func _on_wheel_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.wheel_place_mode else "wheel")


func _on_harvester_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.harvester_place_mode else "harvester")


func _on_factory_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.factory_place_mode else "factory")


func _on_storage_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.storage_place_mode else "storage")


func _on_conveyor_place_mode_pressed() -> void:
	_gs.set_place_mode("" if _gs.conveyor_place_mode else "conveyor")


func _on_world_changed() -> void:
	_hint.text = "Click green trees to chop (%.0fx wood). Stumps regrow after ~%d s. Home adds a trickle of wood." % [
		_gs.MANUAL_WOOD_MULT,
		int(_gs.TREE_REGROW_SEC),
	]
	_hint.text += " Craft planks at home for future recipes (%s wood -> %s plank)." % [
		_fmt(_gs.PLANK_WOOD_COST),
		_fmt(_gs.PLANKS_PER_CRAFT),
	]
	_hint.text += " Craft shaft kits (%s planks + %s stone), then enable shaft place mode and click grass." % [
		_fmt(_gs.SHAFT_KIT_PLANK_COST),
		_fmt(_gs.SHAFT_KIT_STONE_COST),
	]
	_hint.text += " Craft wheel kits and place on river."
	_hint.text += " Conveyors now carry both power and materials: harvesters/factories run only when conveyor network reaches both a wheel and storage."
	_hint.text += " Factories consume logistics wood from that same connected network."
	_hint.text += " Logistics wood: %s / %s capacity." % [_fmt(_gs.logistics_wood), _fmt(_gs.get_storage_capacity())]
	_hint.text += " Harvester role is fixed on placement: tree-adjacent = wood, quarry-adjacent = stone."
	_hint.text += " Machine upgrades improve harvesters, wheel upgrades improve power output, and factory upgrades improve plank throughput."
	_hint.text += " When power use exceeds generation, harvester efficiency is throttled."
	_hint.text += " In any place mode, left-click existing objects to pick up; right-click also picks up and refunds kits."
	_hint.text += " Quarry tiles darken while cooling down after mining."
	if _gs.territory_expanded:
		_hint.text += " Grey quarry tiles: click to mine stone (+%s each, %ds cooldown per tile). Brown = copper mine (not wired yet)." % [
			_fmt(_gs.STONE_PER_MANUAL_GATHER),
			int(_gs.QUARRY_COOLDOWN_SEC),
		]


func _fmt(n: float) -> String:
	if absf(n) >= 1_000_000.0:
		return "%.2e" % n
	if absf(n) >= 1000.0:
		return "%.2f" % n
	return str(snappedf(n, 0.01))
