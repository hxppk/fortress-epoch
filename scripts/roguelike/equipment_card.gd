class_name EquipmentCardHandler
extends RefCounted
## EquipmentCardHandler -- 装备卡处理器
## 管理英雄装备槽位、装备效果应用和被动效果注册。
## 装备数据存储在英雄节点的 meta 中。

## 每个英雄最多装备数量
const MAX_EQUIPMENT: int = 3

# ============================================================
# 装备应用
# ============================================================

## 将装备卡应用到英雄。成功返回 true，槽位已满或无效数据返回 false。
## card_data 可以是 CardData 实例或 Dictionary。
static func apply_equipment(card_data: Variant, hero: Node) -> bool:
	var card_id: String = ""
	var slot: String = ""
	var effects: Array = []
	var equipment_effect: Dictionary = {}

	if card_data is CardData:
		var cd: CardData = card_data as CardData
		card_id = cd.id
		slot = cd.slot
		effects = cd.effects
		equipment_effect = cd.equipment_effect
	elif card_data is Dictionary:
		card_id = card_data.get("id", "")
		slot = card_data.get("slot", "")
		effects = card_data.get("effects", [])
		equipment_effect = card_data.get("equipment_effect", {})
	else:
		push_warning("[EquipmentCardHandler] 不支持的 card_data 类型")
		return false

	# 检查装备槽位
	var equipped: Array = _get_equipped(hero)
	if equipped.size() >= _get_max_slots(hero):
		push_warning("[EquipmentCardHandler] 装备槽已满（%d/%d），无法装备 %s" % [
			equipped.size(), _get_max_slots(hero), card_id])
		return false

	# 检查同槽位是否已有装备（enhance 类型不占槽位，它们增强已有装备）
	if slot != "" and _is_enhance_card(card_id):
		# 增强卡：不占槽位，直接应用效果
		_apply_enhance_effects(card_id, effects, equipment_effect, hero)
		print("[EquipmentCardHandler] 装备增强卡 %s 已应用" % card_id)
		return true

	# 记录装备
	equipped.append({
		"id": card_id,
		"slot": slot,
		"effects": effects,
		"equipment_effect": equipment_effect,
	})
	hero.set_meta("equipment", equipped)

	# 应用装备属性效果
	_apply_equipment_effects(card_id, slot, effects, equipment_effect, hero)

	print("[EquipmentCardHandler] 英雄装备了 %s（槽位: %s, %d/%d）" % [
		card_id, slot, equipped.size(), _get_max_slots(hero)])
	return true


## 获取英雄当前装备列表
static func get_equipped(hero: Node) -> Array:
	return _get_equipped(hero)


## 检查英雄是否有指定槽位的装备
static func has_slot_equipped(hero: Node, slot: String) -> bool:
	var equipped: Array = _get_equipped(hero)
	for item: Dictionary in equipped:
		if item.get("slot", "") == slot:
			return true
	return false

# ============================================================
# 内部方法
# ============================================================

## 获取英雄已装备列表
static func _get_equipped(hero: Node) -> Array:
	if hero.has_meta("equipment"):
		return hero.get_meta("equipment")
	return []


## 获取英雄最大装备槽数（受铸造所等级影响）
static func _get_max_slots(hero: Node) -> int:
	# 默认上限为 MAX_EQUIPMENT，受铸造所等级解锁：
	# Lv1: 1 slot, Lv2: 2 slots, Lv3: 3 slots
	# 通过 GameManager meta 获取铸造所等级
	var forge_level: int = 0
	if Engine.has_singleton("GameManager"):
		var gm: Node = Engine.get_singleton("GameManager")
		if gm and gm.has_meta("tech_forge_level"):
			forge_level = gm.get_meta("tech_forge_level")
	elif is_instance_valid(GameManager):
		if GameManager.has_meta("tech_forge_level"):
			forge_level = GameManager.get_meta("tech_forge_level")

	# 铸造所等级决定可用槽位数
	return clampi(forge_level, 1, MAX_EQUIPMENT)


## 判断是否为增强型装备卡（武器淬炼、护甲强化）
static func _is_enhance_card(card_id: String) -> bool:
	return card_id in ["equip_enhance_weapon", "equip_enhance_armor"]


