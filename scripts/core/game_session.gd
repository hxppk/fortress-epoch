extends Node2D
## 游戏会话顶层控制器
## 管理英雄生成、阶段流程、建筑放置、出征、输入分发
## Phase 4: 由 PhaseManager 驱动完整流程

# 场景预加载
const WolfKnightScene := preload("res://scenes/entities/heroes/wolf_knight.tscn")
const MeteorMageScene := preload("res://scenes/entities/heroes/meteor_mage.tscn")
const NPCScene := preload("res://scenes/entities/npcs/npc_base.tscn")

# 节点引用 — 基础系统
@onready var map: Node2D = $Map
@onready var heroes_node: Node2D = $Entities/Heroes
@onready var enemies_node: Node2D = $Entities/Enemies
@onready var buildings_node: Node2D = $Entities/Buildings
@onready var camera: Camera2D = $Camera2D
@onready var ui_layer: CanvasLayer = $UI
@onready var wave_spawner: WaveSpawner = $WaveSpawner
@onready var enemy_pool: EnemyPool = $EnemyPool
@onready var tower_placement: TowerPlacement = $TowerPlacement
@onready var phase_manager: PhaseManager = $PhaseManager
@onready var expedition_manager: ExpeditionManager = $ExpeditionManager
var expedition_battle: ExpeditionBattle = null

# 节点引用 — UI
@onready var hud: Control = $UI/HUD
@onready var building_selection: Control = $UI/BuildingSelection
@onready var building_upgrade_panel: Control = $UI/BuildingUpgradePanel
@onready var card_selection: Control = $UI/CardSelection
@onready var wave_preview: Control = $UI/WavePreview
@onready var boss_hp_bar: Control = $UI/BossHPBar
@onready var minimap: Control = $UI/Minimap
@onready var expedition_panel: Control = $UI/ExpeditionPanel
@onready var result_screen: Control = $UI/ResultScreen
var pause_menu: Control = null

# 卡牌系统
var card_pool: CardPool = null
var card_effects: CardEffects = null

# 游戏状态
var current_hero: HeroBase = null
var skill_system: SkillSystem = null
var auto_attack: AutoAttackComponent = null

# 堡垒核心位置（地图中心偏下）
var fortress_position := Vector2(40, 135)

# 出生点
var spawn_points := {
	"north": Vector2(500, 40),
	"east": Vector2(500, 135),
	"south": Vector2(500, 230),
	"west": Vector2(500, 135),
}


func _ready() -> void:
	_setup_game()


