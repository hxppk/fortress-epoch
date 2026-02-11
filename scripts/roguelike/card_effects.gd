class_name CardEffects
extends Node
## CardEffects -- 将卡牌效果应用到英雄 / 技能 / 资源系统
## 根据卡牌类别（attribute / skill / resource）分发到对应处理器。

# ============================================================
# 应用入口
# ============================================================

## 根据卡牌类型分发效果。
## card_data 可以是 CardData 实例（取 .effects / .category）也可以是原始 Dictionary。
## hero 必须拥有 StatsComponent 子节点。
func apply_card(card_data: Variant, hero: Node) -> void:
	var category: String = ""
	var effects: Array = []
	var card_id: String = ""

	if card_data is CardData:
		var cd: CardData = card_data as CardData
		category = cd.category
		effects = cd.effects
		card_id = cd.id
	elif card_data is Dictionary:
		category = card_data.get("category", "")
		effects = card_data.get("effects", [])
		card_id = card_data.get("id", "")
	else:
		push_warning("[CardEffects] apply_card: 不支持的 card_data 类型")
		return

	if effects.is_empty():
		push_warning("[CardEffects] 卡牌 %s 没有效果数据" % card_id)
		return

	match category:
		"attribute":
			_apply_attribute_card(effects, hero, card_id)
		"skill":
			_apply_skill_card(effects, hero, card_id)
		"resource":
			_apply_resource_card(effects, card_id)
		_:
			push_warning("[CardEffects] 未知卡牌类别: %s" % category)

# ============================================================
# 属性卡
# ============================================================

## 属性卡：通过 StatsComponent.add_modifier() 修改英雄属性。
func _apply_attribute_card(effects: Array, hero: Node, card_id: String) -> void:
	var stats: StatsComponent = _get_stats(hero)
	if stats == null:
		push_warning("[CardEffects] 英雄缺少 StatsComponent，无法应用属性卡")
		return

	var card_source: String = "card_" + card_id

	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")
		var value: float = float(effect.get("value", 0.0))

		match effect_type:
			"attack":
				stats.add_modifier("attack", card_source, value)
				print("[CardEffects] 攻击力 +%s (source: %s)" % [str(value), card_source])

			"max_hp":
				stats.add_modifier("hp", card_source, value)
				# 加上限后同步回复等量生命值
				stats.current_hp = minf(stats.current_hp + value, stats.max_hp)
				stats.health_changed.emit(stats.current_hp, stats.max_hp)
				print("[CardEffects] 最大生命值 +%s (source: %s)" % [str(value), card_source])

			"attack_speed":
				# 百分比效果：乘以当前基础攻速
				var base_as: float = stats.get_stat("attack_speed")
				var bonus: float = value * base_as
				stats.add_modifier("attack_speed", card_source, bonus)
				print("[CardEffects] 攻击速度 +%.1f%% (+%.2f) (source: %s)" % [value * 100.0, bonus, card_source])

			"crit_rate":
				stats.add_modifier("crit_rate", card_source, value)
				print("[CardEffects] 暴击率 +%.1f%% (source: %s)" % [value * 100.0, card_source])

			"defense":
				stats.add_modifier("defense", card_source, value)
				print("[CardEffects] 防御力 +%s (source: %s)" % [str(value), card_source])

			"speed":
				# 百分比效果：乘以当前基础移速
				var base_spd: float = stats.get_stat("speed")
				var bonus: float = value * base_spd
				stats.add_modifier("speed", card_source, bonus)
				print("[CardEffects] 移动速度 +%.1f%% (+%.2f) (source: %s)" % [value * 100.0, bonus, card_source])

			_:
				push_warning("[CardEffects] 未知属性效果类型: %s" % effect_type)

# ============================================================
# 技能卡
# ============================================================

## 技能卡：通过 SkillSystem 修改技能参数。
func _apply_skill_card(effects: Array, hero: Node, card_id: String) -> void:
	var skill_sys: SkillSystem = _get_skill_system(hero)
	if skill_sys == null:
		push_warning("[CardEffects] 英雄缺少 SkillSystem，无法应用技能卡")
		return

	var card_source: String = "card_" + card_id

	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"skill_damage":
				# 全局技能伤害倍率加成（对所有技能生效）
				var value: float = float(effect.get("value", 0.0))
				_apply_global_skill_modifier(skill_sys, "damage_multiplier", card_source, value)
				print("[CardEffects] 全局技能伤害 +%.0f%% (source: %s)" % [value * 100.0, card_source])

			"skill_cd":
				# 全局技能冷却修改（负值=缩减，对所有技能的 cooldown_total 乘法修改）
				var value: float = float(effect.get("value", 0.0))
				_apply_global_cd_modifier(skill_sys, card_source, value)
				print("[CardEffects] 全局技能冷却 %+.0f%% (source: %s)" % [value * 100.0, card_source])

			"skill_range":
				# 全局技能范围加成
				var value: float = float(effect.get("value", 0.0))
				_apply_global_skill_modifier(skill_sys, "range_multiplier", card_source, value)
				print("[CardEffects] 全局技能范围 +%.0f%% (source: %s)" % [value * 100.0, card_source])

			"skill_specific":
				# 针对特定技能的修改
				_apply_specific_skill_modifier(skill_sys, effect, card_source)

			_:
				push_warning("[CardEffects] 未知技能效果类型: %s" % effect_type)


