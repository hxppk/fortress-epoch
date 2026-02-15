extends Node2D
## 游戏会话顶层控制器
## v0.3.0: 精简为协调层，委托子控制器处理具体逻辑。
## 子控制器: HeroController / InputController / NPCController / UIController

# 子控制器
var hero_controller: HeroController = null
var input_controller: InputController = null
var npc_controller: NPCController = null
var ui_controller: UIController = null

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

# 游戏状态
var current_hero: HeroBase = null

# 英雄复活
const RESPAWN_DELAY: float = 10.0
var _respawn_timer: Timer = null

# 堡垒核心位置
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
	GameManager.start_game()
	BuildingManager.reset()

	# 基础系统初始化
	enemy_pool.initialize(enemies_node)
	wave_spawner.initialize(enemy_pool, fortress_position)
	wave_spawner.set_spawn_points(spawn_points)
	wave_spawner.wave_started.connect(_on_wave_started)
	wave_spawner.wave_completed.connect(_on_wave_completed)
	wave_spawner.all_waves_completed.connect(_on_all_waves_completed)

	tower_placement.buildings_parent = buildings_node
	tower_placement.placeable_area = Rect2i(2, 2, 26, 22)
	tower_placement.building_placed.connect(_on_building_placed)

	if GameManager.has_signal("town_level_up"):
		GameManager.town_level_up.connect(_on_town_level_up)
	GameManager.game_over.connect(_on_game_over)

	# PhaseManager
	phase_manager.initialize(wave_spawner)
	phase_manager.phase_changed.connect(_on_phase_changed)
	phase_manager.countdown_tick.connect(_on_countdown_tick)
	phase_manager.tutorial_message.connect(_on_tutorial_message)
	phase_manager.transition_tick.connect(_on_transition_tick)
	phase_manager.transition_ended.connect(_on_transition_ended)

	# 出征系统
	expedition_manager.initialize()
	expedition_manager.expedition_started.connect(_on_expedition_started)
	expedition_manager.expedition_phase_changed.connect(_on_expedition_phase_changed)
	expedition_manager.expedition_completed.connect(_on_expedition_completed)
	expedition_manager.support_used.connect(_on_support_used)

	expedition_battle = ExpeditionBattle.new()
	expedition_battle.name = "ExpeditionBattle"
	add_child(expedition_battle)
	expedition_battle.battle_ended.connect(_on_expedition_battle_ended)

	# --- 子控制器初始化 ---

	# UIController（管理所有 UI 面板）
	ui_controller = UIController.new()
	ui_controller.name = "UIController"
	add_child(ui_controller)
	ui_controller.initialize({
		"hud": $UI/HUD,
		"building_selection": $UI/BuildingSelection,
		"building_upgrade_panel": $UI/BuildingUpgradePanel,
		"card_selection": $UI/CardSelection,
		"wave_preview": $UI/WavePreview,
		"boss_hp_bar": $UI/BossHPBar,
		"expedition_panel": $UI/ExpeditionPanel,
		"result_screen": $UI/ResultScreen,
		"ui_layer": ui_layer,
		"wave_spawner": wave_spawner,
	})

	# 卡牌系统
	var card_pool := CardPool.new()
	card_pool.initialize()
	var card_effects := CardEffects.new()
	card_effects.name = "CardEffects"
	add_child(card_effects)
	ui_controller.set_card_system(card_pool, card_effects)

	# UIController 信号 → GameSession 桥接
	ui_controller.card_selection_done.connect(func(): phase_manager.on_card_selection_done())
	ui_controller.expedition_skipped.connect(_on_expedition_skipped)
	ui_controller.expedition_selected.connect(_on_expedition_selected)
	ui_controller.building_selection_made.connect(func(id: String): tower_placement.start_placement(id))
	ui_controller.restart_requested.connect(func(): get_tree().reload_current_scene())
	ui_controller.main_menu_requested.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	ui_controller.support_requested.connect(func(t: String): expedition_manager.use_support(t))

	# HeroController
	hero_controller = HeroController.new()
	hero_controller.heroes_parent = heroes_node
	hero_controller.name = "HeroController"
	add_child(hero_controller)

	# InputController
	input_controller = InputController.new()
	input_controller.tower_placement = tower_placement
	input_controller.name = "InputController"
	add_child(input_controller)
	input_controller.building_hotkey_pressed.connect(func(id: String): tower_placement.start_placement(id))
	input_controller.pause_requested.connect(func(): ui_controller.handle_esc_pause())

	# NPCController
	npc_controller = NPCController.new()
	npc_controller.name = "NPCController"
	add_child(npc_controller)
	npc_controller.initialize(heroes_node, get_tree())

	# 生成英雄并注册到子控制器
	_spawn_hero()

	phase_manager.start_game_flow()


func _spawn_hero(hero_id: String = "wolf_knight") -> void:
	var spawn_pos: Vector2 = fortress_position + Vector2(30, 0)
	current_hero = hero_controller.spawn_hero(hero_id, spawn_pos)
	if current_hero == null:
		push_error("GameSession: 英雄生成失败 id=%s" % hero_id)
		return
	ui_controller.set_current_hero(current_hero)
	ui_controller.show_meta_bonus_notification()
	input_controller.register_hero(0, current_hero)
	current_hero.hero_died.connect(_on_hero_died)


func _process(_delta: float) -> void:
	var state: String = GameManager.game_state
	if state in ["playing", "boss", "transition"]:
		input_controller.process_input()


func _unhandled_input(event: InputEvent) -> void:
	input_controller.handle_unhandled_input(event)