func _setup_game() -> void:
	# 初始化 GameManager
	GameManager.start_game()

	# 初始化敌人对象池
	enemy_pool.initialize(enemies_node)

	# 初始化波次生成器
	wave_spawner.initialize(enemy_pool, fortress_position)
	wave_spawner.set_spawn_points(spawn_points)
	wave_spawner.wave_started.connect(_on_wave_started)
	wave_spawner.wave_completed.connect(_on_wave_completed)
	wave_spawner.all_waves_completed.connect(_on_all_waves_completed)

	# 初始化塔放置系统
	tower_placement.buildings_parent = buildings_node
	tower_placement.placeable_area = Rect2i(2, 2, 26, 22)
	tower_placement.building_placed.connect(_on_building_placed)

	# 建筑选择 UI 信号
	if building_selection and building_selection.has_signal("building_selected"):
		building_selection.building_selected.connect(_on_building_selection_made)

	# 城镇升级信号 -> 标记待选卡牌
	if GameManager.has_signal("town_level_up"):
		GameManager.town_level_up.connect(_on_town_level_up)

	# 游戏结束信号 -> 结算屏幕
	GameManager.game_over.connect(_on_game_over)

	# 初始化卡牌系统
	card_pool = CardPool.new()
	card_pool.initialize()

	card_effects = CardEffects.new()
	card_effects.name = "CardEffects"
	add_child(card_effects)

	# 连接卡牌选择 UI 信号
	if card_selection and card_selection.has_signal("card_selected"):
		card_selection.card_selected.connect(_on_card_selected)

	# 初始化 PhaseManager
	phase_manager.initialize(wave_spawner)
	phase_manager.phase_changed.connect(_on_phase_changed)
	phase_manager.countdown_tick.connect(_on_countdown_tick)
	phase_manager.tutorial_message.connect(_on_tutorial_message)
	phase_manager.transition_tick.connect(_on_transition_tick)
	phase_manager.transition_ended.connect(_on_transition_ended)

	# 初始化出征系统
	expedition_manager.initialize()
	expedition_manager.expedition_started.connect(_on_expedition_started)
	expedition_manager.expedition_progress.connect(_on_expedition_progress)
	expedition_manager.expedition_completed.connect(_on_expedition_completed)
	expedition_manager.support_used.connect(_on_support_used)

	# Initialize expedition battle system (visual attack mode)
	expedition_battle = ExpeditionBattle.new()
	expedition_battle.name = "ExpeditionBattle"
	add_child(expedition_battle)
	expedition_battle.battle_ended.connect(_on_expedition_battle_ended)

	# 出征 UI 信号
	if expedition_panel:
		if expedition_panel.has_signal("expedition_selected"):
			expedition_panel.expedition_selected.connect(_on_expedition_selected)
		if expedition_panel.has_signal("support_requested"):
			expedition_panel.support_requested.connect(_on_support_requested)

	# 结算屏幕信号
	if result_screen:
		if result_screen.has_signal("restart_requested"):
			result_screen.restart_requested.connect(_on_restart_requested)
		if result_screen.has_signal("main_menu_requested"):
			result_screen.main_menu_requested.connect(_on_main_menu_requested)

	# NPC 自动生成信号
	if BuildingManager.has_signal("npc_spawn_triggered"):
		BuildingManager.npc_spawn_triggered.connect(_on_npc_spawn_triggered)

	# 实例化暂停菜单
	var PauseMenuScene := preload("res://scenes/ui/pause_menu.tscn")
	pause_menu = PauseMenuScene.instantiate()
	ui_layer.add_child(pause_menu)
	if pause_menu.has_signal("resume_requested"):
		pause_menu.resume_requested.connect(_on_pause_resume)
	if pause_menu.has_signal("restart_requested"):
		pause_menu.restart_requested.connect(_on_pause_restart)
	if pause_menu.has_signal("main_menu_requested"):
		pause_menu.main_menu_requested.connect(_on_pause_main_menu)

	# 生成英雄
	_spawn_hero()

	# 通过 PhaseManager 启动游戏流程
	phase_manager.start_game_flow()


func _spawn_hero() -> void:
	current_hero = WolfKnightScene.instantiate() as HeroBase
	heroes_node.add_child(current_hero)
	current_hero.global_position = fortress_position + Vector2(30, 0)
	current_hero.initialize("wolf_knight")
	current_hero.add_to_group("heroes")

	# 应用局外加成（必须在 initialize 之后，因为 initialize 会 clear modifiers）
	GameManager.apply_meta_bonuses_to_hero(current_hero)

	# 开局加成通知
	_show_meta_bonus_notification()

	# 设置技能系统
	skill_system = SkillSystem.new()
	current_hero.add_child(skill_system)
	skill_system.initialize(current_hero, current_hero.hero_data)

	# 设置自动攻击组件
	auto_attack = AutoAttackComponent.new()
	current_hero.add_child(auto_attack)
	var attack_data: Dictionary = current_hero.hero_data.get("auto_attack", {})
	auto_attack.attack_pattern = attack_data.get("pattern", "single_target")
	auto_attack.fan_angle = attack_data.get("angle", 120.0)
	auto_attack.aoe_radius = attack_data.get("radius", 32.0)
	auto_attack.hit_count_threshold = attack_data.get("hit_count_threshold", 0)
	auto_attack.threshold_effect = attack_data.get("on_threshold_effect", "")
	var stats_comp: StatsComponent = current_hero.get_node("StatsComponent")
	var attack_area: Area2D = current_hero.get_node("AttackArea")
	auto_attack.initialize(current_hero, stats_comp, attack_area)



func _process(_delta: float) -> void:
	# 允许在多种活跃状态下处理输入
	var state: String = GameManager.game_state
	if state in ["playing", "boss", "transition"]:
		_handle_input()