## 对 SkillSystem 中所有技能添加全局修改器。
## modifier_key: "damage_multiplier" | "range_multiplier"
func _apply_global_skill_modifier(skill_sys: SkillSystem, modifier_key: String, source: String, value: float) -> void:
	# 在 SkillSystem 上使用 meta 存储卡牌修改器列表
	var meta_key: String = "card_modifiers_" + modifier_key
	var mod_list: Array = []
	if skill_sys.has_meta(meta_key):
		mod_list = skill_sys.get_meta(meta_key)
	mod_list.append({"source": source, "value": value})
	skill_sys.set_meta(meta_key, mod_list)


## 对 SkillSystem 中所有技能的冷却时间进行百分比修改。
## value 为负值表示缩减（例如 -0.20 = 缩减 20%）。
func _apply_global_cd_modifier(skill_sys: SkillSystem, source: String, value: float) -> void:
	# 保存冷却修改器到 meta
	var meta_key: String = "card_modifiers_cd"
	var mod_list: Array = []
	if skill_sys.has_meta(meta_key):
		mod_list = skill_sys.get_meta(meta_key)
	mod_list.append({"source": source, "value": value})
	skill_sys.set_meta(meta_key, mod_list)

	# 直接修改每个技能的 cooldown_total
	for skill_id: String in skill_sys.skills:
		var entry: Dictionary = skill_sys.skills[skill_id]
		var original_cd: float = entry.get("cooldown_total", 10.0)
		# 计算新冷却 = 原始 * (1 + value)，value 为负则缩减
		var new_cd: float = maxf(original_cd * (1.0 + value), 0.5)  # 最低 0.5 秒
		entry["cooldown_total"] = new_cd
		print("[CardEffects] 技能 %s 冷却: %.1f -> %.1f" % [skill_id, original_cd, new_cd])


## 针对特定 skill_id 的修改（伤害加成、减速延长、持续时间等）。
func _apply_specific_skill_modifier(skill_sys: SkillSystem, effect: Dictionary, source: String) -> void:
	var skill_id: String = effect.get("skill_id", "")
	if skill_id == "":
		push_warning("[CardEffects] skill_specific 效果缺少 skill_id")
		return

	# 在目标技能上存储修改器
	var meta_key: String = "card_specific_" + skill_id
	var mod_list: Array = []
	if skill_sys.has_meta(meta_key):
		mod_list = skill_sys.get_meta(meta_key)

	# 收集所有非 type/skill_id 的键值作为修改参数
	var mod_entry: Dictionary = {"source": source}
	for key: String in effect:
		if key == "type" or key == "skill_id":
			continue
		mod_entry[key] = effect[key]

	mod_list.append(mod_entry)
	skill_sys.set_meta(meta_key, mod_list)

	# 打印修改详情
	var desc_parts: Array = []
	for key: String in mod_entry:
		if key == "source":
			continue
		desc_parts.append("%s=%s" % [key, str(mod_entry[key])])
	print("[CardEffects] 技能 %s 特殊修改: %s (source: %s)" % [skill_id, ", ".join(desc_parts), source])

# ============================================================
# 资源卡
# ============================================================

