class_name ExpeditionBattle
extends Node2D
## ExpeditionBattle -- 出征战斗控制器
## 管理三段式远征实战的完整生命周期：
## 阶段1: 小怪清理 → 阶段2: 精英战斗 → 阶段3: 城堡/BOSS击破
## 英雄按 AI 自动战斗，不需要玩家操控。

# ============================================================
# 信号
# ============================================================

signal battle_started()
signal battle_ended(reason: String)  # "victory", "defeat", "timeout"
signal phase_enemies_cleared()
signal castle_destroyed()

# ============================================================
# 常量
# ============================================================

## 敌人场景路径映射（复用 WaveSpawner 的映射）
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

## 战斗是否激活
var is_battle_active: bool = false

## ExpeditionManager 引用
var _expedition_manager: ExpeditionManager = null

## GameSession 引用
var _game_session_ref: Node2D = null

## 参战 NPC 列表
var _active_npcs: Array[NPCUnit] = []

## NPC 原始数据（用于恢复）
var _npc_data: Array[Dictionary] = []

## 当前阶段的敌人生成计划
var _spawn_timers: Array = []
var _total_to_spawn: int = 0
var _total_spawned: int = 0
var _active_enemies: int = 0
var _all_fixed_spawned: bool = false

## 当前阶段的城堡/BOSS 节点
var _evil_castle: EvilCastle = null
var _has_castle_target: bool = false
var _has_boss_target: bool = false

## UI 节点
var _background: ColorRect = null
var _ui_layer: CanvasLayer = null
var _title_label: Label = null
var _timer_label: Label = null
var _phase_label: Label = null
var _status_label: Label = null

## 敌人目标位置（NPC 的战斗位置）
var _battle_center: Vector2 = Vector2(240.0, 135.0)

# ============================================================
# 公开方法
# ============================================================

## 检查是否有出征 NPC
func has_expedition_npcs() -> bool:
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit:
			return true
	return false


## 开始三段式远征战斗
func start_battle(npcs: Array, game_session: Node2D, expedition_manager: ExpeditionManager) -> void:
	_game_session_ref = game_session
	_expedition_manager = expedition_manager
	_active_npcs.clear()
	_npc_data.clear()

	# 保存 NPC 原始位置和巡逻中心
	for npc: NPCUnit in npcs:
		_active_npcs.append(npc)
		_npc_data.append({
			"npc": npc,
			"original_position": npc.global_position,
			"patrol_center": npc.patrol_center
		})

	# 创建深红色背景
	_create_background()

	# 隐藏防守元素
	_hide_defense_elements()

	# 移动 NPC 到战斗位置
	_spawn_npcs_for_battle()

	# 创建出征 UI
	_create_battle_ui()

	# 连接 ExpeditionManager 信号
	if _expedition_manager:
		if not _expedition_manager.expedition_phase_changed.is_connected(_on_phase_changed):
			_expedition_manager.expedition_phase_changed.connect(_on_phase_changed)
		if not _expedition_manager.expedition_completed.is_connected(_on_expedition_completed):
			_expedition_manager.expedition_completed.connect(_on_expedition_completed)
		if not _expedition_manager.expedition_timer_tick.is_connected(_on_timer_tick):
			_expedition_manager.expedition_timer_tick.connect(_on_timer_tick)

	is_battle_active = true
	battle_started.emit()


## 帧更新
func _process(delta: float) -> void:
	if not is_battle_active:
		return

	# 处理敌人生成
	_process_spawning(delta)

	# 检查存活 NPC
	var all_dead: bool = true
	for npc: NPCUnit in _active_npcs:
		if is_instance_valid(npc) and npc.stats.is_alive():
			all_dead = false
			break

	if all_dead and is_battle_active:
		if _expedition_manager:
			_expedition_manager.on_all_heroes_dead()
		return

	# 检查城堡/BOSS 状态
	if _has_castle_target and _evil_castle != null and is_instance_valid(_evil_castle):
		if _evil_castle.stats.current_hp <= 0.0:
			_has_castle_target = false
			_on_castle_or_boss_destroyed()
			return

	# 检查阶段完成：所有固定敌人已生成且全部消灭（无城堡/BOSS目标）
	if not _has_castle_target and not _has_boss_target:
		if _all_fixed_spawned and _active_enemies <= 0:
			_on_phase_enemies_cleared()