func _unhandled_input(event: InputEvent) -> void:
	# ESC: 优先取消建筑放置，否则弹暂停菜单
	if event.is_action_pressed("ui_cancel"):
		if tower_placement.is_placing:
			tower_placement.cancel_placement()
		else:
			_handle_esc_pause()


func _handle_input() -> void:
	if current_hero == null:
		return

	# 移动输入
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	current_hero.set_move_direction(direction.normalized())

	# 技能输入
	if skill_system:
		if Input.is_action_just_pressed("skill_1"):
			if skill_system.can_use_skill(1):
				skill_system.use_skill(1)
		if Input.is_action_just_pressed("skill_2"):
			if skill_system.can_use_skill(2):
				skill_system.use_skill(2)
		if Input.is_action_just_pressed("ultimate"):
			if skill_system.can_use_ultimate():
				skill_system.use_ultimate()

	# 建筑放置快捷键（数字键 1-3）— 放置中可切换建筑类型
	if Input.is_key_pressed(KEY_1):
		tower_placement.start_placement("arrow_tower")
	elif Input.is_key_pressed(KEY_2):
		tower_placement.start_placement("gold_mine")
	elif Input.is_key_pressed(KEY_3):
		tower_placement.start_placement("barracks")


# ============================================================
# PhaseManager 回调
# ============================================================

func _on_phase_changed(phase_name: String, _phase_data: Dictionary) -> void:
	print("[GameSession] 阶段切换: %s" % phase_name)

	# 阶段切换时关闭建筑升级面板，防止与其他 UI 面板重叠
	if building_upgrade_panel and building_upgrade_panel.has_method("hide_panel"):
		building_upgrade_panel.hide_panel()

	match phase_name:
		"transition":
			# 显示出征选择界面
			if expedition_panel and expedition_panel.has_method("show_selection"):
				expedition_panel.show_selection(expedition_manager.get_available_expeditions())
		"expedition":
			_start_expedition_battle()
		"card_selection":
			# 先弹建筑选择，完成后再弹卡牌选择
			_handle_card_selection_phase()
		"boss":
			# 监听敌人生成，绑定 BOSS 血条
			if not wave_spawner.enemy_spawned.is_connected(_on_enemy_spawned_for_boss):
				wave_spawner.enemy_spawned.connect(_on_enemy_spawned_for_boss)


## 卡牌选择阶段：先建筑选择 -> 再卡牌选择
func _handle_card_selection_phase() -> void:
	# 城镇升级时先弹出三选一建筑选择
	if building_selection and building_selection.has_method("show_selection"):
		building_selection.show_selection(["arrow_tower", "gold_mine", "barracks"])
		# 仅在 UI 确实激活时等待选择完成
		if building_selection.is_active:
			await building_selection.building_selected
	# 建筑选择完成，触发卡牌选择
	_trigger_card_selection()


func _on_tutorial_message(text: String) -> void:
	print("[GameSession] 引导提示: %s" % text)
	# 调用 HUD 的 tutorial tip 显示
	if hud and hud.has_method("show_tutorial_tip"):
		hud.show_tutorial_tip(text)


func _on_transition_tick(remaining: float) -> void:
	# 更新 HUD 中的倒计时显示
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(0, "出征准备 %.0fs" % maxf(remaining, 0))


func _on_countdown_tick(seconds: int) -> void:
	if hud and hud.has_method("show_countdown"):
		hud.show_countdown(seconds)


func _on_transition_ended() -> void:
	print("[GameSession] 过渡倒计时结束")


# ============================================================
# WaveSpawner 回调（委托给 PhaseManager）
# ============================================================

func _on_wave_started(wave_index: int, wave_label: String) -> void:
	print("[GameSession] 波次 %d 开始: %s" % [wave_index + 1, wave_label])
	_update_wave_hud(wave_index, wave_label)

	# 显示波次预告
	if wave_preview and wave_preview.has_method("show_preview"):
		var waves: Array = wave_spawner.current_stage_data.get("waves", [])
		if wave_index < waves.size():
			wave_preview.show_preview(waves[wave_index])


func _on_wave_completed(wave_index: int, rewards: Dictionary) -> void:
	print("[GameSession] 波次 %d 完成! 奖励: %s" % [wave_index + 1, str(rewards)])
	# 委托给 PhaseManager 处理流程路由
	phase_manager.on_wave_completed(wave_index, rewards)


