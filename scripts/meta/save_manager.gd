extends Node
## SaveManager — 存档管理器（Autoload 单例）
## 负责局外成长数据的持久化读写。

const SAVE_PATH := "user://save_data.json"

var progression: MetaProgression = null


func _ready() -> void:
	progression = MetaProgression.new()
	load_data()


# ============================================================
# 存档读写
# ============================================================

## 保存数据到文件
func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法写入存档: %s" % SAVE_PATH)
		return

	var json_string: String = JSON.stringify(progression.data, "\t")
	file.store_string(json_string)
	file.close()
	print("[SaveManager] 存档已保存")


## 从文件加载数据
func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] 无存档文件，使用默认数据")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] 无法读取存档: %s" % SAVE_PATH)
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error: int = json.parse(json_string)
	if error != OK:
		push_error("[SaveManager] 存档 JSON 解析失败: %s" % json.get_error_message())
		return

	var loaded: Variant = json.data
	if loaded is Dictionary:
		_merge_save_data(loaded)
		print("[SaveManager] 存档已加载 (v%d)" % progression.data.get("version", 0))
	else:
		push_error("[SaveManager] 存档格式错误")


## 重置存档
func reset_data() -> void:
	progression = MetaProgression.new()
	save_data()
	print("[SaveManager] 存档已重置")


# ============================================================
# 局内结算接口
# ============================================================

## 游戏结束时调用，将局内数据转入局外存档
func settle_game(victory: bool, game_stats: Dictionary) -> void:
	# 记录统计
	progression.record_game(
		victory,
		game_stats.get("kills", 0),
		game_stats.get("wave", 0),
		game_stats.get("play_time", 0.0),
	)

	# 转入局外货币
	var crystal: int = game_stats.get("crystal", 0)
	var badge: int = game_stats.get("badge", 0)
	if crystal > 0:
		progression.add_currency("crystal", crystal)
	if badge > 0:
		progression.add_currency("badge", badge)

	# 英雄获得局外经验（基于击杀数 + 波次数 × 5）
	var hero_id: String = game_stats.get("hero_id", "wolf_knight")
	var hero_exp: int = game_stats.get("kills", 0) + game_stats.get("wave", 0) * 5
	if victory:
		hero_exp = roundi(hero_exp * 1.5)
	progression.add_hero_exp(hero_id, hero_exp)

	print("[SaveManager] 结算完成 — crystal:%d badge:%d hero_exp:%d" % [crystal, badge, hero_exp])
	save_data()


# ============================================================
# 局外加成查询
# ============================================================

## 获取英雄局外属性加成
func get_hero_bonus(hero_id: String) -> Dictionary:
	return progression.get_hero_stat_bonus(hero_id)


## 获取建筑研究等级
func get_research_level(building_type: String) -> int:
	return progression.get_research_level(building_type)


# ============================================================
# 内部工具
# ============================================================

## 合并加载的数据到当前 progression（向前兼容）
func _merge_save_data(loaded: Dictionary) -> void:
	var defaults: Dictionary = MetaProgression.get_default_data()

	# 逐个顶级 key 合并，缺失的用默认值补充
	for key: String in defaults:
		if not loaded.has(key):
			loaded[key] = defaults[key]
		elif defaults[key] is Dictionary and loaded[key] is Dictionary:
			# 二级合并
			for sub_key: String in defaults[key]:
				if not loaded[key].has(sub_key):
					loaded[key][sub_key] = defaults[key][sub_key]

	progression.data = loaded
