extends Control

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
@onready var _machine_upgrade_label: Label = $HSplit/Panel/PanelScroll/VBox/MachineUpgradeLabel
@onready var _craft_planks_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftPlanksButton
@onready var _craft_shaft_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftShaftKitButton
@onready var _shaft_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/ShaftPlaceModeButton
@onready var _craft_wheel_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftWheelKitButton
@onready var _craft_harvester_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftHarvesterKitButton
@onready var _craft_factory_kit_button: Button = $HSplit/Panel/PanelScroll/VBox/CraftFactoryKitButton
@onready var _machine_upgrade_button: Button = $HSplit/Panel/PanelScroll/VBox/MachineUpgradeButton
@onready var _wheel_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/WheelPlaceModeButton
@onready var _harvester_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/HarvesterPlaceModeButton
@onready var _factory_place_mode_button: Button = $HSplit/Panel/PanelScroll/VBox/FactoryPlaceModeButton
@onready var _expand_button: Button = $HSplit/Panel/PanelScroll/VBox/ExpandButton
@onready var _hint: Label = $HSplit/Panel/PanelScroll/VBox/HintLabel


func _ready() -> void:
	_craft_planks_button.pressed.connect(_on_craft_planks_pressed)
	_craft_shaft_kit_button.pressed.connect(_on_craft_shaft_kit_pressed)
	_shaft_place_mode_button.pressed.connect(_on_shaft_place_mode_pressed)
	_craft_wheel_kit_button.pressed.connect(_on_craft_wheel_kit_pressed)
	_craft_harvester_kit_button.pressed.connect(_on_craft_harvester_kit_pressed)
	_craft_factory_kit_button.pressed.connect(_on_craft_factory_kit_pressed)
	_machine_upgrade_button.pressed.connect(_on_machine_upgrade_pressed)
	_wheel_place_mode_button.pressed.connect(_on_wheel_place_mode_pressed)
	_harvester_place_mode_button.pressed.connect(_on_harvester_place_mode_pressed)
	_factory_place_mode_button.pressed.connect(_on_factory_place_mode_pressed)
	_expand_button.pressed.connect(_on_expand_pressed)
	GameState.world_changed.connect(_on_world_changed)
	_on_world_changed()


func _process(_delta: float) -> void:
	_wood_label.text = "Wood: %s" % _fmt(GameState.wood)
	_wood_rate_label.text = "Wood/s: %s (auto: %s from %d harvesters)" % [
		_fmt(GameState.get_total_wood_per_sec()),
		_fmt(GameState.get_auto_wood_per_sec()),
		GameState.get_powered_harvester_count(),
	]
	_stone_label.text = "Stone: %s" % _fmt(GameState.stone)
	_stone_rate_label.text = "Stone/s: %s (auto from quarry-adjacent harvesters)" % _fmt(GameState.get_total_stone_per_sec())
	_power_rate_label.text = "Power/s: +%s gen, -%s use, net %s" % [
		_fmt(GameState.get_power_generated_per_sec()),
		_fmt(GameState.get_power_consumed_per_sec()),
		_fmt(GameState.get_power_surplus_per_sec()),
	]
	_planks_label.text = "Planks: %s" % _fmt(GameState.planks)
	_planks_rate_label.text = "Planks/s: %s (auto factory)" % _fmt(GameState.get_auto_planks_per_sec())
	_shaft_kits_label.text = "Shaft kits: %s" % _fmt(GameState.shaft_kits)
	_wheel_kits_label.text = "Wheel kits: %s" % _fmt(GameState.wheel_kits)
	_harvester_kits_label.text = "Harvester kits: %s" % _fmt(GameState.harvester_kits)
	_factory_kits_label.text = "Factory kits: %s" % _fmt(GameState.factory_kits)
	_machine_upgrade_label.text = "Machine level: %d (x%s output)" % [
		GameState.machine_upgrade_level,
		_fmt(GameState.get_machine_rate_multiplier()),
	]
	_craft_planks_button.text = "Craft plank (%s wood)" % _fmt(GameState.PLANK_WOOD_COST)
	_craft_planks_button.disabled = not GameState.can_craft_planks()
	_craft_shaft_kit_button.text = "Craft shaft kit (%s planks + %s stone)" % [
		_fmt(GameState.SHAFT_KIT_PLANK_COST),
		_fmt(GameState.SHAFT_KIT_STONE_COST),
	]
	_craft_shaft_kit_button.disabled = not GameState.can_craft_shaft_kit()
	_craft_wheel_kit_button.text = "Craft wheel kit (%s planks + %s stone)" % [
		_fmt(GameState.WHEEL_KIT_PLANK_COST),
		_fmt(GameState.WHEEL_KIT_STONE_COST),
	]
	_craft_wheel_kit_button.disabled = not GameState.can_craft_wheel_kit()
	_craft_harvester_kit_button.text = "Craft harvester kit (%s planks + %s stone)" % [
		_fmt(GameState.HARVESTER_KIT_PLANK_COST),
		_fmt(GameState.HARVESTER_KIT_STONE_COST),
	]
	_craft_harvester_kit_button.disabled = not GameState.can_craft_harvester_kit()
	_craft_factory_kit_button.text = "Craft factory kit (%s planks + %s stone)" % [
		_fmt(GameState.FACTORY_KIT_PLANK_COST),
		_fmt(GameState.FACTORY_KIT_STONE_COST),
	]
	_craft_factory_kit_button.disabled = not GameState.can_craft_factory_kit()
	_machine_upgrade_button.text = "Upgrade machines (%s planks + %s stone)" % [
		_fmt(GameState.get_machine_upgrade_cost_planks()),
		_fmt(GameState.get_machine_upgrade_cost_stone()),
	]
	_machine_upgrade_button.disabled = not GameState.can_buy_machine_upgrade()
	_shaft_place_mode_button.text = "Shaft place: %s" % ("ON (grass)" if GameState.shaft_place_mode else "OFF")
	_wheel_place_mode_button.text = "Wheel place: %s" % ("ON (river)" if GameState.wheel_place_mode else "OFF")
	_harvester_place_mode_button.text = "Harvester place: %s" % ("ON (grass)" if GameState.harvester_place_mode else "OFF")
	_factory_place_mode_button.text = "Factory place: %s" % ("ON (grass)" if GameState.factory_place_mode else "OFF")
	_shaft_place_mode_button.disabled = GameState.shaft_kits < 1.0 and not GameState.shaft_place_mode
	_wheel_place_mode_button.disabled = GameState.wheel_kits < 1.0 and not GameState.wheel_place_mode
	_harvester_place_mode_button.disabled = GameState.harvester_kits < 1.0 and not GameState.harvester_place_mode
	_factory_place_mode_button.disabled = GameState.factory_kits < 1.0 and not GameState.factory_place_mode
	var cost := GameState.EXPANSION_WOOD_COST
	if GameState.territory_expanded:
		_expand_button.text = "Territory expanded"
		_expand_button.disabled = true
	else:
		_expand_button.text = "Expand territory — %s wood" % _fmt(cost)
		_expand_button.disabled = not GameState.can_expand_territory()