func _on_all_waves_completed(stage_id: String) -> void:
	print("[GameSession] 阶段 %s 全部完成!" % stage_id)
	phase_manager.on_all_waves_completed(stage_id)


func _update_wave_hud(wave_index: int, label: String) -> void:
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(wave_index + 1, label)


# ============================================================
# 出征系统回调
# ============================================================

func _on_expedition_selected(expedition_id: String) -> void:
	if expedition_id == "":
		# 跳过出征
		print("[GameSession] 玩家选择跳过出征")
		if expedition_panel:
			expedition_panel.hide_panel()
		phase_manager.on_expedition_completed()
		return

	print("[GameSession] 玩家选择出征: %s" % expedition_id)

	# 获取英雄属性快照
	var hero_stats: Dictionary = {}
	if current_hero and current_hero.has_node("StatsComponent"):
		var stats: StatsComponent = current_hero.get_node("StatsComponent")
		hero_stats = {
			"attack": int(stats.get_stat("attack")),
			"defense": int(stats.get_stat("defense")),
			"hp": int(stats.get_stat("hp")),
			"speed": int(stats.get_stat("speed")),
		}

	expedition_manager.start_expedition(expedition_id, hero_stats)


func _on_expedition_started(expedition_id: String) -> void:
	print("[GameSession] 出征开始: %s" % expedition_id)
	# 切换 UI 到进度显示
	var exp_name: String = ""
	for ed: Dictionary in expedition_manager.all_expeditions:
		if ed.get("id", "") == expedition_id:
			exp_name = ed.get("name", "出征中")
			break
	if expedition_panel and expedition_panel.has_method("show_progress"):
		expedition_panel.show_progress(exp_name)


func _on_expedition_progress(message: String, progress: float) -> void:
	if expedition_panel and expedition_panel.has_method("update_progress"):
		expedition_panel.update_progress(message, progress)


func _on_expedition_completed(expedition_id: String, success: bool, rewards: Dictionary) -> void:
	print("[GameSession] 出征结束: %s — %s" % [expedition_id, "胜利" if success else "失败"])

	# 显示结算
	if expedition_panel and expedition_panel.has_method("show_result"):
		expedition_panel.show_result(success, rewards)

	# 延迟后隐藏并通知 PhaseManager
	await get_tree().create_timer(3.0).timeout
	if expedition_panel:
		expedition_panel.hide_panel()
	phase_manager.on_expedition_completed()


func _on_support_requested() -> void:
	expedition_manager.use_support()


func _on_support_used(remaining: int) -> void:
	if expedition_panel and expedition_panel.has_method("update_support_button"):
		expedition_panel.update_support_button(remaining)


## Start visual expedition battle
func _start_expedition_battle() -> void:
	if expedition_battle == null:
		phase_manager.on_expedition_completed()
		return

	# Collect all NPCUnit nodes
	var npcs: Array = []
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit and is_instance_valid(hero):
			npcs.append(hero)

	if npcs.is_empty():
		phase_manager.on_expedition_completed()
		return

	expedition_battle.start_battle(npcs, self)


## Expedition battle ended callback
func _on_expedition_battle_ended(reason: String) -> void:
	print("[GameSession] 出征战斗结束: %s" % reason)

	if reason == "victory":
		# Evil castle destroyed → game victory
		GameManager.end_game(true)
		return

	# timeout or all_dead → return to defense mode
	phase_manager.on_expedition_completed()


# ============================================================
# BOSS 系统
# ============================================================

func _on_enemy_spawned_for_boss(enemy: Node2D) -> void:
	# 检查是否是 BOSS
	if "enemy_id" in enemy and enemy.enemy_id == "demon_boss":
		if boss_hp_bar and boss_hp_bar.has_method("bind_boss"):
			boss_hp_bar.bind_boss(enemy)
		# 绑定后断开，避免重复
		if wave_spawner.enemy_spawned.is_connected(_on_enemy_spawned_for_boss):
			wave_spawner.enemy_spawned.disconnect(_on_enemy_spawned_for_boss)


# ============================================================
# 结算屏幕
# ============================================================