# ============================================================
# PhaseManager 回调 → 委托 UIController
# ============================================================

func _on_phase_changed(phase_name: String, _phase_data: Dictionary) -> void:
	ui_controller.on_phase_changed(phase_name, expedition_manager)

func _on_tutorial_message(text: String) -> void:
	ui_controller.on_tutorial_message(text)

func _on_transition_tick(remaining: float) -> void:
	ui_controller.on_transition_tick(remaining)

func _on_countdown_tick(seconds: int) -> void:
	ui_controller.on_countdown_tick(seconds)

func _on_transition_ended() -> void:
	pass

# ============================================================
# WaveSpawner 回调
# ============================================================

func _on_wave_started(wave_index: int, wave_label: String) -> void:
	ui_controller.on_wave_started(wave_index, wave_label)
	# 新波次开始：复活所有己方单位并恢复满状态
	_revive_all_allies()

func _on_wave_completed(wave_index: int, rewards: Dictionary) -> void:
	phase_manager.on_wave_completed(wave_index, rewards)

func _on_all_waves_completed(stage_id: String) -> void:
	phase_manager.on_all_waves_completed(stage_id)

# ============================================================
# 出征系统回调
# ============================================================

func _on_expedition_skipped() -> void:
	ui_controller.on_expedition_result_dismissed()
	phase_manager.on_expedition_completed()

func _on_expedition_selected(expedition_id: String) -> void:
	expedition_manager.start_expedition(expedition_id)

func _on_expedition_started(expedition_id: String) -> void:
	ui_controller.on_expedition_started(expedition_id, expedition_manager)
	_start_expedition_battle()

func _on_expedition_phase_changed(phase_index: int, phase_name: String, description: String) -> void:
	ui_controller.on_expedition_phase_changed(phase_index, phase_name, description)

func _on_expedition_completed(_expedition_id: String, success: bool, rewards: Dictionary) -> void:
	ui_controller.on_expedition_completed(success, rewards)
	await get_tree().create_timer(3.0).timeout
	ui_controller.on_expedition_result_dismissed()
	phase_manager.on_expedition_completed()

func _on_support_used(_support_type: String, remaining: int) -> void:
	ui_controller.on_support_used(remaining)

func _start_expedition_battle() -> void:
	if expedition_battle == null:
		phase_manager.on_expedition_completed()
		return
	var npcs: Array = []
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit and is_instance_valid(hero):
			npcs.append(hero)
	if npcs.is_empty():
		phase_manager.on_expedition_completed()
		return
	expedition_battle.start_battle(npcs, self, expedition_manager)

func _on_expedition_battle_ended(_reason: String) -> void:
	pass

# ============================================================
# 建筑 / 游戏结束
# ============================================================

# ============================================================
# 英雄死亡 / 复活
# ============================================================

## 新波次开始：复活所有己方单位并恢复满状态
func _revive_all_allies() -> void:
	# 复活/满血英雄
	if is_instance_valid(current_hero):
		if not current_hero.stats.is_alive():
			var respawn_pos: Vector2 = fortress_position + Vector2(30, 0)
			current_hero.respawn(respawn_pos)
			print("[GameSession] 新波次: 英雄已复活")
		else:
			current_hero.stats.current_hp = current_hero.stats.max_hp
			current_hero.stats.health_changed.emit(current_hero.stats.current_hp, current_hero.stats.max_hp)
	# 取消英雄复活计时器（如果正在倒计时）
	if _respawn_timer and not _respawn_timer.is_stopped():
		_respawn_timer.stop()
	# 复活/满血 NPC
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for node: Node in heroes:
		if node is NPCUnit:
			var npc: NPCUnit = node as NPCUnit
			if npc.is_dead():
				npc.respawn_at()
				print("[GameSession] 新波次: NPC %s 已复活" % npc.npc_type)
			else:
				npc.full_heal()


func _on_hero_died() -> void:
	print("[GameSession] 英雄阵亡！%0.0f 秒后复活..." % RESPAWN_DELAY)
	# 扣除堡垒 HP 作为惩罚
	var penalty: int = maxi(int(GameManager.max_shared_hp * 0.1), 5)
	GameManager.take_shared_damage(penalty)
	# 启动复活计时器
	if _respawn_timer == null:
		_respawn_timer = Timer.new()
		_respawn_timer.one_shot = true
		_respawn_timer.timeout.connect(_on_respawn_timer_timeout)
		add_child(_respawn_timer)
	_respawn_timer.start(RESPAWN_DELAY)


func _on_respawn_timer_timeout() -> void:
	var respawn_pos: Vector2 = fortress_position + Vector2(30, 0)
	if is_instance_valid(current_hero):
		# 英雄节点还在（只是禁用了），原地复活
		current_hero.respawn(respawn_pos)
	else:
		# 英雄节点已销毁，重新生成
		_spawn_hero("wolf_knight")
	print("[GameSession] 英雄已复活!")


func _on_building_placed(building: Node, _grid_pos: Variant) -> void:
	if BuildingManager and BuildingManager.has_method("register_building"):
		BuildingManager.register_building(building)

func _on_town_level_up(_new_level: int) -> void:
	phase_manager.pending_card_selection = true

func _on_game_over(victory: bool) -> void:
	ui_controller.show_game_over(victory, {
		"kill_count": GameManager.kill_count,
		"total_damage": GameManager.total_damage_dealt,
		"gold_earned": GameManager.resources.get("gold", 0),
		"crystal_earned": GameManager.resources.get("crystal", 0),
		"waves_survived": wave_spawner.current_wave_index,
		"town_level": GameManager.town_level,
	})
