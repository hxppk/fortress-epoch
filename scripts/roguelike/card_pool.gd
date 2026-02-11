class_name CardPool
extends RefCounted
## Manages the full card pool, weighted-rarity draws, and pick-three logic
## for the Roguelike card system.

## Every card loaded from cards.json.
var all_cards: Array[CardData] = []

## Cards grouped by rarity key -> Array[CardData].
var cards_by_rarity: Dictionary = {}

## Cards grouped by category key -> Array[CardData].
var cards_by_category: Dictionary = {}

## Cards the player has already chosen this run (to avoid duplicates).
var selected_cards: Array[CardData] = []

## Base rarity weights (before wave-progress adjustment).
var rarity_weights: Dictionary = {
	"common": 0.60,
	"uncommon": 0.25,
	"epic": 0.12,
	"legendary": 0.03,
}

# ── Initialisation ──────────────────────────────────────────────────────────

## Load cards.json and build all lookup tables.
func initialize() -> void:
	_load_cards_from_json()


## Parse res://data/cards.json and populate all_cards, cards_by_rarity,
## cards_by_category.
func _load_cards_from_json() -> void:
	all_cards.clear()
	cards_by_rarity.clear()
	cards_by_category.clear()

	var file := FileAccess.open("res://data/cards.json", FileAccess.READ)
	if file == null:
		push_error("CardPool: Failed to open res://data/cards.json")
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("CardPool: JSON parse error – %s" % json.get_error_message())
		return

	var root: Dictionary = json.data
	if root.has("rarity_weights"):
		rarity_weights = root["rarity_weights"]

	var cards_array: Array = root.get("cards", [])
	for entry in cards_array:
		var card := CardData.from_dict(entry)
		all_cards.append(card)

		# By rarity
		if not cards_by_rarity.has(card.rarity):
			cards_by_rarity[card.rarity] = [] as Array[CardData]
		cards_by_rarity[card.rarity].append(card)

		# By category
		if not cards_by_category.has(card.category):
			cards_by_category[card.category] = [] as Array[CardData]
		cards_by_category[card.category].append(card)

# ── Drawing ─────────────────────────────────────────────────────────────────

## Draw three cards for the player to pick from.
## Guarantees: different categories when possible, no duplicate cards,
## respects hero_filter.
func draw_three(current_wave: int, total_waves: int, hero_id: String) -> Array[CardData]:
	var categories: Array[String] = ["skill", "attribute", "resource"]
	categories.shuffle()

	var result: Array[CardData] = []

	for i in 3:
		var rarity_roll := _roll_rarity(current_wave, total_waves)
		var card := _pick_card_by_rarity(rarity_roll, categories[i], hero_id, result)

		# Fallback 1 – drop the category hint
		if card == null:
			card = _pick_card_by_rarity(rarity_roll, "", hero_id, result)

		# Fallback 2 – pick any available card regardless of rarity
		if card == null:
			card = _pick_any_available(hero_id, result)

		if card != null:
			result.append(card)

	return result


## Roll a rarity string using wave-progress-adjusted weights.
func _roll_rarity(current_wave: int, total_waves: int) -> String:
	var progress := 0.0
	if total_waves > 0:
		progress = clampf(float(current_wave) / float(total_waves), 0.0, 1.0)

	# Legendary probability scales with progress
	var legendary_weight := lerpf(0.015, 0.045, progress)
	# Remaining budget for the other three tiers
	var remaining := 1.0 - legendary_weight

	# Derive base ratios (excluding legendary) from the original weights
	var base_common: float = rarity_weights.get("common", 0.60)
	var base_uncommon: float = rarity_weights.get("uncommon", 0.25)
	var base_epic: float = rarity_weights.get("epic", 0.12)
	var base_sum := base_common + base_uncommon + base_epic
	if base_sum == 0.0:
		base_sum = 1.0

	var w_common := remaining * (base_common / base_sum)
	var w_uncommon := remaining * (base_uncommon / base_sum)
	var w_epic := remaining * (base_epic / base_sum)

	var roll := randf()
	if roll < legendary_weight:
		return "legendary"
	roll -= legendary_weight
	if roll < w_epic:
		return "epic"
	roll -= w_epic
	if roll < w_uncommon:
		return "uncommon"
	return "common"


## Try to pick a single card that matches the requested rarity, category hint,
## and hero filter while avoiding cards already in `exclude` or `selected_cards`.
## Returns null when nothing qualifies.
func _pick_card_by_rarity(rarity: String, category_hint: String, hero_id: String, exclude: Array) -> CardData:
	var candidates: Array[CardData] = []

	# Build the candidate list
	var source: Array = []
	if category_hint != "" and cards_by_category.has(category_hint):
		source = cards_by_category[category_hint]
	elif cards_by_rarity.has(rarity):
		source = cards_by_rarity[rarity]
	else:
		source = all_cards

	for card in source:
		if card.rarity != rarity:
			continue
		if not card.matches_hero(hero_id):
			continue
		if _is_excluded(card, exclude):
			continue
		candidates.append(card)

	# If no exact match but we had a category hint, try the full rarity pool
	if candidates.is_empty() and category_hint != "":
		if cards_by_rarity.has(rarity):
			for card in cards_by_rarity[rarity]:
				if not card.matches_hero(hero_id):
					continue
				if _is_excluded(card, exclude):
					continue
				candidates.append(card)

	if candidates.is_empty():
		return null

	return candidates[randi() % candidates.size()]


## Last-resort: pick any card that the hero can use and that is not excluded.
func _pick_any_available(hero_id: String, exclude: Array) -> CardData:
	var candidates: Array[CardData] = []
	for card in all_cards:
		if not card.matches_hero(hero_id):
			continue
		if _is_excluded(card, exclude):
			continue
		candidates.append(card)

	if candidates.is_empty():
		return null

	return candidates[randi() % candidates.size()]


## Check whether a card should be excluded (already in this draw or already
## selected this run).
func _is_excluded(card: CardData, exclude: Array) -> bool:
	for c in exclude:
		if c != null and c.id == card.id:
			return true
	for c in selected_cards:
		if c.id == card.id:
			return true
	return false

# ── Selection tracking ──────────────────────────────────────────────────────

## Record that the player chose this card (prevents it from appearing again).
func record_selection(card: CardData) -> void:
	selected_cards.append(card)


## Return every card the player has selected so far this run.
func get_selected_cards() -> Array[CardData]:
	return selected_cards


## Reset pool state for a fresh run.
func reset() -> void:
	selected_cards.clear()