func _on_game_over(victory: bool) -> void:
	if result_screen and result_screen.has_method("show_result"):
		var stats: Dictionary = {
			"kill_count": GameManager.kill_count,
			"total_damage": GameManager.total_damage_dealt,
			"gold_earned": GameManager.resources.get("gold", 0),
			"crystal_earned": GameManager.resources.get("crystal", 0),
			"waves_survived": wave_spawner.current_wave_index,
			"town_level": GameManager.town_level,
		}
		result_screen.show_result(victory, stats)


func _on_restart_requested() -> void:
	if result_screen and result_screen.has_method("hide_result"):
		result_screen.hide_result()
	get_tree().reload_current_scene()


func _on_main_menu_requested() -> void:
	if result_screen and result_screen.has_method("hide_result"):
		result_screen.hide_result()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# ============================================================
# 建筑系统
# ============================================================

func _on_building_placed(building: Node, _grid_pos: Variant) -> void:
	# 注册到 BuildingManager
	if BuildingManager and BuildingManager.has_method("register_building"):
		BuildingManager.register_building(building)


func _on_town_level_up(new_level: int) -> void:
	print("[GameSession] 城镇升级到 Lv.%d!" % new_level)
	# 标记 PhaseManager 待选卡牌（在 wave_clear 后触发选择流程）
	phase_manager.pending_card_selection = true


func _on_building_selection_made(building_id: String) -> void:
	print("[GameSession] 玩家选择建筑: %s" % building_id)
	# 选择后进入放置模式
	tower_placement.start_placement(building_id)


# ============================================================
# 卡牌选择
# ============================================================

## 触发三选一卡牌选择界面
func _trigger_card_selection() -> void:
	if card_pool == null or card_selection == null:
		print("[GameSession] 卡牌系统未就绪，跳过卡牌选择")
		phase_manager.on_card_selection_done()
		return

	if current_hero == null:
		print("[GameSession] 当前无英雄，跳过卡牌选择")
		phase_manager.on_card_selection_done()
		return

	# 获取当前英雄 ID（用于 hero_filter 过滤）
	var hero_id: String = ""
	if current_hero.has_method("get") and current_hero.get("hero_id") != null:
		hero_id = current_hero.hero_id
	elif current_hero.has_meta("hero_id"):
		hero_id = current_hero.get_meta("hero_id")

	# 从卡牌池抽取 3 张
	var current_wave_val: int = GameManager.current_wave
	var total_waves: int = wave_spawner.get_total_waves() if wave_spawner.has_method("get_total_waves") else 10
	var cards: Array = card_pool.draw_three(current_wave_val, total_waves, hero_id)

	if cards.size() < 3:
		print("[GameSession] 卡牌池不足 3 张可用卡牌，跳过卡牌选择")
		phase_manager.on_card_selection_done()
		return

	# 将 CardData 转换为 Dictionary 以兼容 CardSelectionUI 信号
	var card_dicts: Array = []
	for card in cards:
		if card is CardData:
			card_dicts.append({
				"id": card.id,
				"name": card.card_name,
				"category": card.category,
				"rarity": card.rarity,
				"icon_color": card.icon_color,
				"source_building": card.source_building,
				"description": card.description,
				"effects": card.effects,
				"hero_filter": card.hero_filter,
			})
		else:
			card_dicts.append(card)

	print("[GameSession] 展示 3 张卡牌: %s" % str(card_dicts.map(func(c): return c.get("name", c.get("id", "?")))))

	# 显示卡牌选择 UI
	if card_selection.has_method("show_cards"):
		card_selection.show_cards(card_dicts)


## 玩家选择卡牌后的回调
func _on_card_selected(card_data: Dictionary) -> void:
	if current_hero == null:
		push_warning("[GameSession] _on_card_selected: 当前无英雄")
		phase_manager.on_card_selection_done()
		return

	var card_name: String = card_data.get("name", card_data.get("id", "unknown"))
	print("[GameSession] 玩家选择卡牌: %s (%s)" % [card_name, card_data.get("category", "?")])

	# 应用卡牌效果
	if card_effects:
		card_effects.apply_card(card_data, current_hero)

	# 记录选择（防止重复抽取）
	if card_pool:
		# 找到对应的 CardData 实例进行记录
		var card_id: String = card_data.get("id", "")
		for card in card_pool.all_cards:
			if card.id == card_id:
				card_pool.record_selection(card)
				break

	print("[GameSession] 卡牌 %s 效果已应用" % card_name)

	# 通知 PhaseManager 卡牌选择完成
	phase_manager.on_card_selection_done()


