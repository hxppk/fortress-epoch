class_name WaveSpawner
extends Node
## WaveSpawner -- 读取 waves.json 配置，按时间生成敌人波次
## 管理多阶段、多波次、多路线的敌人生成逻辑。

# ============================================================
# 信号
# ============================================================

signal wave_started(wave_index: int, wave_label: String)
signal wave_completed(wave_index: int, rewards: Dictionary)
signal all_waves_completed(stage_id: String)
signal enemy_spawned(enemy: Node2D)

# ============================================================
# 常量
# ============================================================

const WAVES_JSON_PATH: String = "res://data/waves.json"

## 敌人场景路径映射
const ENEMY_SCENE_MAP: Dictionary = {
	"slime": "res://scenes/entities/enemies/slime.tscn",
	"goblin": "res://scenes/entities/enemies/goblin.tscn",
	"skeleton": "res://scenes/entities/enemies/skeleton.tscn",
	"ghost": "res://scenes/entities/enemies/ghost.tscn",
	"zombie": "res://scenes/entities/enemies/zombie.tscn",
	"orc_elite": "res://scenes/entities/enemies/orc_elite.tscn",
	"demon_boss": "res://scenes/entities/enemies/demon_boss.tscn",
}

# ============================================================
# 属性
# ============================================================

## 所有波次原始数据（从 JSON 加载）
var wave_data: Dictionary = {}

## 当前阶段配置
var current_stage_data: Dictionary = {}

## 当前波次索引（0-based）
var current_wave_index: int = 0

## 是否正在生成中
var is_spawning: bool = false

## 每种敌人的生成计时器列表
## 每项结构：{ "type": String, "remaining": int, "interval": float, "timer": float, "delay": float,
##            "delay_remaining": float, "route": String, "is_continuous": bool,
##            "spawn_rate": int, "spawn_interval": float, "continuous_timer": float }
var spawn_timers: Array = []

## 当前存活敌人数量
var active_enemies: int = 0

## 当前波已生成的敌人总数（非持续型）
var _total_to_spawn: int = 0

## 当前波已生成数量
var _total_spawned: int = 0

## 敌人对象池引用（可选，如果项目实现了 EnemyPool 则使用）
var enemy_pool: Node = null

## 出生点位置 { "north": Vector2, "east": Vector2, "south": Vector2, "west": Vector2 }
var spawn_points: Dictionary = {}

## 堡垒核心位置（敌人的移动目标）
var fortress_position: Vector2 = Vector2.ZERO

## 当前阶段 ID
var _current_stage_id: String = ""

## 是否所有波次已完成
var _all_completed: bool = false

# ============================================================
# 初始化
# ============================================================

## 初始化波次系统
func initialize(pool: Node, fortress_pos: Vector2) -> void:
	enemy_pool = pool
	fortress_position = fortress_pos
	wave_data = _load_waves_data()

	# 加载伤害倍率配置到 GameManager
	var multipliers: Dictionary = wave_data.get("balance_multipliers", {})
	if not multipliers.is_empty():
		GameManager.load_balance_multipliers(multipliers)

	# 加载共享血池配置到 GameManager
	var hp_pool: Dictionary = wave_data.get("shared_hp_pool", {})
	if hp_pool.has("by_player_count"):
		GameManager.setup_shared_hp_by_players(GameManager.player_count, hp_pool["by_player_count"])


## 设置出生点位置
func set_spawn_points(points: Dictionary) -> void:
	spawn_points = points


## 加载指定阶段数据
func load_stage(stage_id: String) -> void:
	_current_stage_id = stage_id
	current_wave_index = 0
	_all_completed = false
	is_spawning = false
	spawn_timers.clear()
	active_enemies = 0
	_total_to_spawn = 0
	_total_spawned = 0

	# 在 stages 列表中查找匹配的阶段
	var stages: Array = wave_data.get("stages", [])
	for stage: Dictionary in stages:
		if stage.get("id", "") == stage_id:
			current_stage_data = stage
			# 应用阶段级别的伤害倍率（如有），否则回退到全局配置
			var stage_multipliers: Dictionary = stage.get("balance_multipliers", {})
			if not stage_multipliers.is_empty():
				GameManager.load_balance_multipliers(stage_multipliers)
			# 预热对象池
			if enemy_pool and enemy_pool.has_method("prewarm_for_stage"):
				enemy_pool.prewarm_for_stage(stage)
			return

	push_warning("WaveSpawner: 未找到阶段 id=%s" % stage_id)
	current_stage_data = {}

