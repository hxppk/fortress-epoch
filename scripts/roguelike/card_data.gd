class_name CardData
extends RefCounted
## Single card data wrapper for the Roguelike card system.

## Card ID, e.g. "skill_damage_boost"
var id: String = ""
## Display name, e.g. "技能强化"
var card_name: String = ""
## Category: "skill" | "attribute" | "resource"
var category: String = ""
## Rarity: "common" | "uncommon" | "epic" | "legendary"
var rarity: String = ""
## Icon tint key: "red" | "blue" | "gold"
var icon_color: String = ""
## Which building unlocks this card: "safety" | "military" | "economy"
var source_building: String = ""
## Human-readable effect description
var description: String = ""
## Array of effect dictionaries, each with at least a "type" key
var effects: Array = []
## Hero ID filter. Empty string means the card is universal.
var hero_filter: String = ""
## Equipment slot: "weapon" | "armor" | "accessory" (only for equipment cards)
var slot: String = ""
## Equipment effect configuration dictionary (only for equipment cards)
var equipment_effect: Dictionary = {}


## Factory: build a CardData instance from a raw dictionary (parsed from JSON).
static func from_dict(data: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = data.get("id", "")
	card.card_name = data.get("name", "")
	card.category = data.get("category", "")
	card.rarity = data.get("rarity", "common")
	card.icon_color = data.get("icon_color", "")
	card.source_building = data.get("source_building", "")
	card.description = data.get("description", "")
	card.effects = data.get("effects", [])
	card.hero_filter = data.get("hero_filter", "")
	card.slot = data.get("slot", "")
	card.equipment_effect = data.get("equipment_effect", {})
	return card


## Return the display colour that matches this card's rarity tier.
func get_rarity_color() -> Color:
	match rarity:
		"common":
			return Color.WHITE
		"uncommon":
			return Color(0.29, 0.56, 0.85)
		"epic":
			return Color(0.61, 0.35, 0.71)
		"legendary":
			return Color(0.95, 0.77, 0.06)
		_:
			return Color.WHITE


## Return the Chinese label for this card's category.
func get_category_label() -> String:
	match category:
		"skill":
			return "技能卡"
		"attribute":
			return "属性卡"
		"resource":
			return "资源卡"
		"equipment":
			return "装备卡"
		_:
			return "未知"


## Check whether this card is usable by the given hero.
## A card matches if it has no hero_filter (universal) or if the filter equals hero_id.
func matches_hero(hero_id: String) -> bool:
	if hero_filter == "":
		return true
	return hero_filter == hero_id