## 资源卡：修改 GameManager 上的资源倍率。
func _apply_resource_card(effects: Array, card_id: String) -> void:
	var gm: Node = _get_game_manager()
	if gm == null:
		push_warning("[CardEffects] 找不到 GameManager，无法应用资源卡")
		return

	var card_source: String = "card_" + card_id

	# 确保 GameManager 上有资源修改器字典（通过 meta 存储）
	var resource_modifiers: Dictionary = {}
	if gm.has_meta("resource_modifiers"):
		resource_modifiers = gm.get_meta("resource_modifiers")

	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")
		var value: float = float(effect.get("value", 0.0))

		match effect_type:
			"kill_gold":
				# 增加击杀金币加成百分比
				var current_bonus: float = resource_modifiers.get("kill_gold_bonus", 0.0)
				resource_modifiers["kill_gold_bonus"] = current_bonus + value
				print("[CardEffects] 击杀金币加成 +%.0f%% (总计: %.0f%%)" % [value * 100.0, (current_bonus + value) * 100.0])

			"exp_gain":
				# 增加经验获取加成百分比
				var current_bonus: float = resource_modifiers.get("exp_gain_bonus", 0.0)
				resource_modifiers["exp_gain_bonus"] = current_bonus + value
				print("[CardEffects] 经验获取加成 +%.0f%% (总计: %.0f%%)" % [value * 100.0, (current_bonus + value) * 100.0])

			"double_loot_chance":
				# 设置双倍掉落概率（叠加）
				var current_chance: float = resource_modifiers.get("double_loot_chance", 0.0)
				resource_modifiers["double_loot_chance"] = minf(current_chance + value, 1.0)
				print("[CardEffects] 双倍掉落概率 +%.0f%% (总计: %.0f%%)" % [value * 100.0, minf(current_chance + value, 1.0) * 100.0])

			"passive_gold":
				# 启动被动金币产出 Timer
				var interval: float = float(effect.get("interval", 10.0))
				_start_passive_gold_timer(gm, value, interval, card_source)
				print("[CardEffects] 启动被动金币: 每 %.0f 秒获得 %d 金币 (source: %s)" % [interval, int(value), card_source])

			"crystal_drop_rate":
				# 增加水晶掉落率
				var current_rate: float = resource_modifiers.get("crystal_drop_bonus", 0.0)
				resource_modifiers["crystal_drop_bonus"] = current_rate + value
				print("[CardEffects] 水晶掉落率 +%.0f%% (总计: %.0f%%)" % [value * 100.0, (current_rate + value) * 100.0])

			_:
				push_warning("[CardEffects] 未知资源效果类型: %s" % effect_type)

	gm.set_meta("resource_modifiers", resource_modifiers)


## 创建被动金币产出 Timer 并挂载到 GameManager 上。
func _start_passive_gold_timer(gm: Node, gold_amount: float, interval: float, source: String) -> void:
	var timer := Timer.new()
	timer.name = "PassiveGoldTimer_" + source
	timer.wait_time = interval
	timer.one_shot = false
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	gm.add_child(timer)
	timer.start()

	var gold_per_tick: int = maxi(int(gold_amount), 1)

	timer.timeout.connect(
		func() -> void:
			if gm and gm.has_method("add_resource"):
				gm.add_resource("gold", gold_per_tick)
				print("[CardEffects] 被动产出 %d 金币 (source: %s)" % [gold_per_tick, source])
	)

# ============================================================
# 查询接口（供外部系统使用）
# ============================================================

## 获取全局技能伤害倍率（1.0 + 所有卡牌叠加值）
static func get_skill_damage_multiplier(skill_sys: SkillSystem) -> float:
	var total: float = 1.0
	var meta_key: String = "card_modifiers_damage_multiplier"
	if skill_sys and skill_sys.has_meta(meta_key):
		var mod_list: Array = skill_sys.get_meta(meta_key)
		for mod: Dictionary in mod_list:
			total += mod.get("value", 0.0)
	return total


## 获取全局技能范围倍率（1.0 + 所有卡牌叠加值）
static func get_skill_range_multiplier(skill_sys: SkillSystem) -> float:
	var total: float = 1.0
	var meta_key: String = "card_modifiers_range_multiplier"
	if skill_sys and skill_sys.has_meta(meta_key):
		var mod_list: Array = skill_sys.get_meta(meta_key)
		for mod: Dictionary in mod_list:
			total += mod.get("value", 0.0)
	return total


## 获取特定技能的卡牌修改列表
static func get_specific_skill_modifiers(skill_sys: SkillSystem, skill_id: String) -> Array:
	var meta_key: String = "card_specific_" + skill_id
	if skill_sys and skill_sys.has_meta(meta_key):
		return skill_sys.get_meta(meta_key)
	return []


## 获取资源修改器值（从 GameManager meta 读取）
static func get_resource_modifier(modifier_name: String) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var gm: Node = tree.root.get_node_or_null("GameManager") if tree else null
	if gm == null:
		return 0.0
	if not gm.has_meta("resource_modifiers"):
		return 0.0
	var mods: Dictionary = gm.get_meta("resource_modifiers")
	return float(mods.get(modifier_name, 0.0))

# ============================================================
# 内部工具
# ============================================================

## 获取英雄的 StatsComponent
func _get_stats(hero: Node) -> StatsComponent:
	if hero == null:
		return null
	if hero.has_node("StatsComponent"):
		return hero.get_node("StatsComponent") as StatsComponent
	return null


## 获取英雄的 SkillSystem（遍历子节点查找）
func _get_skill_system(hero: Node) -> SkillSystem:
	if hero == null:
		return null
	for child: Node in hero.get_children():
		if child is SkillSystem:
			return child as SkillSystem
	return null


## 获取 GameManager 单例
func _get_game_manager() -> Node:
	return GameManager