## 检查邪恶城堡是否被摧毁（兼容旧接口）
func is_evil_castle_destroyed() -> bool:
	if _evil_castle == null:
		return true
	return not is_instance_valid(_evil_castle) or _evil_castle.stats.current_hp <= 0.0

# ============================================================
# 阶段管理
# ============================================================

## 当 ExpeditionManager 发出阶段切换信号
func _on_phase_changed(phase_index: int, phase_name: String, description: String) -> void:
	# 清除上一阶段的敌人和城堡
	_clear_phase_entities()

	# 更新 UI
	if _phase_label:
		_phase_label.text = "阶段 %d/3: %s" % [phase_index + 1, phase_name]
	if _status_label:
		_status_label.text = description

	# 加载新阶段的敌人生成数据
	if _expedition_manager:
		var phase_data: Dictionary = _expedition_manager.get_current_phase_data()
		_setup_phase(phase_data)


## 设置阶段的敌人生成
func _setup_phase(phase_data: Dictionary) -> void:
	_spawn_timers.clear()
	_total_to_spawn = 0
	_total_spawned = 0
	_active_enemies = 0
	_all_fixed_spawned = false
	_has_castle_target = false
	_has_boss_target = false

	# 检查是否有城堡目标
	var castle_hp: float = float(phase_data.get("castle_hp", 0))
	if castle_hp > 0.0:
		_has_castle_target = true
		_create_evil_castle(castle_hp)

	# 检查是否有 BOSS 目标
	var boss_hp: float = float(phase_data.get("boss_hp", 0))
	if boss_hp > 0.0:
		_has_boss_target = true
		_has_castle_target = true  # BOSS 也用城堡逻辑判断
		_create_evil_castle(boss_hp)

	# 设置敌人生成计划
	var enemies_config: Array = phase_data.get("enemies", [])
	var routes: Array = phase_data.get("spawn_routes", ["east"])

	for enemy_config: Dictionary in enemies_config:
		var enemy_type: String = enemy_config.get("type", "skeleton")
		var count: int = int(enemy_config.get("count", 0))
		var interval: float = float(enemy_config.get("interval", 1.0))
		var delay: float = float(enemy_config.get("delay", 0.0))
		var is_continuous: bool = enemy_config.get("spawn_continuous", false)
		var spawn_rate: int = int(enemy_config.get("spawn_rate", 1))
		var spawn_interval: float = float(enemy_config.get("spawn_interval", 5.0))

		if is_continuous:
			var spawn_entry: Dictionary = {
				"type": enemy_type,
				"remaining": -1,
				"interval": spawn_interval,
				"timer": 0.0,
				"delay": delay,
				"delay_remaining": delay,
				"is_continuous": true,
				"spawn_rate": spawn_rate,
				"spawn_interval": spawn_interval,
				"continuous_timer": 0.0,
				"routes": routes,
				"route_index": 0,
			}
			_spawn_timers.append(spawn_entry)
		else:
			if count > 0:
				_total_to_spawn += count
			var spawn_entry: Dictionary = {
				"type": enemy_type,
				"remaining": count,
				"interval": interval if interval > 0.0 else 1.0,
				"timer": 0.0,
				"delay": delay,
				"delay_remaining": delay,
				"is_continuous": false,
				"spawn_rate": 0,
				"spawn_interval": 0.0,
				"continuous_timer": 0.0,
				"routes": routes,
				"route_index": 0,
			}
			_spawn_timers.append(spawn_entry)

	# 如果没有敌人生成且有城堡，只需击破城堡
	if _total_to_spawn == 0 and _spawn_timers.is_empty():
		_all_fixed_spawned = true