## 应用装备属性效果
static func _apply_equipment_effects(card_id: String, slot: String, effects: Array, equipment_effect: Dictionary, hero: Node) -> void:
	var source_name: String = "equip_%s" % card_id

	# 应用 effects 数组中的属性修改
	if hero.has_node("StatsComponent"):
		var stats: StatsComponent = hero.get_node("StatsComponent")
		for effect: Dictionary in effects:
			var effect_type: String = effect.get("type", "")
			var value: float = float(effect.get("value", 0.0))
			match effect_type:
				"speed":
					var base_spd: float = stats.get_stat("speed")
					var bonus: float = value * base_spd
					stats.add_modifier("speed", source_name, bonus)
					print("[EquipmentCardHandler] 移动速度 +%.0f%%" % [value * 100.0])
				"dodge":
					stats.add_modifier("dodge", source_name, value)
					print("[EquipmentCardHandler] 闪避率 +%.0f%%" % [value * 100.0])
				"defense":
					stats.add_modifier("defense", source_name, value)
					print("[EquipmentCardHandler] 防御力 +%s" % str(value))
				"damage_reduction":
					# 受伤减免百分比，存储在 meta 中
					var current: float = 0.0
					if hero.has_meta("damage_reduction"):
						current = hero.get_meta("damage_reduction")
					hero.set_meta("damage_reduction", current + value)
					print("[EquipmentCardHandler] 受伤减免 +%.0f%%" % [value * 100.0])

	# 注册被动效果
	var passive: String = equipment_effect.get("passive", "")
	if passive != "":
		_register_passive(passive, equipment_effect, hero, source_name)


## 应用增强型装备卡效果（武器淬炼/护甲强化）
static func _apply_enhance_effects(card_id: String, effects: Array, equipment_effect: Dictionary, hero: Node) -> void:
	var source_name: String = "equip_%s" % card_id

	match card_id:
		"equip_enhance_weapon":
			# 武器淬炼：已装备武器效果+50%
			_enhance_slot_effects(hero, "weapon", 0.5)
		"equip_enhance_armor":
			# 护甲强化：已装备护甲效果+50%，受到伤害-10%
			_enhance_slot_effects(hero, "armor", 0.5)
			# 额外：受伤-10%
			for effect: Dictionary in effects:
				if effect.get("type", "") == "damage_reduction":
					var value: float = float(effect.get("value", 0.0))
					var current: float = 0.0
					if hero.has_meta("damage_reduction"):
						current = hero.get_meta("damage_reduction")
					hero.set_meta("damage_reduction", current + value)
					print("[EquipmentCardHandler] 护甲强化：受伤减免 +%.0f%%" % [value * 100.0])


## 增强指定槽位的装备效果
static func _enhance_slot_effects(hero: Node, target_slot: String, enhance_ratio: float) -> void:
	var equipped: Array = _get_equipped(hero)
	for item: Dictionary in equipped:
		if item.get("slot", "") != target_slot:
			continue

		var item_id: String = item.get("id", "")
		var eq_effect: Dictionary = item.get("equipment_effect", {})
		var passive: String = eq_effect.get("passive", "")

		# 增强被动效果数值
		match passive:
			"burn_on_hit":
				if hero.has_meta("on_hit_burn"):
					var burn_data: Dictionary = hero.get_meta("on_hit_burn")
					burn_data["damage"] = burn_data.get("damage", 0) * (1.0 + enhance_ratio)
					burn_data["chance"] = minf(burn_data.get("chance", 0.0) * (1.0 + enhance_ratio), 1.0)
					hero.set_meta("on_hit_burn", burn_data)
					print("[EquipmentCardHandler] 武器淬炼强化 %s 灼烧效果 +%.0f%%" % [item_id, enhance_ratio * 100.0])
			"freeze_on_hit":
				if hero.has_meta("on_hit_freeze"):
					var freeze_data: Dictionary = hero.get_meta("on_hit_freeze")
					freeze_data["duration"] = freeze_data.get("duration", 0.0) * (1.0 + enhance_ratio)
					freeze_data["chance"] = minf(freeze_data.get("chance", 0.0) * (1.0 + enhance_ratio), 1.0)
					hero.set_meta("on_hit_freeze", freeze_data)
					print("[EquipmentCardHandler] 护甲强化 %s 冰冻效果 +%.0f%%" % [item_id, enhance_ratio * 100.0])


## 注册装备被动效果到英雄 meta
static func _register_passive(passive_id: String, effect_config: Dictionary, hero: Node, source: String) -> void:
	match passive_id:
		"burn_on_hit":
			# 普攻命中时15%概率灼烧
			hero.set_meta("on_hit_burn", {
				"damage": effect_config.get("burn_damage", 3),
				"duration": effect_config.get("burn_duration", 3.0),
				"chance": effect_config.get("burn_chance", 0.15),
				"source": source,
			})
			print("[EquipmentCardHandler] 注册被动: 灼烧 (伤害=%d, 持续=%.1fs, 概率=%.0f%%)" % [
				effect_config.get("burn_damage", 3),
				effect_config.get("burn_duration", 3.0),
				effect_config.get("burn_chance", 0.15) * 100.0,
			])

		"freeze_on_hit":
			# 受击时20%概率冻结攻击者
			hero.set_meta("on_hit_freeze", {
				"duration": effect_config.get("freeze_duration", 1.5),
				"chance": effect_config.get("freeze_chance", 0.20),
				"source": source,
			})
			print("[EquipmentCardHandler] 注册被动: 冰冻 (持续=%.1fs, 概率=%.0f%%)" % [
				effect_config.get("freeze_duration", 1.5),
				effect_config.get("freeze_chance", 0.20) * 100.0,
			])

		_:
			push_warning("[EquipmentCardHandler] 未知被动效果: %s" % passive_id)
