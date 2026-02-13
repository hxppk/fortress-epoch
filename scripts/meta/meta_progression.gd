class_name MetaProgression
extends RefCounted
## MetaProgression — 局外成长数据结构
## 定义存档格式、默认值、数据访问接口。

const SAVE_VERSION: int = 1

## 英雄升级经验阈值（Lv1→Lv2 需 50 exp, Lv2→Lv3 需 120, ...）
const HERO_EXP_THRESHOLDS: Array = [0, 50, 120, 250, 500]

## 研究升级费用（水晶）：[Lv0→1, Lv1→2, Lv2→3]
const RESEARCH_COSTS: Dictionary = {
	"arrow_tower": [20, 60, 150],
	"gold_mine": [20, 60, 150],
	"barracks": [20, 60, 150],
}

## 研究效果：每级加成百分比
const RESEARCH_EFFECTS: Dictionary = {
	"arrow_tower": [0.10, 0.20, 0.35],
	"gold_mine": [0.15, 0.30, 0.50],
	"barracks": [0.10, 0.20, 0.35],
}

## 存档数据
var data: Dictionary = {}


func _init() -> void:
	data = get_default_data()


## 返回默认存档数据
static func get_default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"stats": {
			"total_games": 0,
			"total_wins": 0,
			"total_kills": 0,
			"best_wave": 0,
			"total_play_time": 0.0,
		},
		"currencies": {
			"crystal": 0,
			"badge": 0,
		},
		"hero_progress": {
			"wolf_knight": {"level": 1, "exp": 0},
			"meteor_mage": {"level": 1, "exp": 0},
		},
		"research": {
			"arrow_tower": 0,
			"gold_mine": 0,
			"barracks": 0,
		},
		"unlocks": {
			"cards": [],
			"heroes": ["wolf_knight"],
			"buildings": ["arrow_tower", "gold_mine", "barracks"],
		},
	}


# ============================================================
# 统计数据
# ============================================================

func record_game(victory: bool, kills: int, wave: int, play_time: float) -> void:
	data["stats"]["total_games"] += 1
	if victory:
		data["stats"]["total_wins"] += 1
	data["stats"]["total_kills"] += kills
	data["stats"]["best_wave"] = maxi(data["stats"]["best_wave"], wave)
	data["stats"]["total_play_time"] += play_time


# ============================================================
# 货币
# ============================================================

func add_currency(type: String, amount: int) -> void:
	if data["currencies"].has(type):
		data["currencies"][type] += amount


func spend_currency(type: String, amount: int) -> bool:
	if not data["currencies"].has(type):
		return false
	if data["currencies"][type] < amount:
		return false
	data["currencies"][type] -= amount
	return true


func get_currency(type: String) -> int:
	return data["currencies"].get(type, 0)


# ============================================================
# 英雄进度
# ============================================================

func add_hero_exp(hero_id: String, amount: int) -> void:
	if not data["hero_progress"].has(hero_id):
		data["hero_progress"][hero_id] = {"level": 1, "exp": 0}

	var progress: Dictionary = data["hero_progress"][hero_id]
	progress["exp"] += amount

	# 自动升级
	while progress["level"] < HERO_EXP_THRESHOLDS.size():
		var threshold: int = HERO_EXP_THRESHOLDS[progress["level"]]
		if progress["exp"] >= threshold:
			progress["level"] += 1
			print("[MetaProgression] 英雄 %s 升级到 Lv.%d" % [hero_id, progress["level"]])
		else:
			break


func get_hero_level(hero_id: String) -> int:
	if data["hero_progress"].has(hero_id):
		return data["hero_progress"][hero_id].get("level", 1)
	return 1


# ============================================================
# 研究
# ============================================================

func get_research_level(building_type: String) -> int:
	return data["research"].get(building_type, 0)


## 升级研究，返回是否成功
func upgrade_research(building_type: String) -> bool:
	if not data["research"].has(building_type):
		return false
	var current_level: int = data["research"][building_type]
	if current_level >= 3:
		return false
	var costs: Array = RESEARCH_COSTS.get(building_type, [])
	if current_level >= costs.size():
		return false
	var cost: int = costs[current_level]
	if not spend_currency("crystal", cost):
		return false
	data["research"][building_type] = current_level + 1
	print("[MetaProgression] 研究升级: %s -> Lv.%d" % [building_type, current_level + 1])
	return true


## 获取研究加成百分比
func get_research_bonus(building_type: String) -> float:
	var level: int = get_research_level(building_type)
	if level <= 0:
		return 0.0
	var effects: Array = RESEARCH_EFFECTS.get(building_type, [])
	if level - 1 < effects.size():
		return effects[level - 1]
	return 0.0


## 获取研究升级费用（-1 = 已满级）
func get_research_cost(building_type: String) -> int:
	var current_level: int = get_research_level(building_type)
	if current_level >= 3:
		return -1
	var costs: Array = RESEARCH_COSTS.get(building_type, [])
	if current_level < costs.size():
		return costs[current_level]
	return -1


# ============================================================
# 局外加成计算（预留，当前返回 0）
# ============================================================

func get_hero_stat_bonus(hero_id: String) -> Dictionary:
	var level: int = get_hero_level(hero_id)
	# 每级 +2% 基础属性（从 Lv2 开始有加成）
	var bonus_pct: float = maxf((level - 1) * 0.02, 0.0)
	return {
		"attack_pct": bonus_pct,
		"hp_pct": bonus_pct,
		"defense_pct": bonus_pct,
	}