## 处理敌人生成（每帧调用）
func _process_spawning(delta: float) -> void:
	if _spawn_timers.is_empty():
		_all_fixed_spawned = true
		return

	var all_finished: bool = true

	for entry: Dictionary in _spawn_timers:
		if entry["delay_remaining"] > 0.0:
			entry["delay_remaining"] -= delta
			all_finished = false
			continue

		if entry["is_continuous"]:
			all_finished = false
			entry["continuous_timer"] += delta
			if entry["continuous_timer"] >= entry["spawn_interval"]:
				entry["continuous_timer"] -= entry["spawn_interval"]
				var routes: Array = entry["routes"]
				for i in range(entry["spawn_rate"]):
					var route: String = _get_next_route(entry, routes)
					_spawn_expedition_enemy(entry["type"], route)
		else:
			if entry["remaining"] <= 0:
				continue
			all_finished = false
			entry["timer"] += delta
			if entry["timer"] >= entry["interval"]:
				entry["timer"] -= entry["interval"]
				var routes: Array = entry["routes"]
				var route: String = _get_next_route(entry, routes)
				_spawn_expedition_enemy(entry["type"], route)
				entry["remaining"] -= 1
				_total_spawned += 1

	if all_finished:
		_all_fixed_spawned = true

# ============================================================
# 敌人生成
# ============================================================

