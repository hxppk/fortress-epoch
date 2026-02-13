class_name ExpeditionBattle
extends Node2D
## ExpeditionBattle — 出征战斗控制器
## 管理出征模式的完整生命周期，包括场景切换、NPC 移动和邪恶城堡战斗。

# ============================================================
# 信号
# ============================================================

signal battle_started()
signal battle_ended(reason: String)  # "timeout", "all_dead", "victory"

# ============================================================
# 属性
# ============================================================

## 邪恶城堡最大生命值（首次战斗计算，持久化）
var evil_castle_max_hp: float = 0.0

## 邪恶城堡当前生命值（持久化，不会恢复）
var evil_castle_current_hp: float = 0.0

## 战斗是否激活
var is_battle_active: bool = false

## 战斗计时器（秒）
var battle_timer: float = 0.0

## 最大战斗时间
const MAX_BATTLE_TIME: float = 30.0

## 内部节点引用
var _background: ColorRect = null
var _evil_castle: EvilCastle = null
var _game_session_ref: Node2D = null
var _active_npcs: Array[NPCUnit] = []

## UI 节点
var _title_label: Label = null
var _timer_label: Label = null
var _status_label: Label = null
var _ui_layer: CanvasLayer = null

## NPC 原始数据（用于恢复）
var _npc_data: Array[Dictionary] = []

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


## 开始战斗
func start_battle(npcs: Array, game_session: Node2D) -> void:
	_game_session_ref = game_session
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

	# 首次战斗：计算城堡生命值
	if evil_castle_max_hp == 0.0:
		_calculate_castle_hp(npcs)

	# 创建深红色背景
	_create_background()

	# 隐藏防守元素
	_hide_defense_elements()

	# 创建邪恶城堡
	_create_evil_castle()

	# 移动 NPC 到左侧生成位置并启动出征模式
	_spawn_npcs_for_battle()

	# 创建出征 UI
	_create_battle_ui()

	# 初始化战斗状态
	battle_timer = MAX_BATTLE_TIME
	is_battle_active = true

	battle_started.emit()


## 帧更新
func _process(delta: float) -> void:
	if not is_battle_active:
		return

	# 倒计时
	battle_timer -= delta
	if battle_timer <= 0.0:
		_end_battle("timeout")
		return

	# 检查所有 NPC 是否死亡
	var all_dead: bool = true
	for npc: NPCUnit in _active_npcs:
		if is_instance_valid(npc) and npc.stats.is_alive():
			all_dead = false
			break

	if all_dead:
		_end_battle("all_dead")
		return

	# 更新城堡当前生命值
	if _evil_castle != null and is_instance_valid(_evil_castle):
		evil_castle_current_hp = _evil_castle.stats.current_hp

	# 更新 UI 倒计时
	_update_battle_ui()


## 检查邪恶城堡是否被摧毁
func is_evil_castle_destroyed() -> bool:
	return evil_castle_current_hp <= 0.0


# ============================================================
# 内部方法
# ============================================================

## 创建出征战斗 UI（CanvasLayer 保证覆盖游戏画面）
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

	# 倒计时
	_timer_label = Label.new()
	_timer_label.text = "剩余: 30s"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_timer_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_label.add_theme_constant_override("shadow_offset_y", 1)
	_timer_label.position = Vector2(400, 50)
	_timer_label.size = Vector2(160, 30)
	_ui_layer.add_child(_timer_label)

	# 状态说明
	_status_label = Label.new()
	_status_label.text = "NPC正在攻击邪恶城堡..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_status_label.position = Vector2(340, 500)
	_status_label.size = Vector2(280, 30)
	_ui_layer.add_child(_status_label)


## 更新出征 UI
func _update_battle_ui() -> void:
	if _timer_label:
		_timer_label.text = "剩余: %ds" % ceili(maxf(battle_timer, 0.0))

	if _status_label and _evil_castle and is_instance_valid(_evil_castle):
		var hp_pct: int = int(_evil_castle.stats.current_hp / _evil_castle.stats.max_hp * 100.0)
		_status_label.text = "邪恶城堡 HP: %d%%" % hp_pct


## 移除出征 UI
func _remove_battle_ui() -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.queue_free()
		_ui_layer = null
	_title_label = null
	_timer_label = null
	_status_label = null


