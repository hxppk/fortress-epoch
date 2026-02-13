extends SceneTree
## 数值验证脚本 — 从 JSON 数据文件读取并计算平衡报告
## 用法: godot --headless --script res://scripts/tests/balance_check.gd

func _init() -> void:
	print("=" .repeat(60))
	print("  数值平衡检查 v0.2.1")
	print("=" .repeat(60))

	var buildings: Dictionary = _load_json("res://data/buildings.json")
	var enemies: Dictionary = _load_json("res://data/enemies.json")
	var heroes: Dictionary = _load_json("res://data/heroes.json")
	var waves: Dictionary = _load_json("res://data/waves.json")

	_check_building_costs(buildings)
	_check_npc_dps(buildings)
	_check_enemy_stats(enemies)
	_check_hero_stats(heroes)
	_check_evil_castle_hp(buildings)
	_check_economy(buildings, waves, enemies)

	print("\n" + "=" .repeat(60))
	print("  数值检查完成")
	print("=" .repeat(60))
	quit()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[SKIP] 无法加载: %s" % path)
		return {}

	var json := JSON.new()
	var error: int = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		print("[ERROR] JSON 解析失败: %s" % path)
		return {}

	return json.data if json.data is Dictionary else {}


func _check_building_costs(data: Dictionary) -> void:
	print("\n--- 建筑造价 ---")
	var buildings_arr: Array = data.get("buildings", [])
	for b: Dictionary in buildings_arr:
		var name: String = b.get("name", b.get("id", "?"))
		var levels: Array = b.get("levels", [])
		for lv: Dictionary in levels:
			var cost: Dictionary = lv.get("upgrade_cost", {})
			print("  %s Lv%d — 造价: %s" % [name, lv.get("level", 0), str(cost)])


func _check_npc_dps(data: Dictionary) -> void:
	print("\n--- NPC DPS 估算 ---")
	var buildings_arr: Array = data.get("buildings", [])
	for b: Dictionary in buildings_arr:
		var bid: String = b.get("id", "")
		var levels: Array = b.get("levels", [])
		for lv: Dictionary in levels:
			var level: int = lv.get("level", 1)
			var dps: float = _calc_npc_dps(bid, lv)
			if dps > 0:
				print("  %s NPC (基于 Lv%d 建筑) — DPS: %.1f" % [bid, level, dps])


func _calc_npc_dps(building_type: String, level_data: Dictionary) -> float:
	match building_type:
		"arrow_tower":
			var damage: float = float(level_data.get("damage", 16))
			var atk_interval: float = float(level_data.get("attack_speed", 1.0))
			var atk_speed: float = 1.0 / maxf(atk_interval, 0.1)
			return damage * atk_speed
		"barracks":
			var phys: float = float(level_data.get("phys_attack_bonus", 10))
			var attack: float = 15.0 + phys
			var atk_speed: float = 1.2
			return attack * atk_speed
		"gold_mine":
			var production: float = float(level_data.get("production", 5))
			var attack: float = 8.0 + production * 2.0
			var atk_speed: float = 0.8
			return attack * atk_speed
	return 0.0


func _check_evil_castle_hp(data: Dictionary) -> void:
	print("\n--- 邪恶城堡 HP 估算 ---")
	var buildings_arr: Array = data.get("buildings", [])

	# 计算各组合下的总 DPS 和对应城堡 HP
	# 场景：3 箭塔 + 0 兵营 + 0 金矿 (全 Lv1, Lv2, Lv3)
	var scenarios: Array = [
		{"name": "3×箭塔 Lv1", "configs": [{"type": "arrow_tower", "level": 1}]},
		{"name": "3×箭塔 Lv2", "configs": [{"type": "arrow_tower", "level": 2}]},
		{"name": "各1种 Lv1", "configs": [
			{"type": "arrow_tower", "level": 1},
			{"type": "barracks", "level": 1},
			{"type": "gold_mine", "level": 1},
		]},
		{"name": "各1种 Lv2", "configs": [
			{"type": "arrow_tower", "level": 2},
			{"type": "barracks", "level": 2},
			{"type": "gold_mine", "level": 2},
		]},
	]

	for scenario: Dictionary in scenarios:
		var total_dps: float = 0.0
		for config: Dictionary in scenario["configs"]:
			var lv_data: Dictionary = _find_level_data(buildings_arr, config["type"], config["level"])
			total_dps += _calc_npc_dps(config["type"], lv_data)

		var castle_hp: float = total_dps * 30.0 * 3.0
		print("  %s — 总DPS: %.1f → 城堡HP: %.0f" % [scenario["name"], total_dps, castle_hp])


func _find_level_data(buildings_arr: Array, building_id: String, level: int) -> Dictionary:
	for b: Dictionary in buildings_arr:
		if b.get("id", "") == building_id:
			for lv: Dictionary in b.get("levels", []):
				if lv.get("level", 0) == level:
					return lv
	return {}


func _check_enemy_stats(data: Dictionary) -> void:
	print("\n--- 敌人属性 ---")
	var enemies_arr: Array = data.get("enemies", [])
	for e: Dictionary in enemies_arr:
		var eid: String = e.get("id", "?")
		var hp: int = e.get("hp", 0)
		var attack: int = e.get("attack", 0)
		var speed: int = e.get("speed", 0)
		var reward: Dictionary = e.get("reward", {})
		print("  %s — HP:%d ATK:%d SPD:%d 奖励:%s" % [eid, hp, attack, speed, str(reward)])


func _check_hero_stats(data: Dictionary) -> void:
	print("\n--- 英雄属性 ---")
	var heroes_arr: Array = data.get("heroes", [])
	for h: Dictionary in heroes_arr:
		var hid: String = h.get("id", "?")
		var stats: Dictionary = h.get("base_stats", {})
		print("  %s — HP:%s ATK:%s DEF:%s SPD:%s" % [
			hid,
			str(stats.get("hp", "?")),
			str(stats.get("attack", "?")),
			str(stats.get("defense", "?")),
			str(stats.get("speed", "?")),
		])


func _check_economy(buildings: Dictionary, waves: Dictionary, enemies: Dictionary) -> void:
	print("\n--- 经济流转估算 ---")

	# 初始金币
	var gold: int = 100
	print("  初始金币: %d" % gold)

	# 建筑造价
	var buildings_arr: Array = buildings.get("buildings", [])
	for b: Dictionary in buildings_arr:
		var levels: Array = b.get("levels", [])
		if levels.size() > 0:
			var cost: Dictionary = levels[0].get("upgrade_cost", {})
			var g: int = cost.get("gold", 0)
			if g > 0:
				print("  %s Lv1 造价: %d 金" % [b.get("name", "?"), g])

	# 波次奖励估算
	var stages: Dictionary = waves.get("stages", {})
	for stage_id: String in stages:
		var stage: Dictionary = stages[stage_id]
		var wave_list: Array = stage.get("waves", [])
		var stage_gold: int = 0
		for w: Dictionary in wave_list:
			var reward: Dictionary = w.get("reward", {})
			stage_gold += reward.get("gold", 0)
		if stage_gold > 0:
			print("  %s 波次总金币奖励: %d" % [stage_id, stage_gold])