func _on_expand_pressed() -> void:
	GameState.try_expand_territory()


func _on_craft_planks_pressed() -> void:
	GameState.craft_planks()


func _on_craft_shaft_kit_pressed() -> void:
	GameState.craft_shaft_kit()


func _on_shaft_place_mode_pressed() -> void:
	GameState.set_place_mode("" if GameState.shaft_place_mode else "shaft")


func _on_craft_wheel_kit_pressed() -> void:
	GameState.craft_wheel_kit()


func _on_craft_harvester_kit_pressed() -> void:
	GameState.craft_harvester_kit()


func _on_craft_factory_kit_pressed() -> void:
	GameState.craft_factory_kit()


func _on_machine_upgrade_pressed() -> void:
	GameState.buy_machine_upgrade()


func _on_wheel_place_mode_pressed() -> void:
	GameState.set_place_mode("" if GameState.wheel_place_mode else "wheel")


func _on_harvester_place_mode_pressed() -> void:
	GameState.set_place_mode("" if GameState.harvester_place_mode else "harvester")


func _on_factory_place_mode_pressed() -> void:
	GameState.set_place_mode("" if GameState.factory_place_mode else "factory")


func _on_world_changed() -> void:
	_hint.text = "Click green trees to chop (%.0fx wood). Stumps regrow after ~%d s. Home adds a trickle of wood." % [
		GameState.MANUAL_WOOD_MULT,
		int(GameState.TREE_REGROW_SEC),
	]
	_hint.text += " Craft planks at home for future recipes (%s wood -> %s plank)." % [
		_fmt(GameState.PLANK_WOOD_COST),
		_fmt(GameState.PLANKS_PER_CRAFT),
	]
	_hint.text += " Craft shaft kits (%s planks + %s stone), then enable shaft place mode and click grass." % [
		_fmt(GameState.SHAFT_KIT_PLANK_COST),
		_fmt(GameState.SHAFT_KIT_STONE_COST),
	]
	_hint.text += " Craft wheel kits and place on river; craft harvesters and place on grass next to powered shafts."
	_hint.text += " Craft factory kits and place factories on grass to auto-convert wood into planks (no power required)."
	_hint.text += " Factory visuals dim when wood input is insufficient."
	_hint.text += " Harvester role is fixed on placement: tree-adjacent = wood, quarry-adjacent = stone."
	_hint.text += " Machine upgrades improve wood/stone output per powered harvester."
	_hint.text += " In any place mode, left-click existing objects to pick up; right-click also picks up and refunds kits."
	_hint.text += " Quarry tiles darken while cooling down after mining."
	if GameState.territory_expanded:
		_hint.text += " Grey quarry tiles: click to mine stone (+%s each, %ds cooldown per tile). Brown = copper mine (not wired yet)." % [
			_fmt(GameState.STONE_PER_MANUAL_GATHER),
			int(GameState.QUARRY_COOLDOWN_SEC),
		]


func _fmt(n: float) -> String:
	if absf(n) >= 1_000_000.0:
		return "%.2e" % n
	if absf(n) >= 1000.0:
		return "%.2f" % n
	return str(snappedf(n, 0.01))
