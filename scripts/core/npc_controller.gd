class_name NPCController
extends Node
## NPCController -- NPC 生成与管理
## 从 GameSession 抽取，处理建筑满 3 触发 NPC 自动生成。

const NPCScene := preload("res://scenes/entities/npcs/npc_base.tscn")

# ============================================================
# 信号
# ============================================================

signal npc_spawned(npc: NPCUnit, npc_type: String, building_type: String)

# ============================================================
# 属性
# ============================================================

## NPC 实体的父节点
var heroes_parent: Node2D = null

## 场景树引用（用于 get_nodes_in_group）
var scene_tree: SceneTree = null

# ============================================================
# 公共接口
# ============================================================

## 初始化
func initialize(parent: Node2D, tree: SceneTree) -> void:
	heroes_parent = parent
	scene_tree = tree
	# 监听 BuildingManager 的 NPC 生成信号
	if BuildingManager.has_signal("npc_spawn_triggered"):
		BuildingManager.npc_spawn_triggered.connect(_on_npc_spawn_triggered)


## 根据建筑类型生成 NPC
func spawn_npc(building_type: String) -> void:
	var buildings_list: Array = BuildingManager.get_buildings_by_type(building_type)
	if buildings_list.is_empty():
		return

	# 每种 NPC 上限 1 个
	var expected_npc_type: String = _get_npc_type(building_type)

	if _npc_exists(expected_npc_type):
		print("[NPCController] NPC 已存在，跳过: %s" % expected_npc_type)
		return

	# 计算所有同类建筑的中心点
	var center := Vector2.ZERO
	for b: Node in buildings_list:
		center += b.global_position
	center /= float(buildings_list.size())

	var npc: NPCUnit = NPCScene.instantiate() as NPCUnit
	heroes_parent.add_child(npc)

	# 获取最高等级建筑的数据
	var best_level_data: Dictionary = _get_best_level_data(buildings_list)

	# 构建 NPC 属性
	var npc_stats: Dictionary = {}
	var attack_range: float = 40.0
	var attack_pattern: String = "single_target"

	match building_type:
		"arrow_tower":
			var tower_dmg: float = float(best_level_data.get("damage", 16))
			var tower_range: float = float(best_level_data.get("range", 96))
			var tower_atk_interval: float = float(best_level_data.get("attack_speed", 1.0))
			npc_stats = {
				"hp": 60,
				"attack": tower_dmg,
				"defense": 2,
				"speed": 50,
				"attack_speed": 1.0 / maxf(tower_atk_interval, 0.1),
				"attack_range": tower_range,
				"crit_rate": 0.05,
			}
			attack_range = tower_range
		"barracks":
			var phys_bonus: float = float(best_level_data.get("phys_attack_bonus", 10))
			var hp_bonus: float = float(best_level_data.get("hp_bonus", 50))
			var armor_bonus: float = float(best_level_data.get("armor_bonus", 2))
			npc_stats = {
				"hp": 100 + hp_bonus,
				"attack": 15 + phys_bonus,
				"defense": 5 + armor_bonus,
				"speed": 60,
				"attack_speed": 1.2,
				"attack_range": 30,
				"crit_rate": 0.08,
			}
			attack_range = 30.0
		"gold_mine":
			var production: float = float(best_level_data.get("production", 5))
			npc_stats = {
				"hp": 60 + production * 4.0,
				"attack": 8 + production * 2.0,
				"defense": 3,
				"speed": 40,
				"attack_speed": 0.8,
				"attack_range": 25,
				"crit_rate": 0.03,
			}
			attack_range = 25.0

	npc.initialize(expected_npc_type, npc_stats, center, attack_range, attack_pattern)
	npc.add_to_group("heroes")

	npc_spawned.emit(npc, expected_npc_type, building_type)
	print("[NPCController] 自动生成 NPC: %s (建筑类型: %s)" % [expected_npc_type, building_type])


# ============================================================
# 内部回调
# ============================================================

func _on_npc_spawn_triggered(building_type: String) -> void:
	spawn_npc(building_type)


# ============================================================
# 辅助函数
# ============================================================

func _get_npc_type(building_type: String) -> String:
	match building_type:
		"arrow_tower": return "archer"
		"barracks": return "knight"
		"gold_mine": return "miner"
		_: return building_type


func _npc_exists(npc_type: String) -> bool:
	if scene_tree == null:
		return false
	var heroes: Array = scene_tree.get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit and hero.npc_type == npc_type:
			return true
	return false


func _get_best_level_data(buildings_list: Array) -> Dictionary:
	var best_level_data: Dictionary = {}
	var highest_level: int = 0
	for b: Node in buildings_list:
		if "current_level" in b and b.current_level > highest_level:
			highest_level = b.current_level
			best_level_data = b.level_data
	if best_level_data.is_empty() and not buildings_list.is_empty():
		best_level_data = buildings_list[0].level_data
	return best_level_data