# ============================================================
# 波次控制
# ============================================================

## 开始下一波
func start_next_wave() -> void:
	var waves: Array = current_stage_data.get("waves", [])
	if current_wave_index >= waves.size():
		_all_completed = true
		all_waves_completed.emit(_current_stage_id)
		return

	var wave: Dictionary = waves[current_wave_index]
	var wave_label: String = wave.get("label", "Wave %d" % (current_wave_index + 1))

	# 重置生成状态
	is_spawning = true
	spawn_timers.clear()
	_total_to_spawn = 0
	_total_spawned = 0

	# 获取该波的出生路线
	var routes: Array = wave.get("spawn_routes", ["north"])

	# 为每种敌人类型创建生成计划
	var enemies_config: Array = wave.get("enemies", [])
	for enemy_config: Dictionary in enemies_config:
		var enemy_type: String = enemy_config.get("type", "slime")
		var count: int = int(enemy_config.get("count", 0))
		var interval: float = float(enemy_config.get("interval", 1.0))
		var delay: float = float(enemy_config.get("delay", 0.0))
		var is_continuous: bool = enemy_config.get("spawn_continuous", false)
		var spawn_rate: int = int(enemy_config.get("spawn_rate", 1))
		var spawn_interval: float = float(enemy_config.get("spawn_interval", 5.0))
		var hp_mult: float = float(enemy_config.get("hp_multiplier", 1.0))

		# 为每个路线平均分配（如果有多条路线，轮流从各路线生成）
		var assigned_route: String = routes[0] if routes.size() > 0 else "north"

		if is_continuous:
			# 持续生成类型
			var spawn_entry: Dictionary = {
				"type": enemy_type,
				"remaining": -1,  # -1 表示无限
				"interval": spawn_interval,
				"timer": 0.0,
				"delay": delay,
				"delay_remaining": delay,
				"route": assigned_route,
				"is_continuous": true,
				"spawn_rate": spawn_rate,
				"spawn_interval": spawn_interval,
				"continuous_timer": 0.0,
				"routes": routes,
				"route_index": 0,
				"hp_multiplier": hp_mult,
			}
			spawn_timers.append(spawn_entry)
		else:
			_total_to_spawn += count
			var spawn_entry: Dictionary = {
				"type": enemy_type,
				"remaining": count,
				"interval": interval if interval > 0.0 else 1.0,
				"timer": 0.0,
				"delay": delay,
				"delay_remaining": delay,
				"route": assigned_route,
				"is_continuous": false,
				"spawn_rate": 0,
				"spawn_interval": 0.0,
				"continuous_timer": 0.0,
				"routes": routes,
				"route_index": 0,
				"hp_multiplier": hp_mult,
			}
			spawn_timers.append(spawn_entry)

	wave_started.emit(current_wave_index, wave_label)

# ============================================================
# 帧处理
# ============================================================