# ============================================================
# NPC 自动生成系统
# ============================================================

func _on_npc_spawn_triggered(building_type: String) -> void:
	_spawn_npc(building_type)


func _spawn_npc(building_type: String) -> void:
	var buildings_list: Array = BuildingManager.get_buildings_by_type(building_type)
	if buildings_list.is_empty():
		return

	# P0-1: 每种 NPC 上限 1 个
	var expected_npc_type: String
	match building_type:
		"arrow_tower": expected_npc_type = "archer"
		"barracks": expected_npc_type = "knight"
		"gold_mine": expected_npc_type = "miner"
		_: expected_npc_type = building_type

	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit and hero.npc_type == expected_npc_type:
			print("[GameSession] NPC已存在，跳过: %s" % expected_npc_type)
			return

	# 计算所有同类建筑的中心点
	var center := Vector2.ZERO
	for b: Node in buildings_list:
		center += b.global_position
	center /= float(buildings_list.size())

	var npc: NPCUnit = NPCScene.instantiate() as NPCUnit
	heroes_node.add_child(npc)

	# 获取最高等级建筑的数据
	var best_level_data: Dictionary = {}
	var highest_level: int = 0
	for b: Node in buildings_list:
		if "current_level" in b and b.current_level > highest_level:
			highest_level = b.current_level
			best_level_data = b.level_data
	if best_level_data.is_empty() and not buildings_list.is_empty():
		best_level_data = buildings_list[0].level_data

	var npc_stats: Dictionary = {}
	var attack_range: float = 40.0
	var attack_pattern: String = "single_target"
	var npc_type: String = ""

	match building_type:
		"arrow_tower":
			npc_type = "archer"
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
			npc_type = "knight"
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
			npc_type = "miner"
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

	npc.initialize(npc_type, npc_stats, center, attack_range, attack_pattern)
	npc.add_to_group("heroes")
	print("[GameSession] 自动生成 NPC: %s (建筑类型: %s)" % [npc_type, building_type])


# ============================================================
# 局外加成通知
# ============================================================

## 开局显示局外加成通知（有加成时 2 秒淡出）
func _show_meta_bonus_notification() -> void:
	if not is_instance_valid(SaveManager) or hud == null:
		return

	var bonus: Dictionary = SaveManager.get_hero_bonus("wolf_knight")
	var pct: float = bonus.get("attack_pct", 0.0)
	if pct <= 0.0:
		return

	var notification := Label.new()
	notification.text = "局外加成: 全属性 +%.0f%%" % (pct * 100)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification.add_theme_font_size_override("font_size", 20)
	notification.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	notification.add_theme_color_override("font_shadow_color", Color.BLACK)
	notification.add_theme_constant_override("shadow_offset_x", 1)
	notification.add_theme_constant_override("shadow_offset_y", 1)
	notification.anchors_preset = Control.PRESET_CENTER_TOP
	notification.offset_top = 50.0
	notification.offset_left = -120.0
	notification.offset_right = 120.0
	hud.add_child(notification)

	var tween := hud.create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 2.0).set_delay(1.5)
	tween.tween_callback(notification.queue_free)


# ============================================================
# 暂停菜单
# ============================================================

## 处理 ESC 暂停
func _handle_esc_pause() -> void:
	# 冲突处理：如果已有 UI 暂停，不弹出暂停菜单
	var state: String = GameManager.game_state
	if state not in ["playing", "defend"]:
		return

	# 显示暂停菜单
	if pause_menu and pause_menu.has_method("show_pause_menu"):
		pause_menu.show_pause_menu()


func _on_pause_resume() -> void:
	print("[GameSession] 暂停菜单: 继续游戏")


func _on_pause_restart() -> void:
	print("[GameSession] 暂停菜单: 重新开始")


func _on_pause_main_menu() -> void:
	print("[GameSession] 暂停菜单: 返回主菜单")