## 计算城堡生命值
func _calculate_castle_hp(npcs: Array) -> void:
	var total_dps: float = 0.0

	for npc: NPCUnit in npcs:
		if not is_instance_valid(npc):
			continue
		var attack: float = npc.stats.get_stat("attack")
		var attack_speed: float = npc.stats.get_stat("attack_speed")
		var dps: float = attack * attack_speed
		total_dps += dps

	# 城堡生命值 = 总 DPS * 30 秒 * 3 倍平衡系数
	evil_castle_max_hp = total_dps * 30.0 * 3.0
	evil_castle_current_hp = evil_castle_max_hp


## 创建背景
func _create_background() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.3, 0.1, 0.1, 1.0)  # 深红色
	_background.z_index = -5
	_background.position = Vector2(-10.0, -10.0)
	_background.size = Vector2(500.0, 290.0)

	if _game_session_ref:
		_game_session_ref.add_child(_background)


## 隐藏防守元素
func _hide_defense_elements() -> void:
	if not _game_session_ref:
		return

	# 隐藏地图、敌人、建筑
	if _game_session_ref.has_node("Map"):
		_game_session_ref.get_node("Map").visible = false

	if _game_session_ref.has_node("Entities/Enemies"):
		_game_session_ref.get_node("Entities/Enemies").visible = false

	if _game_session_ref.has_node("Entities/Buildings"):
		_game_session_ref.get_node("Entities/Buildings").visible = false

	# 隐藏非 NPC 的英雄
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if not (hero is NPCUnit) and hero is CanvasItem:
			hero.visible = false


## 创建邪恶城堡
func _create_evil_castle() -> void:
	_evil_castle = EvilCastle.new()
	_evil_castle.global_position = Vector2(420.0, 135.0)

	# 添加到 Entities 节点
	var entities_node: Node = null
	if _game_session_ref and _game_session_ref.has_node("Entities"):
		entities_node = _game_session_ref.get_node("Entities")
	else:
		entities_node = _game_session_ref

	if entities_node:
		entities_node.add_child(_evil_castle)

	# 初始化城堡
	_evil_castle.initialize(evil_castle_current_hp, 15.0, 120.0, 2.0)

	# 连接城堡摧毁信号
	_evil_castle.castle_destroyed.connect(_on_castle_destroyed)


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

		# 调用 NPC 的出征方法（由另一个 agent 添加）
		if npc.has_method("enter_expedition"):
			npc.enter_expedition(spawn_pos, 420.0)


## 结束战斗
func _end_battle(reason: String) -> void:
	is_battle_active = false

	# 保存城堡当前生命值
	if _evil_castle != null and is_instance_valid(_evil_castle):
		evil_castle_current_hp = _evil_castle.stats.current_hp

	# 移除出征 UI
	_remove_battle_ui()

	# 移除并释放背景
	if _background != null and is_instance_valid(_background):
		_background.queue_free()
		_background = null

	# 移除并释放城堡
	if _evil_castle != null and is_instance_valid(_evil_castle):
		_evil_castle.queue_free()
		_evil_castle = null

	# 恢复防守元素
	_restore_defense_elements()

	# 恢复 NPC 位置和生命值
	_restore_npcs()

	battle_ended.emit(reason)


## 恢复防守元素
func _restore_defense_elements() -> void:
	if not _game_session_ref:
		return

	# 显示地图、敌人、建筑
	if _game_session_ref.has_node("Map"):
		_game_session_ref.get_node("Map").visible = true

	if _game_session_ref.has_node("Entities/Enemies"):
		_game_session_ref.get_node("Entities/Enemies").visible = true

	if _game_session_ref.has_node("Entities/Buildings"):
		_game_session_ref.get_node("Entities/Buildings").visible = true

	# 显示非 NPC 的英雄，并重置移动方向
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if not (hero is NPCUnit) and hero is CanvasItem:
			hero.visible = true
		if hero is HeroBase:
			hero.set_move_direction(Vector2.ZERO)


## 恢复 NPC 到原始位置
func _restore_npcs() -> void:
	for data: Dictionary in _npc_data:
		var npc: NPCUnit = data["npc"]
		if not is_instance_valid(npc):
			continue

		var original_pos: Vector2 = data["original_position"]
		var original_center: Vector2 = data["patrol_center"]

		# 调用 NPC 的退出出征方法（由另一个 agent 添加）
		if npc.has_method("exit_expedition"):
			npc.exit_expedition(original_pos, original_center)


## 城堡被摧毁回调
func _on_castle_destroyed() -> void:
	_end_battle("victory")
