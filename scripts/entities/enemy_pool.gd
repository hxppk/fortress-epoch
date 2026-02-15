class_name EnemyPool
extends Node
## EnemyPool — 敌人对象池
## 管理敌人实例的复用，避免频繁创建和销毁节点。

# ============================================================
# 属性
# ============================================================

## 对象池：{ "skeleton": [EnemyBase, ...], ... }
var pools: Dictionary = {}

## 预加载的场景：{ "skeleton": PackedScene, ... }
var enemy_scenes: Dictionary = {}

## 敌人的父节点
var parent_node: Node2D = null

## 场景路径映射
const SCENE_MAP: Dictionary = {
	"slime": "res://scenes/entities/enemies/slime.tscn",
	"goblin": "res://scenes/entities/enemies/goblin.tscn",
	"skeleton": "res://scenes/entities/enemies/skeleton.tscn",
	"ghost": "res://scenes/entities/enemies/ghost.tscn",
	"zombie": "res://scenes/entities/enemies/zombie.tscn",
	"orc_elite": "res://scenes/entities/enemies/orc_elite.tscn",
	"demon_boss": "res://scenes/entities/enemies/demon_boss.tscn",
}

# ============================================================
# 初始化
# ============================================================

## 设置父节点并预加载所有敌人场景
func initialize(parent: Node2D) -> void:
	parent_node = parent
	_preload_scenes()

	# 为每种敌人类型创建空池
	for type_key: String in SCENE_MAP:
		if not pools.has(type_key):
			pools[type_key] = []

# ============================================================
# 公共方法
# ============================================================

## 从池中获取敌人，若池为空则新建
func get_enemy(type: String) -> EnemyBase:
	if not SCENE_MAP.has(type):
		push_warning("EnemyPool: 未知敌人类型 '%s'" % type)
		return null

	# 尝试从池中取出一个
	if pools.has(type) and pools[type].size() > 0:
		var enemy: EnemyBase = pools[type].pop_back()
		enemy.reset()
		return enemy

	# 池为空，创建新实例
	return _create_new(type)


## 根据阶段数据预创建 50% 最大需求量的敌人实例
## stage_data: 来自 waves.json 的阶段字典（含 "waves" 数组）
func prewarm_for_stage(stage_data: Dictionary) -> void:
	# 统计该阶段各敌人类型的最大单波需求量
	var max_counts: Dictionary = {}
	var waves: Array = stage_data.get("waves", [])
	for wave: Dictionary in waves:
		var wave_counts: Dictionary = {}
		var enemies_config: Array = wave.get("enemies", [])
		for enemy_config: Dictionary in enemies_config:
			var enemy_type: String = enemy_config.get("type", "")
			if enemy_type == "":
				continue
			var count: int = int(enemy_config.get("count", 0))
			var is_continuous: bool = enemy_config.get("spawn_continuous", false)
			if is_continuous:
				# 持续生成型：按 duration / interval * rate 估算
				var duration: float = float(wave.get("duration", 60))
				var spawn_interval: float = float(enemy_config.get("spawn_interval", 5.0))
				var spawn_rate: int = int(enemy_config.get("spawn_rate", 1))
				count = int(duration / spawn_interval * spawn_rate)
			if not wave_counts.has(enemy_type):
				wave_counts[enemy_type] = 0
			wave_counts[enemy_type] += count
		# 取各波次的最大值
		for enemy_type: String in wave_counts:
			if not max_counts.has(enemy_type) or wave_counts[enemy_type] > max_counts[enemy_type]:
				max_counts[enemy_type] = wave_counts[enemy_type]

	# 预创建 50% 的最大需求量
	for enemy_type: String in max_counts:
		if not SCENE_MAP.has(enemy_type):
			continue
		var target: int = int(max_counts[enemy_type] * 0.5)
		var current: int = pools[enemy_type].size() if pools.has(enemy_type) else 0
		var to_create: int = maxi(target - current, 0)
		if to_create > 0:
			print("[EnemyPool] 预热 %s: 创建 %d 个实例" % [enemy_type, to_create])
		for i in range(to_create):
			var enemy: EnemyBase = _create_new(enemy_type)
			if enemy != null:
				if not pools.has(enemy_type):
					pools[enemy_type] = []
				pools[enemy_type].append(enemy)


## 回收敌人到池中
func return_enemy(enemy: EnemyBase) -> void:
	if enemy == null:
		return

	enemy.deactivate()

	var type: String = enemy.enemy_id
	if not pools.has(type):
		pools[type] = []

	pools[type].append(enemy)

# ============================================================
# 内部方法
# ============================================================

## 预加载所有敌人场景
func _preload_scenes() -> void:
	for type_key: String in SCENE_MAP:
		var path: String = SCENE_MAP[type_key]
		if ResourceLoader.exists(path):
			enemy_scenes[type_key] = load(path)
		else:
			push_warning("EnemyPool: 场景不存在 '%s'" % path)


## 实例化一个新敌人
func _create_new(type: String) -> EnemyBase:
	if not enemy_scenes.has(type):
		push_warning("EnemyPool: 未加载场景 '%s'" % type)
		return null

	var scene: PackedScene = enemy_scenes[type]
	var enemy: EnemyBase = scene.instantiate() as EnemyBase

	if enemy == null:
		push_warning("EnemyPool: 实例化失败 '%s'" % type)
		return null

	# 添加到父节点
	parent_node.add_child(enemy)

	# 默认停用
	enemy.deactivate()

	return enemy