## 生成远征敌人
func _spawn_expedition_enemy(type: String, _route: String) -> void:
	var scene_path: String = ENEMY_SCENE_MAP.get(type, "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("[ExpeditionBattle] 敌人场景不存在 type=%s" % type)
		return

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return

	var enemy: Node2D = scene.instantiate() as Node2D

	# 在右侧生成，向左移动攻击 NPC
	var spawn_x: float = 450.0 + randf_range(-10.0, 10.0)
	var spawn_y: float = _battle_center.y + randf_range(-60.0, 60.0)
	enemy.global_position = Vector2(spawn_x, spawn_y)

	# 添加到场景树
	if _game_session_ref:
		_game_session_ref.add_child(enemy)
	else:
		add_child(enemy)

	# 激活敌人
	if enemy.has_method("activate"):
		# 目标设定为 NPC 的中心位置
		enemy.activate(enemy.global_position, _battle_center)
	elif "is_active" in enemy:
		enemy.is_active = true
		enemy.visible = true

	# 设置目标位置
	if enemy.has_method("set_target_position"):
		enemy.set_target_position(_battle_center)
	elif "target_position" in enemy:
		enemy.target_position = _battle_center

	# 加入远征敌人分组
	if not enemy.is_in_group("expedition_enemies"):
		enemy.add_to_group("expedition_enemies")
	if not enemy.is_in_group("enemies"):
		enemy.add_to_group("enemies")

	# 连接死亡信号
	if enemy.has_signal("enemy_died"):
		if not enemy.enemy_died.is_connected(_on_expedition_enemy_died):
			enemy.enemy_died.connect(_on_expedition_enemy_died)

	_active_enemies += 1


## 远征敌人死亡回调
func _on_expedition_enemy_died(enemy: Node2D) -> void:
	_active_enemies = maxi(_active_enemies - 1, 0)

	# 释放敌人节点
	if is_instance_valid(enemy):
		enemy.queue_free()


## 城堡/BOSS 被摧毁回调
func _on_castle_or_boss_destroyed() -> void:
	if _expedition_manager:
		_expedition_manager.on_castle_or_boss_destroyed()


## 阶段所有敌人清除
func _on_phase_enemies_cleared() -> void:
	if _expedition_manager:
		_expedition_manager.on_phase_enemies_cleared()

# ============================================================
# 出征完成
# ============================================================

## 当 ExpeditionManager 发出出征完成信号
func _on_expedition_completed(expedition_id: String, success: bool, rewards: Dictionary) -> void:
	_end_battle("victory" if success else "defeat")


## 当 ExpeditionManager 发出计时器 tick
func _on_timer_tick(remaining: float, phase_index: int) -> void:
	if _timer_label:
		_timer_label.text = "剩余: %ds" % ceili(maxf(remaining, 0.0))


## 结束战斗
func _end_battle(reason: String) -> void:
	is_battle_active = false

	# 清除所有远征敌人
	_clear_phase_entities()

	# 断开 ExpeditionManager 信号
	if _expedition_manager:
		if _expedition_manager.expedition_phase_changed.is_connected(_on_phase_changed):
			_expedition_manager.expedition_phase_changed.disconnect(_on_phase_changed)
		if _expedition_manager.expedition_completed.is_connected(_on_expedition_completed):
			_expedition_manager.expedition_completed.disconnect(_on_expedition_completed)
		if _expedition_manager.expedition_timer_tick.is_connected(_on_timer_tick):
			_expedition_manager.expedition_timer_tick.disconnect(_on_timer_tick)

	# 移除出征 UI
	_remove_battle_ui()

	# 移除背景
	if _background != null and is_instance_valid(_background):
		_background.queue_free()
		_background = null

	# 恢复防守元素
	_restore_defense_elements()

	# 恢复 NPC 位置
	_restore_npcs()

	battle_ended.emit(reason)

# ============================================================
# 清理与恢复
# ============================================================

## 清除当前阶段的所有敌人和城堡
func _clear_phase_entities() -> void:
	# 清除远征敌人
	var enemies: Array = get_tree().get_nodes_in_group("expedition_enemies")
	for enemy: Node in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()

	# 清除城堡/BOSS
	if _evil_castle != null and is_instance_valid(_evil_castle):
		_evil_castle.queue_free()
		_evil_castle = null

	_spawn_timers.clear()
	_active_enemies = 0
	_all_fixed_spawned = false
	_has_castle_target = false
	_has_boss_target = false

# ============================================================
# 场景设置
# ============================================================

## 创建背景
func _create_background() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.3, 0.1, 0.1, 1.0)
	_background.z_index = -5
	_background.position = Vector2(-10.0, -10.0)
	_background.size = Vector2(500.0, 290.0)
	if _game_session_ref:
		_game_session_ref.add_child(_background)


## 隐藏防守元素
func _hide_defense_elements() -> void:
	if not _game_session_ref:
		return

	if _game_session_ref.has_node("Map"):
		_game_session_ref.get_node("Map").visible = false
	if _game_session_ref.has_node("Entities/Enemies"):
		_game_session_ref.get_node("Entities/Enemies").visible = false
	if _game_session_ref.has_node("Entities/Buildings"):
		_game_session_ref.get_node("Entities/Buildings").visible = false

	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if not (hero is NPCUnit) and hero is CanvasItem:
			hero.visible = false


## 恢复防守元素
func _restore_defense_elements() -> void:
	if not _game_session_ref:
		return

	if _game_session_ref.has_node("Map"):
		_game_session_ref.get_node("Map").visible = true
	if _game_session_ref.has_node("Entities/Enemies"):
		_game_session_ref.get_node("Entities/Enemies").visible = true
	if _game_session_ref.has_node("Entities/Buildings"):
		_game_session_ref.get_node("Entities/Buildings").visible = true

	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if not (hero is NPCUnit) and hero is CanvasItem:
			hero.visible = true
		if hero is HeroBase:
			hero.set_move_direction(Vector2.ZERO)


