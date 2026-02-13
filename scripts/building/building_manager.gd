extends Node
## BuildingManager — 全局建筑管理器（Autoload 单例）
## 管理所有建筑实例、统一处理升级事件、维护击杀金币加成。

# ============================================================
# 信号
# ============================================================

signal building_registered(building: Node)
signal building_upgraded(building: Node, new_level: int)
signal kill_gold_bonus_changed(new_bonus: float)
signal npc_spawn_triggered(building_type: String)

# ============================================================
# 属性
# ============================================================

## 所有已放置的建筑
var buildings: Array[Node] = []

## 每种建筑的数量 { "arrow_tower": 0, "gold_mine": 0, "barracks": 0 }
var building_counts: Dictionary = {}

## 当前击杀金币加成（来自所有金矿中的最高等级）
var kill_gold_bonus: float = 0.0

## 已触发NPC生成的建筑类型
var npc_spawned: Dictionary = {}

# ============================================================
# 公有方法
# ============================================================

## 注册新放置的建筑
func register_building(building: Node) -> void:
	if buildings.has(building):
		push_warning("BuildingManager: 建筑已注册，跳过重复注册")
		return

	buildings.append(building)

	# 更新建筑计数
	var building_id: String = building.building_id if "building_id" in building else ""
	if building_id != "":
		if not building_counts.has(building_id):
			building_counts[building_id] = 0
		building_counts[building_id] += 1

	# 如果是金矿，重新计算击杀金币加成
	if building_id == "gold_mine":
		_update_kill_gold_bonus()

	building_registered.emit(building)

	# 检查是否达到 3 个同类建筑，触发 NPC 生成
	if building_id != "" and building_counts.get(building_id, 0) >= 3:
		if not npc_spawned.get(building_id, false):
			npc_spawned[building_id] = true
			npc_spawn_triggered.emit(building_id)


## 移除建筑
func unregister_building(building: Node) -> void:
	if not buildings.has(building):
		push_warning("BuildingManager: 建筑未注册，无法移除")
		return

	buildings.erase(building)

	# 更新建筑计数
	var building_id: String = building.building_id if "building_id" in building else ""
	if building_id != "":
		if building_counts.has(building_id):
			building_counts[building_id] = maxi(building_counts[building_id] - 1, 0)

	# 如果是金矿，重新计算击杀金币加成
	if building_id == "gold_mine":
		_update_kill_gold_bonus()


## 获取指定类型的所有建筑
func get_buildings_by_type(type: String) -> Array:
	var result: Array = []
	for building: Node in buildings:
		if not is_instance_valid(building):
			continue
		var building_id: String = building.building_id if "building_id" in building else ""
		if building_id == type:
			result.append(building)
	return result


## 返回当前击杀金币加成
func get_kill_gold_bonus() -> float:
	return kill_gold_bonus


## 所有建筑总数
func get_total_building_count() -> int:
	return buildings.size()


## 统一升级入口
func upgrade_building(building: Node) -> bool:
	if not buildings.has(building):
		push_warning("BuildingManager: 建筑未注册，无法升级")
		return false

	if not building.has_method("upgrade"):
		push_warning("BuildingManager: 建筑没有 upgrade 方法")
		return false

	var success: bool = building.upgrade()
	if not success:
		return false

	var new_level: int = building.current_level if "current_level" in building else 0
	var building_id: String = building.building_id if "building_id" in building else ""

	# 如果是金矿，升级后重新计算击杀金币加成
	if building_id == "gold_mine":
		_update_kill_gold_bonus()

	building_upgraded.emit(building, new_level)
	return true

# ============================================================
# 私有方法
# ============================================================

## 重新计算所有金矿的最高 kill_gold_bonus
func _update_kill_gold_bonus() -> void:
	var max_bonus: float = 0.0

	for building: Node in buildings:
		if not is_instance_valid(building):
			continue
		var building_id: String = building.building_id if "building_id" in building else ""
		if building_id != "gold_mine":
			continue

		# 从 level_data 中读取 kill_gold_bonus
		var level_data: Dictionary = building.level_data if "level_data" in building else {}
		var bonus: float = float(level_data.get("kill_gold_bonus", 0.0))
		if bonus > max_bonus:
			max_bonus = bonus

	if kill_gold_bonus != max_bonus:
		kill_gold_bonus = max_bonus
		kill_gold_bonus_changed.emit(kill_gold_bonus)