func _process(delta: float) -> void:
	if not is_spawning:
		return

	var all_finished: bool = true

	for entry: Dictionary in spawn_timers:
		# 处理延迟
		if entry["delay_remaining"] > 0.0:
			entry["delay_remaining"] -= delta
			all_finished = false
			continue

		var hp_mult: float = entry.get("hp_multiplier", 1.0)

		if entry["is_continuous"]:
			# 持续生成逻辑
			all_finished = false  # 持续生成永远不会自行结束
			entry["continuous_timer"] += delta
			if entry["continuous_timer"] >= entry["spawn_interval"]:
				entry["continuous_timer"] -= entry["spawn_interval"]
				# 一次生成 spawn_rate 只
				var routes: Array = entry["routes"]
				for i in range(entry["spawn_rate"]):
					var route: String = _get_next_route(entry, routes)
					_spawn_enemy(entry["type"], route, hp_mult)
		else:
			# 固定数量生成逻辑
			if entry["remaining"] <= 0:
				continue

			all_finished = false
			entry["timer"] += delta
			if entry["timer"] >= entry["interval"]:
				entry["timer"] -= entry["interval"]
				var routes: Array = entry["routes"]
				var route: String = _get_next_route(entry, routes)
				_spawn_enemy(entry["type"], route, hp_mult)
				entry["remaining"] -= 1
				_total_spawned += 1

	# 检查非持续型是否全部生成完毕
	if all_finished or _check_all_spawned():
		_check_wave_complete()

# ============================================================
# 敌人生成
# ============================================================

## 在指定路线生成一个敌人
func _spawn_enemy(type: String, route: String, hp_multiplier: float = 1.0) -> void:
	var spawn_pos: Vector2 = _get_spawn_position(route)

	# 添加随机偏移
	spawn_pos += Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))

	var enemy: Node2D = null

	# 优先从对象池获取
	if enemy_pool and enemy_pool.has_method("get_enemy"):
		enemy = enemy_pool.get_enemy(type)
		if enemy:
			enemy.global_position = spawn_pos
			# 激活敌人（设置 is_active, visible, move_target）
			if enemy.has_method("activate"):
				enemy.activate(spawn_pos, fortress_position)

	# 对象池没有则实例化场景
	if enemy == null:
		var scene_path: String = ENEMY_SCENE_MAP.get(type, "")
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			push_warning("WaveSpawner: 敌人场景不存在 type=%s path=%s" % [type, scene_path])
			return

		var scene: PackedScene = load(scene_path) as PackedScene
		if scene == null:
			push_warning("WaveSpawner: 无法加载敌人场景 type=%s" % type)
			return

		enemy = scene.instantiate() as Node2D
		enemy.global_position = spawn_pos

		# 添加到场景树
		if is_inside_tree() and get_tree().current_scene:
			get_tree().current_scene.add_child(enemy)
		else:
			add_child(enemy)

		# 添加到场景树后激活
		if enemy.has_method("activate"):
			enemy.activate(spawn_pos, fortress_position)
		elif "is_active" in enemy:
			enemy.is_active = true
			enemy.visible = true

	# 应用 HP 倍率
	if hp_multiplier != 1.0 and enemy != null:
		if "stats" in enemy and enemy.stats is StatsComponent:
			var base_hp: float = enemy.stats.max_hp
			enemy.stats.max_hp = base_hp * hp_multiplier
			enemy.stats.current_hp = enemy.stats.max_hp

	# 加入 enemies 分组
	if not enemy.is_in_group("enemies"):
		enemy.add_to_group("enemies")

	# 设置目标位置（堡垒核心）
	if enemy.has_method("set_target_position"):
		enemy.set_target_position(fortress_position)
	elif "target_position" in enemy:
		enemy.target_position = fortress_position

	# 连接死亡信号
	_connect_enemy_death(enemy)

	active_enemies += 1
	enemy_spawned.emit(enemy)


## 连接敌人死亡信号
func _connect_enemy_death(enemy: Node2D) -> void:
	# 连接 enemy_died 信号（die() 总是 emit，无论是 HP 归零还是到达堡垒）
	if enemy.has_signal("enemy_died"):
		if not enemy.enemy_died.is_connected(_on_enemy_died):
			enemy.enemy_died.connect(_on_enemy_died)

# ============================================================
# 敌人死亡回调
# ============================================================

## 敌人死亡处理
func _on_enemy_died(enemy: Node2D) -> void:
	active_enemies = maxi(active_enemies - 1, 0)

	# 归还对象池（类型安全检查）
	if enemy_pool and enemy_pool.has_method("return_enemy") and enemy is EnemyBase:
		enemy_pool.return_enemy(enemy as EnemyBase)

	_check_wave_complete()