## 创建邪恶城堡/BOSS 目标
func _create_evil_castle(hp: float) -> void:
	_evil_castle = EvilCastle.new()
	_evil_castle.global_position = Vector2(420.0, 135.0)

	var entities_node: Node = null
	if _game_session_ref and _game_session_ref.has_node("Entities"):
		entities_node = _game_session_ref.get_node("Entities")
	else:
		entities_node = _game_session_ref

	if entities_node:
		entities_node.add_child(_evil_castle)

	_evil_castle.initialize(hp, 15.0, 120.0, 2.0)

	if _evil_castle.has_signal("castle_destroyed"):
		_evil_castle.castle_destroyed.connect(_on_evil_castle_destroyed)


## 城堡被摧毁信号回调
func _on_evil_castle_destroyed() -> void:
	_on_castle_or_boss_destroyed()


## 生成 NPC 到战斗位置
func _spawn_npcs_for_battle() -> void:
	var spawn_x: float = 30.0
	var center_y: float = 135.0
	var spacing: float = 30.0

	var count: int = _active_npcs.size()
	var start_y: float = center_y - (count - 1) * spacing / 2.0

	for i in range(count):
		var npc: NPCUnit = _active_npcs[i]
		if not is_instance_valid(npc):
			continue

		var spawn_pos := Vector2(spawn_x, start_y + i * spacing)

		# 加入远征英雄分组
		if not npc.is_in_group("expedition_heroes"):
			npc.add_to_group("expedition_heroes")

		if npc.has_method("enter_expedition"):
			npc.enter_expedition(spawn_pos, 420.0)


## 恢复 NPC 到原始位置
func _restore_npcs() -> void:
	for data: Dictionary in _npc_data:
		var npc: NPCUnit = data["npc"]
		if not is_instance_valid(npc):
			continue

		# 移除远征英雄分组
		if npc.is_in_group("expedition_heroes"):
			npc.remove_from_group("expedition_heroes")

		var original_pos: Vector2 = data["original_position"]
		var original_center: Vector2 = data["patrol_center"]

		if npc.has_method("exit_expedition"):
			npc.exit_expedition(original_pos, original_center)

# ============================================================
# UI
# ============================================================

## 创建出征战斗 UI
func _create_battle_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# 标题 "出征模式"
	_title_label = Label.new()
	_title_label.text = "出征模式"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_title_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.position = Vector2(380, 10)
	_title_label.size = Vector2(200, 40)
	_ui_layer.add_child(_title_label)

	# 阶段信息
	_phase_label = Label.new()
	_phase_label.text = "阶段 1/3"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 18)
	_phase_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
	_phase_label.position = Vector2(380, 45)
	_phase_label.size = Vector2(200, 25)
	_ui_layer.add_child(_phase_label)

	# 倒计时
	_timer_label = Label.new()
	_timer_label.text = "剩余: --s"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_timer_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_label.add_theme_constant_override("shadow_offset_y", 1)
	_timer_label.position = Vector2(400, 70)
	_timer_label.size = Vector2(160, 30)
	_ui_layer.add_child(_timer_label)

	# 状态说明
	_status_label = Label.new()
	_status_label.text = "准备战斗..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_status_label.position = Vector2(300, 500)
	_status_label.size = Vector2(360, 30)
	_ui_layer.add_child(_status_label)


## 更新出征 UI
func _update_battle_ui() -> void:
	if _status_label and _evil_castle and is_instance_valid(_evil_castle):
		var hp_pct: int = int(_evil_castle.stats.current_hp / _evil_castle.stats.max_hp * 100.0)
		_status_label.text = "目标 HP: %d%%" % hp_pct


## 移除出征 UI
func _remove_battle_ui() -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.queue_free()
		_ui_layer = null
	_title_label = null
	_timer_label = null
	_phase_label = null
	_status_label = null

# ============================================================
# 工具方法
# ============================================================

## 在多路线间轮流选择
func _get_next_route(entry: Dictionary, routes: Array) -> String:
	if routes.is_empty():
		return "east"
	var idx: int = entry.get("route_index", 0) % routes.size()
	entry["route_index"] = idx + 1
	return routes[idx]