# ============================================================
# 波次完成检查
# ============================================================

## 检查是否所有非持续型敌人已生成完毕
func _check_all_spawned() -> bool:
	for entry: Dictionary in spawn_timers:
		if entry["is_continuous"]:
			continue
		if entry["remaining"] > 0:
			return false
	return true


## 检查当前波是否结束
func _check_wave_complete() -> void:
	if not is_spawning:
		return

	# 条件：所有固定敌人已生成完毕 + 没有存活敌人（持续生成的波在 active_enemies==0 时也算完成）
	if not _check_all_spawned():
		return

	# 安全兜底：验证 active_enemies 计数与实际存活敌人一致
	if active_enemies > 0:
		var real_count: int = _count_alive_enemies()
		if real_count != active_enemies:
			push_warning("WaveSpawner: active_enemies 计数偏差 (%d → %d)，已修正" % [active_enemies, real_count])
			active_enemies = real_count
	if active_enemies > 0:
		return

	# 波次完成
	is_spawning = false
	spawn_timers.clear()

	# 发放奖励
	var waves: Array = current_stage_data.get("waves", [])
	var rewards: Dictionary = {}
	if current_wave_index < waves.size():
		rewards = waves[current_wave_index].get("rewards", {})
		_distribute_rewards(rewards)

	wave_completed.emit(current_wave_index, rewards)

	# 推进到下一波
	current_wave_index += 1

	# 检查是否全部波次完成
	if current_wave_index >= waves.size():
		_all_completed = true
		all_waves_completed.emit(_current_stage_id)


## 发放奖励
func _distribute_rewards(rewards: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm == null:
		return

	for resource_type: String in rewards:
		var amount: int = int(rewards[resource_type])
		if resource_type == "exp" and gm.has_method("add_exp"):
			gm.add_exp(amount)
		elif gm.has_method("add_resource"):
			gm.add_resource(resource_type, amount)


## 是否所有波次已结束
func is_all_waves_complete() -> bool:
	return _all_completed


## 获取当前阶段的总波次数
func get_total_waves() -> int:
	var waves: Array = current_stage_data.get("waves", [])
	return waves.size()

# ============================================================
# 数据加载
# ============================================================

## 从 waves.json 加载波次数据
func _load_waves_data() -> Dictionary:
	if not FileAccess.file_exists(WAVES_JSON_PATH):
		push_error("WaveSpawner: waves.json 不存在: %s" % WAVES_JSON_PATH)
		return {}

	var file: FileAccess = FileAccess.open(WAVES_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("WaveSpawner: waves.json 解析失败: %s" % json.get_error_message())
		return {}

	return json.data

# ============================================================
# 工具方法
# ============================================================

## 获取出生点位置
func _get_spawn_position(route: String) -> Vector2:
	if spawn_points.has(route):
		return spawn_points[route]

	# 默认出生点（屏幕边缘偏移）
	match route:
		"north":
			return fortress_position + Vector2(0, -300)
		"east":
			return fortress_position + Vector2(300, 0)
		"south":
			return fortress_position + Vector2(0, 300)
		"west":
			return fortress_position + Vector2(-300, 0)
		_:
			return fortress_position + Vector2(0, -300)


## 在多路线间轮流选择
func _get_next_route(entry: Dictionary, routes: Array) -> String:
	if routes.is_empty():
		return "north"

	var idx: int = entry.get("route_index", 0) % routes.size()
	entry["route_index"] = idx + 1
	return routes[idx]


## 统计场景中实际存活的敌人数量（安全兜底用）
func _count_alive_enemies() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var count: int = 0
	var enemies: Array[Node] = tree.get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is EnemyBase:
			var enemy: EnemyBase = node as EnemyBase
			if enemy.is_active and enemy.stats and enemy.stats.is_alive():
				count += 1
	return count


## 获取 GameManager 引用
func _get_game_manager() -> Node:
	return GameManager
